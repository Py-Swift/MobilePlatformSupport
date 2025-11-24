import Foundation
import ArgumentParser
import MobilePlatformSupport

// MARK: - Database Update
extension Database {
    struct Update: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "update",
            abstract: "Re-process packages (force update existing data)",
            discussion: """
            Re-analyzes packages even if already processed. Useful for:
              • Weekly: Update wheel availability without deps (faster)
              • Monthly: Full update with --deps (slower but comprehensive)
              • Re-checking packages after schema changes
            
            Example:
              mobile-wheels-checker database update --concurrent 20
              mobile-wheels-checker database update --deps --limit 5000 --concurrent 50
            """
        )
    
    @Option(name: .shortAndLong, help: "Database file path (default: mobile-wheels.realm)")
    var database: String?
    
    @Option(name: .shortAndLong, help: "Output directory")
    var output: String?
    
    @Option(name: .shortAndLong, help: "Number of concurrent requests (1-50)")
    var concurrent: Int = 10
    
    @Option(name: .shortAndLong, help: "Limit number of packages to update (0 = all processed)")
    var limit: Int = 0
    
    @Flag(name: .long, help: "Check and update dependencies (slower, use for monthly full updates)")
    var deps: Bool = false
    
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
        print("🔍 Mobile Wheels Checker - Update Packages")
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
        print("🔄 Mode: Force re-process (includes already processed packages)")
        print("📦 Dependency checking: \(deps ? "ENABLED" : "DISABLED")")
        print()
        
        // Get all packages (including processed ones)
        let allPackages = db.getPackagesSortedByRank()
        let packagesToUpdate = limit > 0 ? Array(allPackages.prefix(limit)) : Array(allPackages)
        
        // Extract package names on main thread to avoid cross-thread Realm access
        let packageNames = packagesToUpdate.map { $0.name }
        
        print("📋 Packages to update: \(packageNames.count)")
        print()
        
        // Process packages
        let checker = MobilePlatformSupport()
        
        // Pre-fetch indexes to avoid duplicate log messages in concurrent tasks
        _ = try? await checker.fetchPySwiftPackages()
        _ = try? await checker.fetchKivySchoolPackages()
        
        print("🔄 Re-processing packages...")
        print()
        
        var processedCount = 0
        var results: [(info: PackageInfo, dependencies: [String])] = []
        
        for batchStart in stride(from: 0, to: packageNames.count, by: concurrent) {
            let batchEnd = min(batchStart + concurrent, packageNames.count)
            let batch = Array(packageNames[batchStart..<batchEnd])
            
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
            
            let percentage = Int((Double(processedCount) / Double(packageNames.count)) * 100)
            print("\r\u{001B}[K[\(processedCount)/\(packageNames.count)] [\(percentage)% done] updating...", terminator: "")
            fflush(stdout)
        }
        
        print("\n✅ Completed update\n")
        
            // Check dependencies if enabled
            if deps {
                print("🔍 Checking dependencies (parallel + cached)...\n")
                
                var depCheckedCount = 0
                var dependencyCache: [String: PackageInfo] = [:] // Shared cache across all packages
                
                // Process dependencies in batches with concurrency control
                for batchStart in stride(from: 0, to: results.count, by: concurrent) {
                let batchEnd = min(batchStart + concurrent, results.count)
                let batch = Array(results[batchStart..<batchEnd])
                
                // Pre-fetch database lookups for all dependencies in batch (thread-safe)
                var allDepNames = Set<String>()
                for (_, depNames) in batch {
                    allDepNames.formUnion(depNames)
                }
                
                var dbLookup: [String: PackageInfo] = [:]
                for depName in allDepNames {
                    if let dbPackage = db.getPackage(name: depName),
                       dbPackage.isProcessed,
                       let latestVersion = dbPackage.latestVersion {
                        
                        // Reconstruct PackageInfo from database (value type, thread-safe)
                        let info = PackageInfo(
                            name: dbPackage.name,
                            android: dbPackage.androidSupport.toPlatformSupport(),
                            ios: dbPackage.iosSupport.toPlatformSupport(),
                            source: dbPackage.source.toPackageIndex(),
                            androidVersion: dbPackage.androidVersion,
                            iosVersion: dbPackage.iosVersion,
                            version: latestVersion
                        )
                        dbLookup[depName] = info
                    }
                }
                
                let batchResults = await withTaskGroup(of: (String, [String], [PackageInfo], DependencyStatus)?.self) { group in
                    for (package, depNames) in batch {
                        group.addTask { [dependencyCache, dbLookup] in
                            // Fetch dependencies in parallel with database-first lookup and caching
                            let (dependencies, _) = await DependencyHelpers.fetchDependenciesParallel(
                                depNames: depNames,
                                checker: checker,
                                dbLookup: dbLookup,
                                cache: dependencyCache
                            )
                            
                            // Determine dependency status
                            let depStatus = DependencyHelpers.determineDependencyStatus(dependencies: dependencies)
                            
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
                let percentage = Int((Double(depCheckedCount) / Double(results.count)) * 100)
                print("\r\u{001B}[K[\(depCheckedCount)/\(results.count)] [\(percentage)%] processing dependencies...", terminator: "")
                fflush(stdout)
            }
        }
        print()
        }
        
        print("📊 Final stats:")
        print("  - Total packages: \(db.getTotalPackages())")
        print("  - Processed: \(db.getProcessedCount())")
        print("  - Database file: \(dbPath)")
    }
    }
}
