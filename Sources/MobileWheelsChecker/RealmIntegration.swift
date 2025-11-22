import Foundation
import MobilePlatformSupport

extension MobileWheelsChecker {
    /// Process packages with Realm database storage
    @MainActor
    func processWithRealm(
        packages: [String],
        checker: MobilePlatformSupport,
        concurrency: Int,
        checkDeps: Bool
    ) async throws -> [PackageInfo] {
        // Initialize database
        let outputDir = output ?? FileManager.default.currentDirectoryPath
        let dbPath = (outputDir as NSString).appendingPathComponent("mobile-wheels.realm")
        let db = try PackageDatabase(path: dbPath)
        
        print("💾 Using Realm database: \(dbPath)\n")
        
        // Step 1: Insert all packages with their download ranks
        print("📝 Initializing database with \(packages.count) packages...")
        for (index, packageName) in packages.enumerated() {
            try db.upsertPackage(name: packageName, downloadRank: index + 1)
        }
        print("✅ Database initialized\n")
        
        // Step 2: Get unprocessed packages sorted by rank
        let unprocessedPackages = db.getUnprocessedPackages(limit: limit == 0 ? nil : limit)
        let packagesToCheck = unprocessedPackages.map { $0.name }
        
        print("🔍 Processing \(packagesToCheck.count) packages...")
        if concurrent > 1 {
            print("(Using \(concurrent) concurrent requests)")
        }
        print()
        
        // Step 3: Process packages and update database on the fly
        var results: [PackageInfo] = []
        var processedCount = 0
        
        // Process in batches for better progress tracking
        for batchStart in stride(from: 0, to: packagesToCheck.count, by: concurrent) {
            let batchEnd = min(batchStart + concurrent, packagesToCheck.count)
            let batch = Array(packagesToCheck[batchStart..<batchEnd])
            
            // Process batch concurrently
            let batchResults = await withTaskGroup(of: (String, PackageInfo?).self, returning: [(String, PackageInfo?)].self) { group in
                for packageName in batch {
                    group.addTask {
                        do {
                            let packageInfo = try await checker.annotatePackage(packageName)
                            return (packageName, packageInfo)
                        } catch {
                            return (packageName, nil)
                        }
                    }
                }
                
                // Collect all results first
                var collected: [(String, PackageInfo?)] = []
                for await result in group {
                    collected.append(result)
                }
                return collected
            }
            
            // Now update database sequentially on the main thread
            for (_, packageInfo) in batchResults {
                processedCount += 1
                let percentage = Int((Double(processedCount) / Double(packagesToCheck.count)) * 100)
                print("\r\u{001B}[K[\(processedCount)/\(packagesToCheck.count)] [\(percentage)% done] processing...", terminator: "")
                fflush(stdout)
                
                if let info = packageInfo {
                    results.append(info)
                    
                    // Update database immediately (now on same thread)
                    let androidSupport = Self.platformSupportToString(info.android)
                    let iosSupport = Self.platformSupportToString(info.ios)
                    let category = Self.categorizePackage(info)
                    let source = Self.sourceToString(info.source)
                    
                    try? db.updatePackageResults(
                        name: info.name,
                        androidSupport: androidSupport,
                        iosSupport: iosSupport,
                        androidVersion: info.androidVersion,
                        iosVersion: info.iosVersion,
                        source: source,
                        category: category
                    )
                }
            }
        }
        
        print("\n✅ Completed processing\n")
        
        // Step 4: Check dependencies if enabled
        if checkDeps {
            print("🔍 Checking dependencies...\n")
            for package in results {
                print("  Checking \(package.name)...")
                var visited = Set<String>()
                
                do {
                    let depResults = try await checker.checkWithDependencies(
                        packageName: package.name,
                        depth: 1,
                        visited: &visited
                    )
                    
                    let dependencies = depResults.filter { $0.key != package.name }.map { $0.value }
                    let allDepsSupported = dependencies.allSatisfy { dep in
                        (dep.android == .success || dep.android == .purePython) &&
                        (dep.ios == .success || dep.ios == .purePython)
                    }
                    
                    // Update database with dependencies
                    try? db.updatePackageDependencies(
                        name: package.name,
                        dependencyNames: dependencies.map { $0.name },
                        allSupported: allDepsSupported
                    )
                } catch {
                    print("    ⚠️  Failed to check dependencies: \(error.localizedDescription)")
                }
            }
            print()
        }
        
        // Step 5: Export JSON from database
        print("📤 Exporting JSON from database...")
        let jsonData = db.exportToJSON()
        let jsonFilename = (outputDir as NSString).appendingPathComponent("mobile-wheels-results.json")
        
        let jsonOutput = try JSONSerialization.data(withJSONObject: jsonData, options: [.prettyPrinted, .sortedKeys])
        try jsonOutput.write(to: URL(fileURLWithPath: jsonFilename))
        
        print("✅ Exported JSON: \(jsonFilename)\n")
        
        // Step 6: Also create JSON chunks for compatibility
        try await Self.exportJSONChunks(
            from: results,
            depsEnabled: checkDeps,
            outputDir: outputDir,
            limit: packagesToCheck.count,
            db: db
        )
        
        print("📊 Database stats:")
        print("  - Total packages: \(db.getTotalPackages())")
        print("  - Processed: \(db.getProcessedCount())")
        print("  - Database file: \(dbPath)")
        print()
        
        return results
    }
    
