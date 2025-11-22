import Foundation
import MobilePlatformSupport

// JSON structures matching the exported format
struct PackageJSON: Codable {
    let name: String
    let android: String
    let androidVersion: String?
    let ios: String
    let iosVersion: String?
    let source: String
    let category: String
    let dependencies: [String]?
    let allDepsSupported: Bool?
}

struct DependencyChecker {
    
    // Check dependencies from exported JSON data
    static func checkDependenciesFromJSON(jsonPath: String, limit: Int = 100, concurrent: Int = 10) async throws {
        print("🔍 Dependency Checker from JSON Export")
        print(String(repeating: "=", count: 71))
        print()
        
        // Load all packages from JSON chunks
        print("📥 Loading packages from JSON chunks...")
        let packages = try loadPackagesFromChunks(jsonPath: jsonPath)
        print("✅ Loaded \(packages.count) packages")
        print()
        
        // Initialize checker
        let checker = MobilePlatformSupport()
        
        // Check dependencies for all packages concurrently
        print("🔍 Checking dependencies for all packages...")
        print("(Using \(concurrent) concurrent requests)")
        print()
        
        var packagesWithDeps: [(PackageJSON, [String], Bool)] = []
        var processedCount = 0
        
        // Process packages in batches
        for batch in stride(from: 0, to: packages.count, by: concurrent) {
            let batchEnd = min(batch + concurrent, packages.count)
            let batchPackages = Array(packages[batch..<batchEnd])
            
            let results = await withTaskGroup(of: (PackageJSON, [String], Bool).self) { group in
                for package in batchPackages {
                    group.addTask {
                        var visited = Set<String>()
                        do {
                            let depResults = try await checker.checkWithDependencies(
                                packageName: package.name,
                                depth: 1,
                                visited: &visited
                            )
                            
                            let dependencies = depResults.filter { $0.key != package.name }.map { $0.value }
                            let depNames = dependencies.map { $0.name }
                            let allDepsSupported = dependencies.allSatisfy { dep in
                                (dep.android == .success || dep.android == .purePython) &&
                                (dep.ios == .success || dep.ios == .purePython)
                            }
                            
                            return (package, depNames, allDepsSupported)
                        } catch {
                            // If check fails, return empty deps
                            return (package, [], false)
                        }
                    }
                }
                
                var batchResults: [(PackageJSON, [String], Bool)] = []
                for await result in group {
                    batchResults.append(result)
                }
                return batchResults
            }
            
            packagesWithDeps.append(contentsOf: results)
            processedCount += batchPackages.count
            
            // Progress indicator
            let progress = (Double(processedCount) / Double(packages.count)) * 100
            print("[\(processedCount)/\(packages.count)] \(String(format: "%.1f%%", progress)) complete...")
        }
        
        // Find packages with unsupported dependencies
        let failedPackages = packagesWithDeps.filter { !$0.2 }
        let supportedPackages = packagesWithDeps.filter { $0.2 }
        
        print()
        print("📈 Summary:")
        print("- Total packages checked: \(packagesWithDeps.count)")
        print("- All dependencies supported: \(supportedPackages.count)")
        print("- Some dependencies unsupported: \(failedPackages.count)")
        
        // Display first 100 packages with unsupported dependencies
        if !failedPackages.isEmpty {
            print()
            print("⚠️  Packages with Unsupported Dependencies (first \(min(limit, failedPackages.count))):")
            print(String(repeating: "=", count: 71))
            print("\("Package".padding(toLength: 30, withPad: " ", startingAt: 0)) \("Category".padding(toLength: 20, withPad: " ", startingAt: 0)) \("Unsupported Deps".padding(toLength: 20, withPad: " ", startingAt: 0))")
            print(String(repeating: "-", count: 71))
            
            for (index, (package, deps, _)) in failedPackages.enumerated() {
                if index >= limit {
                    let remaining = failedPackages.count - limit
                    print("... +\(remaining) more")
                    break
                }
                
                let category = package.category.replacingOccurrences(of: "_", with: " ")
                let depsDisplay = deps.isEmpty ? "unknown" : "\(deps.count) deps"
                print("\(package.name.padding(toLength: 30, withPad: " ", startingAt: 0)) \(category.padding(toLength: 20, withPad: " ", startingAt: 0)) \(depsDisplay.padding(toLength: 20, withPad: " ", startingAt: 0))")
            }
            
            // Export results
            print()
            print("📝 Exporting dependency check results...")
            try exportDependencyResults(packages: packagesWithDeps, outputPath: jsonPath)
        } else {
            print()
            print("✅ All packages have supported dependencies!")
        }
    }
    
