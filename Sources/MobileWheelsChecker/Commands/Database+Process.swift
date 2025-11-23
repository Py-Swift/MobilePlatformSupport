import Foundation
import ArgumentParser
import MobilePlatformSupport

// MARK: - Database Process
extension Database {
    struct Process: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "process",
            abstract: "Process packages and check wheel/dependency support",
            discussion: """
            Analyzes packages for mobile platform support and updates database.
            Requires existing database initialized with 'database init'.
            
            Example:
              mobile-wheels-checker database process --concurrent 20
              mobile-wheels-checker database process --deps --database my-data.realm
            """
        )
    
    @Option(name: .shortAndLong, help: "Database file path (default: mobile-wheels.realm)")
    var database: String?
    
    @Option(name: .shortAndLong, help: "Output directory")
    var output: String?
    
    @Option(name: .shortAndLong, help: "Number of concurrent requests (1-50)")
    var concurrent: Int = 10
    
    @Option(name: .shortAndLong, help: "Limit number of packages to process (0 = all unprocessed)")
    var limit: Int = 0
    
    mutating func validate() throws {
        guard concurrent >= 1 && concurrent <= 50 else {
            throw ValidationError("Concurrent must be between 1 and 50")
        }
        guard limit >= 0 else {
            throw ValidationError("Limit must be non-negative")
        }
    }
    
    @MainActor
    func run() async throws {
        print("🔍 Mobile Wheels Checker - Process Packages")
        print("============================================\n")
        
        let outputDir = output ?? FileManager.default.currentDirectoryPath
        let dbPath = database ?? (outputDir as NSString).appendingPathComponent("mobile-wheels.realm")
        
        // Check if database exists
        guard FileManager.default.fileExists(atPath: dbPath) else {
            throw ValidationError("Database not found at \(dbPath). Run 'database init' first.")
        }
        
        let db = try PackageDatabase(path: dbPath)
        print("💾 Using database: \(dbPath)")
        print("📊 Stats: \(db.getProcessedCount())/\(db.getTotalPackages()) packages processed\n")
        
        // Get unprocessed packages
        let unprocessedPackages = db.getUnprocessedPackages(limit: limit == 0 ? nil : limit)
        let packagesToCheck = unprocessedPackages.map { $0.name }
        
        guard !packagesToCheck.isEmpty else {
            print("✅ All packages already processed!")
            return
        }
        
        print("🔍 Processing \(packagesToCheck.count) packages...")
        if concurrent > 1 {
            print("(Using \(concurrent) concurrent requests)")
        }
        print()
        
        // Process packages
        let checker = MobilePlatformSupport()
        
        // Pre-fetch indexes to avoid duplicate log messages in concurrent tasks
        _ = try? await checker.fetchPySwiftPackages()
        _ = try? await checker.fetchKivySchoolPackages()
        
        var processedCount = 0
        var results: [(info: PackageInfo, dependencies: [String])] = []
        
        for batchStart in stride(from: 0, to: packagesToCheck.count, by: concurrent) {
            let batchEnd = min(batchStart + concurrent, packagesToCheck.count)
            let batch = Array(packagesToCheck[batchStart..<batchEnd])
            
            let batchResults = await withTaskGroup(of: (String, PackageInfo?, [String]).self, returning: [(String, PackageInfo?, [String])].self) { group in
                for packageName in batch {
                    group.addTask {
                        do {
                            if let result = try await checker.annotatePackage(packageName) {
                                return (packageName, result.info, result.dependencies)
                            } else {
                                return (packageName, nil, [])
                            }
                        } catch {
                            return (packageName, nil, [])
                        }
                    }
                }
                
                var collected: [(String, PackageInfo?, [String])] = []
                for await result in group {
                    collected.append(result)
                }
                return collected
            }
            
            var dbUpdates: [(name: String, androidSupport: PlatformSupportCategory, iosSupport: PlatformSupportCategory,
                           androidVersion: String?, iosVersion: String?, latestVersion: String?,
                           source: PackageSourceIndex, category: PackageCategoryType)] = []
            
            for (_, packageInfo, depNames) in batchResults {
                processedCount += 1
                
                if let info = packageInfo {
                    results.append((info, depNames))
                    
                    let androidSupport = info.android.map { RealmHelpers.platformSupportToCategory($0) } ?? .unknown
                    let iosSupport = info.ios.map { RealmHelpers.platformSupportToCategory($0) } ?? .unknown
                    let category = RealmHelpers.categorizePackage(info)
                    let source = info.source.map { RealmHelpers.packageIndexToSource($0) } ?? .pypi
                    
                    dbUpdates.append((
                        name: info.name,
                        androidSupport: androidSupport,
                        iosSupport: iosSupport,
                        androidVersion: info.androidVersion,
                        iosVersion: info.iosVersion,
                        latestVersion: info.version,
                        source: source,
                        category: category
                    ))
                }
            }
            
            try? db.updatePackageResultsBatch(updates: dbUpdates)
            
            let percentage = Int((Double(processedCount) / Double(packagesToCheck.count)) * 100)
            print("\r\u{001B}[K[\(processedCount)/\(packagesToCheck.count)] [\(percentage)% done] processing...", terminator: "")
            fflush(stdout)
        }
        
        print("\n✅ Completed processing\n")
        
        // Now process dependencies that were collected during main processing
        print("🔍 Checking dependencies (concurrent: \(concurrent))...\n")
        
        var depCheckedCount = 0
        
        // Process dependencies in batches with concurrency control
        for batchStart in stride(from: 0, to: results.count, by: concurrent) {
            let batchEnd = min(batchStart + concurrent, results.count)
            let batch = Array(results[batchStart..<batchEnd])
            
            let batchResults = await withTaskGroup(of: (String, [String], [PackageInfo], DependencyStatus)?.self) { group in
                for (package, depNames) in batch {
                    group.addTask {
                        do {
                            // Check each dependency for mobile support
                            var dependencies: [PackageInfo] = []
                            for depName in depNames {
                                // Try to annotate dependency
                                if let result = try? await checker.annotatePackage(depName) {
                                    dependencies.append(result.info)
                                }
                            }
                            
                            // Determine dependency status
                            var depStatus: DependencyStatus = .noIssues
                            var hasUnsupportedDep = false
                            var hasMissingDep = false
                            
                            for dep in dependencies {
                                guard let android = dep.android, let ios = dep.ios else {
                                    hasMissingDep = true
                                    continue
                                }
                                
                                // Check if dependency has issues (warning or no support)
                                if android == .warning || ios == .warning {
                                    hasUnsupportedDep = true
                                }
                                
                                // Check if both platforms not supported
                                if !(android == .success || android == .purePython) ||
                                   !(ios == .success || ios == .purePython) {
                                    hasUnsupportedDep = true
                                }
                            }
                            
                            if hasUnsupportedDep {
                                depStatus = .error
                            } else if hasMissingDep {
                                depStatus = .warning
                            }
                            
                            return (package.name, depNames, dependencies, depStatus)
                        } catch {
                            print("\n  Error checking \(package.name): \(error)")
                            return nil
                        }
                    }
                }
                
                var collected: [(String, [String], [PackageInfo], DependencyStatus)?] = []
                for await result in group {
                    collected.append(result)
                }
                return collected
            }
            
            // Now write to database on main thread
            for result in batchResults {
                guard let (packageName, depNames, dependencies, depStatus) = result else { continue }
                
                try? db.updatePackageDependenciesWithInfo(
                    name: packageName,
                    dependencyInfo: dependencies,
                    status: depStatus
                )
                
                depCheckedCount += 1
                let percentage = Int((Double(depCheckedCount) / Double(results.count)) * 100)
                print("\r\u{001B}[K[\(depCheckedCount)/\(results.count)] [\(percentage)%] processing dependencies...", terminator: "")
                fflush(stdout)
            }
        }
        print()
        
        print("📊 Final stats:")
        print("  - Total packages: \(db.getTotalPackages())")
        print("  - Processed: \(db.getProcessedCount())")
        print("  - Database file: \(dbPath)")
    }
    }
}
