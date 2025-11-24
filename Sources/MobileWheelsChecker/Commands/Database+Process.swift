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
        var dependencyCache: [String: PackageInfo] = [:] // Shared cache for dependencies
        
        // OPTIMIZED: Pipeline processing - fetch packages + dependencies together, single batch write
        for batchStart in stride(from: 0, to: packagesToCheck.count, by: concurrent) {
            let batchEnd = min(batchStart + concurrent, packagesToCheck.count)
            let batch = Array(packagesToCheck[batchStart..<batchEnd])
            
            // Phase 1: Fetch package info concurrently
            let packageResults = await withTaskGroup(of: (String, PackageInfo?, [String]).self, returning: [(String, PackageInfo?, [String])].self) { group in
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
            
            // Phase 2: Fetch dependencies for all packages in batch concurrently
            let fullResults = await withTaskGroup(of: (PackageInfo, [PackageInfo], DependencyStatus)?.self, returning: [(PackageInfo, [PackageInfo], DependencyStatus)].self) { group in
                for (_, packageInfo, depNames) in packageResults {
                    if let info = packageInfo {
                        group.addTask { [dependencyCache] in
                            // Fetch dependencies in parallel with caching
                            let (dependencies, _) = await DependencyHelpers.fetchDependenciesParallel(
                                depNames: depNames,
                                checker: checker,
                                db: db,
                                cache: dependencyCache
                            )
                            
                            // Determine dependency status
                            let depStatus = DependencyHelpers.determineDependencyStatus(dependencies: dependencies)
                            
                            return (info, dependencies, depStatus)
                        }
                    }
                }
                
                var collected: [(PackageInfo, [PackageInfo], DependencyStatus)] = []
                for await result in group {
                    if let result = result {
                        collected.append(result)
                    }
                }
                return collected
            }
            
            // Phase 3: Single batch write for packages + dependencies (OPTIMIZED!)
            if !fullResults.isEmpty {
                try? db.updatePackagesWithDependenciesBatch(updates: fullResults)
            }
            
            processedCount += fullResults.count
            let percentage = Int((Double(processedCount) / Double(packagesToCheck.count)) * 100)
            print("\r\u{001B}[K[\(processedCount)/\(packagesToCheck.count)] [\(percentage)% done] processing...", terminator: "")
            fflush(stdout)
        }
        
        print("\n✅ Completed processing")
        print()
        
        print("📊 Final stats:")
        print("  - Total packages: \(db.getTotalPackages())")
        print("  - Processed: \(db.getProcessedCount())")
        print("  - Database file: \(dbPath)")
    }
    }
}
