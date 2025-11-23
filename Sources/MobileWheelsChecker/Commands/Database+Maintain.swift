import Foundation
import ArgumentParser
import MobilePlatformSupport

// MARK: - Database Maintain
extension Database {
    struct Maintain: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "maintain",
            abstract: "Maintain database with smart dependency updates",
            discussion: """
            Updates all packages and selectively updates dependencies based on age.
            Only checks dependencies for packages where more than X days have passed
            since the last dependency update.
            
            This is ideal for automated maintenance:
              • Always updates wheel availability (fast)
              • Checks dependencies only when threshold is reached (efficient)
              • Default: 14 days between dependency checks
            
            Example:
              mobile-wheels-checker database maintain
              mobile-wheels-checker database maintain --days 7 --concurrent 50
              mobile-wheels-checker database maintain --days 30 --limit 1000
            """
        )
    
    @Option(name: .shortAndLong, help: "Database file path (default: mobile-wheels.realm)")
    var database: String?
    
    @Option(name: .shortAndLong, help: "Output directory")
    var output: String?
    
    @Option(name: .shortAndLong, help: "Number of concurrent requests (1-50)")
    var concurrent: Int = 10
    
    @Option(name: .shortAndLong, help: "Limit number of packages to maintain (0 = all processed)")
    var limit: Int = 0
    
    @Option(name: .shortAndLong, help: "Days threshold for dependency updates")
    var days: Int = 14
    
    mutating func validate() throws {
        guard concurrent >= 1 && concurrent <= 50 else {
            throw ValidationError("Concurrent must be between 1 and 50")
        }
        guard limit >= 0 else {
            throw ValidationError("Limit must be non-negative")
        }
        guard days > 0 else {
            throw ValidationError("Days threshold must be positive")
        }
    }
    
    @MainActor
    func run() async throws {
        print("🔧 Mobile Wheels Checker - Maintain Database")
        print("===========================================\n")
        
        let outputDir = output ?? FileManager.default.currentDirectoryPath
        let dbPath = database ?? (outputDir as NSString).appendingPathComponent("mobile-wheels.realm")
        
        // Check if database exists
        guard FileManager.default.fileExists(atPath: dbPath) else {
            throw ValidationError("Database not found at \(dbPath). Run 'database init' first.")
        }
        
        let db = try PackageDatabase(path: dbPath)
        
        print("💾 Database: \(dbPath)")
        print("📊 Total packages: \(db.getTotalPackages())")
        print("⚙️  Concurrent requests: \(concurrent)")
        print("📅 Dependency update threshold: \(days) days")
        print()
        
        // Get all packages (including processed ones)
        let allPackages = db.getPackagesSortedByRank()
        let packagesToUpdate = limit > 0 ? Array(allPackages.prefix(limit)) : Array(allPackages)
        
        // Extract package names on main thread to avoid cross-thread Realm access
        let packageNames = packagesToUpdate.map { $0.name }
        
        print("📋 Packages to maintain: \(packageNames.count)")
        print()
        
        // Load package indices
        let checker = MobilePlatformSupport()
        
        // Pre-fetch indexes to avoid duplicate log messages in concurrent tasks
        _ = try? await checker.fetchPySwiftPackages()
        _ = try? await checker.fetchKivySchoolPackages()
        
        print("🔄 Updating package information...\n")
        
        var processedCount = 0
        var results: [(info: PackageInfo, dependencies: [String])] = []
        
        // Process packages in batches with concurrency control
        for batchStart in stride(from: 0, to: packageNames.count, by: concurrent) {
            let batchEnd = min(batchStart + concurrent, packageNames.count)
            let batchNames = Array(packageNames[batchStart..<batchEnd])
            
            let batchResults = await withTaskGroup(of: (String, PackageInfo?, [String]).self, returning: [(String, PackageInfo?, [String])].self) { group in
                for name in batchNames {
                    group.addTask {
                        do {
                            if let result = try await checker.annotatePackage(name) {
                                return (name, result.info, result.dependencies)
                            } else {
                                return (name, nil, [])
                            }
                        } catch {
                            return (name, nil, [])
                        }
                    }
                }
                
                var collected: [(String, PackageInfo?, [String])] = []
                for await result in group {
                    collected.append(result)
                }
                return collected
            }
            
            // Write results on main thread
            for (_, packageInfo, depNames) in batchResults {
                if let info = packageInfo {
                    results.append((info, depNames))
                    
                    // Update package in database
                    try? db.updatePackageResults(
                        name: info.name,
                        androidSupport: info.android.map { RealmHelpers.platformSupportToCategory($0) } ?? .unknown,
                        iosSupport: info.ios.map { RealmHelpers.platformSupportToCategory($0) } ?? .unknown,
                        androidVersion: info.androidVersion,
                        iosVersion: info.iosVersion,
                        latestVersion: info.version,
                        source: info.source.map { RealmHelpers.packageIndexToSource($0) } ?? .pypi,
                        category: RealmHelpers.categorizePackage(info)
                    )
                }
                
                processedCount += 1
                let percentage = Int((Double(processedCount) / Double(packageNames.count)) * 100)
                print("\r\u{001B}[K[\(processedCount)/\(packageNames.count)] [\(percentage)% done] updating...", terminator: "")
                fflush(stdout)
            }
        }
        
        print("\n✅ Completed package updates\n")
        
        // Filter packages that need dependency updates based on threshold
        let threshold = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        var packagesNeedingDepUpdate: [(info: PackageInfo, dependencies: [String])] = []
        
        for (info, depNames) in results {
            if let package = db.getPackage(name: info.name),
               package.dependenciesUpdated < threshold {
                packagesNeedingDepUpdate.append((info, depNames))
            }
        }
        
        if packagesNeedingDepUpdate.isEmpty {
            print("✨ All packages have up-to-date dependencies (within \(days) days)")
        } else {
            print("🔍 Checking dependencies for \(packagesNeedingDepUpdate.count) packages (older than \(days) days)...\n")
            
            var depCheckedCount = 0
            
            // Process dependencies in batches with concurrency control
            for batchStart in stride(from: 0, to: packagesNeedingDepUpdate.count, by: concurrent) {
                let batchEnd = min(batchStart + concurrent, packagesNeedingDepUpdate.count)
                let batch = Array(packagesNeedingDepUpdate[batchStart..<batchEnd])
                
                let batchResults = await withTaskGroup(of: (String, [String], [PackageInfo], DependencyStatus)?.self) { group in
                    for (package, depNames) in batch {
                        group.addTask {
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
                                
                                let androidCat = RealmHelpers.platformSupportToCategory(android)
                                let iosCat = RealmHelpers.platformSupportToCategory(ios)
                                
                                // Warning means no binary wheels, which could be problematic
                                if androidCat == .warning || iosCat == .warning {
                                    hasUnsupportedDep = true
                                }
                            }
                            
                            if hasUnsupportedDep {
                                depStatus = .error
                            } else if hasMissingDep {
                                depStatus = .warning
                            }
                            
                            return (package.name, depNames, dependencies, depStatus)
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
                    guard let (packageName, _, dependencies, depStatus) = result else { continue }
                    
                    try? db.updatePackageDependenciesWithInfo(
                        name: packageName,
                        dependencyInfo: dependencies,
                        status: depStatus
                    )
                    
                    depCheckedCount += 1
                    let percentage = Int((Double(depCheckedCount) / Double(packagesNeedingDepUpdate.count)) * 100)
                    print("\r\u{001B}[K[\(depCheckedCount)/\(packagesNeedingDepUpdate.count)] [\(percentage)%] processing dependencies...", terminator: "")
                    fflush(stdout)
                }
            }
            print()
        }
        
        print("📊 Final stats:")
        print("  - Total packages: \(db.getTotalPackages())")
        print("  - Processed: \(db.getProcessedCount())")
        print("  - Dependencies updated: \(packagesNeedingDepUpdate.count)")
        print("  - Database file: \(dbPath)")
    }
    }
}