    static func loadPackagesFromChunks(jsonPath: String) throws -> [PackageJSON] {
        let fileManager = FileManager.default
        var chunksPath = jsonPath
        
        // If jsonPath is a directory, use it directly, otherwise assume it's the chunks directory
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: jsonPath, isDirectory: &isDirectory) {
            if !isDirectory.boolValue {
                chunksPath = (jsonPath as NSString).deletingLastPathComponent
            }
        }
        
        // Check if json-chunks directory exists
        let jsonChunksPath = (chunksPath as NSString).appendingPathComponent("json-chunks")
        if fileManager.fileExists(atPath: jsonChunksPath, isDirectory: &isDirectory) && isDirectory.boolValue {
            chunksPath = jsonChunksPath
        }
        
        // Find all chunk files
        let contents = try fileManager.contentsOfDirectory(atPath: chunksPath)
        let chunkFiles = contents.filter { $0.hasPrefix("chunk-") && $0.hasSuffix(".json") }
            .sorted()
        
        guard !chunkFiles.isEmpty else {
            throw NSError(domain: "DependencyChecker", code: 1, 
                         userInfo: [NSLocalizedDescriptionKey: "No chunk files found in \(chunksPath)"])
        }
        
        // Load all chunks
        var allPackages: [PackageJSON] = []
        let decoder = JSONDecoder()
        
        for chunkFile in chunkFiles {
            let chunkPath = (chunksPath as NSString).appendingPathComponent(chunkFile)
            let data = try Data(contentsOf: URL(fileURLWithPath: chunkPath))
            let packages = try decoder.decode([PackageJSON].self, from: data)
            allPackages.append(contentsOf: packages)
        }
        