    /// Convert PlatformSupport to database string
    static func platformSupportToString(_ support: PlatformSupport?) -> String {
        guard let support = support else { return "unknown" }
        switch support {
        case .success: return "supported"
        case .purePython: return "pure_python"
        case .warning: return "not_available"
        }
    }
    
    /// Convert source to database string
    static func sourceToString(_ source: PackageIndex?) -> String {
        guard let source = source else { return "pypi" }
        switch source {
        case .pypi: return "pypi"
        case .pyswift: return "pyswift"
        case .kivyschool: return "kivyschool"
        }
    }
    
    /// Categorize package for database
    static func categorizePackage(_ package: PackageInfo) -> String {
        let hasAndroidSupport = package.android == .success
        let hasIOSSupport = package.ios == .success
        let isPurePython = package.android == .purePython || package.ios == .purePython
        let hasMobileSupport = hasAndroidSupport || hasIOSSupport
        
        if package.source == .pyswift && hasMobileSupport {
            return "pyswift_binary"
        } else if package.source == .kivyschool && hasMobileSupport {
            return "kivyschool_binary"
        } else if package.source == .pypi && hasMobileSupport {
            return "official_binary"
        } else if isPurePython {
            return "pure_python"
        } else {
            return "binary_without_mobile"
        }
    }
    
    /// Export JSON chunks from database
    @MainActor
    static func exportJSONChunks(
        from results: [PackageInfo],
        depsEnabled: Bool,
        outputDir: String,
        limit: Int,
        db: PackageDatabase
    ) async throws {
        let chunkSize = 5000
        let allPackages = db.getPackagesSortedByRank()
        let packagesArray = Array(allPackages.filter { $0.isProcessed })
        
        if packagesArray.count > 1000 {
            print("📦 Creating JSON chunks (large dataset)...")
            
            // Create chunks directory
            let chunksDir = (outputDir as NSString).appendingPathComponent("json-chunks")
            try? FileManager.default.createDirectory(atPath: chunksDir, withIntermediateDirectories: true)
            
            // Create chunks
            let totalChunks = (packagesArray.count + chunkSize - 1) / chunkSize
            var chunks: [[String: Any]] = []
            
            for chunkIndex in 0..<totalChunks {
                let startIndex = chunkIndex * chunkSize
                let endIndex = min(startIndex + chunkSize, packagesArray.count)
                let chunkPackages = Array(packagesArray[startIndex..<endIndex])
                
                var chunkData: [[String: Any]] = []
                for package in chunkPackages {
                    var pkgDict: [String: Any] = [
                        "name": package.name,
                        "android": package.androidSupport,
                        "ios": package.iosSupport,
                        "source": package.source,
                        "category": package.category
                    ]
                    
                    if let androidVersion = package.androidVersion {
                        pkgDict["androidVersion"] = androidVersion
                    }
                    if let iosVersion = package.iosVersion {
                        pkgDict["iosVersion"] = iosVersion
                    }
                    if !package.dependencies.isEmpty {
                        // Convert PackageResult relationships to array of names
                        pkgDict["dependencies"] = package.dependencies.map { $0.name }
                        pkgDict["allDepsSupported"] = package.allDepsSupported
                    }
                    
                    chunkData.append(pkgDict)
                }
                
                // Write chunk file
                let chunkFilename = (chunksDir as NSString).appendingPathComponent("chunk-\(chunkIndex + 1).json")
                let jsonOutput = try JSONSerialization.data(withJSONObject: chunkData, options: [.prettyPrinted, .sortedKeys])
                try jsonOutput.write(to: URL(fileURLWithPath: chunkFilename))
                
                chunks.append([
                    "filename": "chunk-\(chunkIndex + 1).json",
                    "start_index": startIndex,
                    "end_index": endIndex - 1,
                    "count": chunkPackages.count
                ])
            }
            
            // Create index file
            let indexData: [String: Any] = [
                "total_packages": packagesArray.count,
                "chunk_size": chunkSize,
                "total_chunks": totalChunks,
                "chunks": chunks
            ]
            
            let indexFilename = (chunksDir as NSString).appendingPathComponent("index.json")
            let jsonOutput = try JSONSerialization.data(withJSONObject: indexData, options: [.prettyPrinted, .sortedKeys])
            try jsonOutput.write(to: URL(fileURLWithPath: indexFilename))
            
            print("✅ Created \(totalChunks) JSON chunks in json-chunks/")
        }
    }
}