        return allPackages
    }
    
    static func exportDependencyResults(packages: [(PackageJSON, [String], Bool)], outputPath: String) throws {
        // Update packages with dependency information
        var updatedPackages: [PackageJSON] = []
        
        for (package, deps, allSupported) in packages {
            let updated = PackageJSON(
                name: package.name,
                android: package.android,
                androidVersion: package.androidVersion,
                ios: package.ios,
                iosVersion: package.iosVersion,
                source: package.source,
                category: package.category,
                dependencies: deps.isEmpty ? nil : deps,
                allDepsSupported: allSupported
            )
            updatedPackages.append(updated)
        }
        
        // Export updated chunks
        let chunksDir = (outputPath as NSString).appendingPathComponent("json-chunks")
        let chunkSize = 5000
        let chunks = stride(from: 0, to: updatedPackages.count, by: chunkSize).map {
            Array(updatedPackages[$0..<min($0 + chunkSize, updatedPackages.count)])
        }
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        
        for (index, chunk) in chunks.enumerated() {
            let chunkFilename = "chunk-\(index + 1).json"
            let chunkPath = (chunksDir as NSString).appendingPathComponent(chunkFilename)
            let chunkData = try encoder.encode(chunk)
            try chunkData.write(to: URL(fileURLWithPath: chunkPath))
        }
        
        print("✅ Updated JSON chunks with dependency information")
    }
    
    static func checkPackageWithDependencies(packageName: String, depth: Int = 2) async {
        print("🔍 Dependency Checker for: \(packageName)")
        print(String(repeating: "=", count: 71))
        print()
        
        let checker = MobilePlatformSupport()
        
        do {
            var visited = Set<String>()
            let results = try await checker.checkWithDependencies(
                packageName: packageName,
                depth: depth,
                visited: &visited
            )
            
            guard !results.isEmpty else {
                print("❌ Package not found or has no binary wheels")
                return
            }
            
            // Separate by package type
            let mainPackage = results[packageName]
            let dependencies = results.filter { $0.key != packageName }
            
            // Display main package
            if let main = mainPackage {
                print("📦 Main Package:")
                print(String(repeating: "-", count: 71))
                displayPackage(main)
                print()
            }
            
            // Display dependencies
            if !dependencies.isEmpty {
                print("📚 Dependencies (\(dependencies.count)):")
                print(String(repeating: "-", count: 71))
                print("\("Package".padding(toLength: 30, withPad: " ", startingAt: 0)) \("Android".padding(toLength: 20, withPad: " ", startingAt: 0)) \("iOS".padding(toLength: 20, withPad: " ", startingAt: 0))")
                print(String(repeating: "-", count: 71))
                
                for (name, info) in dependencies.sorted(by: { $0.key < $1.key }) {
                    let androidStatus = formatStatus(info.android)
                    let iosStatus = formatStatus(info.ios)
                    print("\(name.padding(toLength: 30, withPad: " ", startingAt: 0)) \(androidStatus.padding(toLength: 20, withPad: " ", startingAt: 0)) \(iosStatus.padding(toLength: 20, withPad: " ", startingAt: 0))")
                }
                print()
            }
            
            // Summary
            print("📈 Summary:")
            let totalPackages = results.count
            let androidSupport = results.values.filter { $0.android == .success }.count
            let iosSupport = results.values.filter { $0.ios == .success }.count
            let bothSupport = results.values.filter { $0.android == .success && $0.ios == .success }.count
            let unsupported = results.values.filter { 
                ($0.android == .warning || $0.android == nil) && 
                ($0.ios == .warning || $0.ios == nil) 
            }.count
            
            print("- Total packages: \(totalPackages) (\(packageName) + \(dependencies.count) dependencies)")
            print("- Android support: \(androidSupport)/\(totalPackages)")
            print("- iOS support: \(iosSupport)/\(totalPackages)")
            print("- Both platforms: \(bothSupport)/\(totalPackages)")
            
            if unsupported > 0 {
                print("- ⚠️  Unsupported: \(unsupported)/\(totalPackages)")
                print("\n⚠️  Warning: Some dependencies don't have mobile support!")
            } else {
                print("\n✅ All dependencies support mobile platforms!")
            }
            
        } catch {
            print("❌ Error: \(error.localizedDescription)")
        }
    }
    
    static func displayPackage(_ package: PackageInfo) {
        print("  Name: \(package.name)")
        print("  Android: \(formatStatus(package.android))")
        print("  iOS: \(formatStatus(package.ios))")
    }
    
    static func formatStatus(_ status: PlatformSupport?) -> String {
        guard let status = status else {
            return "Unknown"
        }
        
        switch status {
        case .success:
            return "✅ Supported"
        case .purePython:
            return "🐍 Pure Python"
        case .warning:
            return "⚠️  Not available"
        }
    }
}

// Parse command line arguments
let args = ProcessInfo.processInfo.arguments

if args.count < 2 {
    print("Usage:")
    print("  dependency-checker <package-name> [depth]")
    print("    Check dependencies for a specific package")
    print("    Example: dependency-checker numpy 2")
    print()
    print("  dependency-checker --json <path> [--limit N] [--concurrent N]")
    print("    Check dependencies for all packages in JSON export")
    print("    Example: dependency-checker --json ./json-chunks --limit 100 --concurrent 20")
    print()
    exit(1)
}

// Check if using JSON mode
if args[1] == "--json" || args[1] == "-j" {
    guard args.count > 2 else {
        print("❌ Error: --json requires a path argument")
        exit(1)
    }
    
    let jsonPath = args[2]
    var limit = 100
    var concurrent = 10
    
    // Parse additional flags
    var i = 3
    while i < args.count {
        if args[i] == "--limit" && i + 1 < args.count {
            limit = Int(args[i + 1]) ?? 100
            i += 2
        } else if args[i] == "--concurrent" && i + 1 < args.count {
            concurrent = Int(args[i + 1]) ?? 10
            i += 2
        } else {
            i += 1
        }
    }
    
    do {
        try await DependencyChecker.checkDependenciesFromJSON(
            jsonPath: jsonPath,
            limit: limit,
            concurrent: concurrent
        )
    } catch {
        print("❌ Error: \(error.localizedDescription)")
        exit(1)
    }
} else {
    // Original single package mode
    let packageName = args[1]
    let depth = args.count > 2 ? Int(args[2]) ?? 2 : 2
    
    await DependencyChecker.checkPackageWithDependencies(packageName: packageName, depth: depth)
}
