import Foundation
import MobilePlatformSupport
import ArgumentParser

@main
struct MobileWheelsChecker: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mobile-wheels-checker",
        abstract: "Check PyPI packages for iOS/Android wheel support",
        discussion: """
        A toolkit for analyzing Python package mobile platform support.
        
        Commands:
          • database init    - Initialize Realm database with package list
          • database process - Process packages and check wheel/dependency support
          • export           - Export database to various formats (JSON, Markdown, SQL)
          • inspect          - Inspect database contents and download counts
        
        Workflow:
          1. mobile-wheels-checker database init --limit 1000
          2. mobile-wheels-checker database process --concurrent 20
          3. mobile-wheels-checker export --json --markdown
        """,
        version: "2.0.0",
        subcommands: [Database.self, Export.self, Inspect.self],
        defaultSubcommand: Database.self
    )
}

// MARK: - Database Command
struct Database: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "database",
        abstract: "Database operations (init, process, update)",
        subcommands: [Init.self, Process.self, Update.self],
        defaultSubcommand: Init.self
    )
}

// MARK: - Database Init
extension Database {
    struct Init: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Initialize Realm database with package list",
            discussion: """
            Downloads package list from PyPI and initializes Realm database.
            Does NOT process packages - use 'database process' for that.
            
            Example:
              mobile-wheels-checker database init --limit 5000
              mobile-wheels-checker database init --all --database my-data.realm
            """
        )
        
        @Argument(help: "Number of packages to add (0 = all packages)")
        var limit: Int = 1000
        
        @Flag(name: .shortAndLong, help: "Use PyPI Simple Index (all ~700k packages)")
        var all: Bool = false
        
        @Option(name: .shortAndLong, help: "Database file path (default: mobile-wheels.realm)")
        var database: String?
        
        @Option(name: .shortAndLong, help: "Output directory for database file")
        var output: String?
        
        mutating func validate() throws {
            guard limit >= 0 else {
                throw ValidationError("Limit must be non-negative (0 = all packages)")
            }
        }
        
        func run() async throws {
            print("🔍 Mobile Wheels Checker - Database Initialization")
            print("==================================================\n")
            
            let outputDir = output ?? FileManager.default.currentDirectoryPath
            let dbPath = database ?? (outputDir as NSString).appendingPathComponent("mobile-wheels.realm")
            
            // Download package list
            let packagesWithCounts: [(String, Int)]
            if all {
                print("📥 Downloading all packages from PyPI Simple Index...")
                let allPackages = try await MobileWheelsCheckerCore.downloadAllPackages()
                print("📦 Found \(allPackages.count) packages\n")
                // For all packages, we don't have download counts, so use 0
                packagesWithCounts = allPackages.map { ($0, 0) }
            } else {
                print("📥 Downloading top \(limit == 0 ? "all" : "\(limit)") packages from PyPI...")
                let (downloaded, _) = try await MobileWheelsCheckerCore.downloadTopPackages(limit: limit)
                packagesWithCounts = downloaded
                print("📦 Downloaded \(packagesWithCounts.count) packages with download counts\n")
            }
            
            // Filter out non-mobile packages
            let mobilePackages = packagesWithCounts.filter { !MobileWheelsCheckerCore.isExcluded($0.0) }
            let excluded = packagesWithCounts.count - mobilePackages.count
            print("🔍 Filtered to \(mobilePackages.count) mobile-compatible packages (removed \(excluded) GPU/CUDA/Windows/non-mobile packages)\n")
            
            // Initialize database
            let db = try PackageDatabase(path: dbPath)
            print("💾 Database: \(dbPath)\n")
            
            print("📝 Initializing database with \(mobilePackages.count) packages...")
            let batchSize = 1000
            var initializedCount = 0
            
            for batchStart in stride(from: 0, to: mobilePackages.count, by: batchSize) {
                let batchEnd = min(batchStart + batchSize, mobilePackages.count)
                let batch = mobilePackages[batchStart..<batchEnd]
                
                let batchData = batch.map { (name, downloads) in
                    (name: name, numberOfDownloads: downloads)
                }
                
                try db.upsertPackagesBatch(packages: batchData)
                
                initializedCount += batchData.count
                let percentage = Int((Double(initializedCount) / Double(mobilePackages.count)) * 100)
                print("\r\u{001B}[K[\(initializedCount)/\(mobilePackages.count)] [\(percentage)%] updating database...", terminator: "")
                fflush(stdout)
            }
            
            print("\n✅ Database initialized with \(mobilePackages.count) packages")
            print("\n📊 Database stats:")
            print("  - Total packages: \(db.getTotalPackages())")
            print("  - Unprocessed: \(db.getUnprocessedPackages().count)")
            print("  - Database file: \(dbPath)")
        }
    }
}

// MARK: - Database Process
extension Database {
    struct Process: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
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
        
        @Flag(name: .long, help: "Enable recursive dependency checking")
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
            var results: [PackageInfo] = []
            
            for batchStart in stride(from: 0, to: packagesToCheck.count, by: concurrent) {
                let batchEnd = min(batchStart + concurrent, packagesToCheck.count)
                let batch = Array(packagesToCheck[batchStart..<batchEnd])
                
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
                    
                    var collected: [(String, PackageInfo?)] = []
                    for await result in group {
                        collected.append(result)
                    }
                    return collected
                }
                
                var dbUpdates: [(name: String, androidSupport: PlatformSupportCategory, iosSupport: PlatformSupportCategory,
                               androidVersion: String?, iosVersion: String?, latestVersion: String?,
                               source: PackageSourceIndex, category: PackageCategoryType)] = []
                
                for (_, packageInfo) in batchResults {
                    processedCount += 1
                    
                    if let info = packageInfo {
                        results.append(info)
                        
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
            
            // Check dependencies if enabled
            if deps {
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
                        
                        try? db.updatePackageDependencies(
                            name: package.name,
                            dependencyNames: dependencies.map { $0.name },
                            status: depStatus
                        )
                    } catch {
                        print("    ⚠️  Failed to check dependencies: \(error.localizedDescription)")
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

// MARK: - Database Update
extension Database {
    struct Update: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Re-process packages (force update existing data)",
            discussion: """
            Re-analyzes packages even if already processed. Useful for:
              • Adding dependency checking (--deps) to existing data
              • Re-checking packages after schema changes
              • Updating data with new analysis features
            
            Example:
              mobile-wheels-checker database update --deps --concurrent 20
              mobile-wheels-checker database update --limit 100 --database my-data.realm
            """
        )
        
        @Option(name: .shortAndLong, help: "Database file path (default: mobile-wheels.realm)")
        var database: String?
        
        @Option(name: .shortAndLong, help: "Output directory")
        var output: String?
        
        @Option(name: .shortAndLong, help: "Number of concurrent requests (1-50)")
        var concurrent: Int = 10
        
        @Option(name: .shortAndLong, help: "Limit number of packages to update (0 = all)")
        var limit: Int = 0
        
        @Flag(name: .long, help: "Enable recursive dependency checking")
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
            if deps {
                print("📦 Dependency checking: ENABLED")
            }
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
            var results: [PackageInfo] = []
            
            for batchStart in stride(from: 0, to: packageNames.count, by: concurrent) {
                let batchEnd = min(batchStart + concurrent, packageNames.count)
                let batch = Array(packageNames[batchStart..<batchEnd])
                
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
                    
                    var collected: [(String, PackageInfo?)] = []
                    for await result in group {
                        collected.append(result)
                    }
                    return collected
                }
                
                var dbUpdates: [(name: String, androidSupport: PlatformSupportCategory, iosSupport: PlatformSupportCategory,
                               androidVersion: String?, iosVersion: String?, latestVersion: String?,
                               source: PackageSourceIndex, category: PackageCategoryType)] = []
                
                for (_, packageInfo) in batchResults {
                    processedCount += 1
                    
                    if let info = packageInfo {
                        results.append(info)
                        
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
                        
                        // Update package dependencies
                        try? db.updatePackageDependencies(
                            name: package.name,
                            dependencyNames: dependencies.map { $0.name },
                            status: depStatus
                        )
                    } catch {
                        print("    ⚠️  Failed to check dependencies: \(error.localizedDescription)")
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

// MARK: - Export Command
struct Export: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export database to various formats",
        discussion: """
        Exports analyzed package data to JSON, Markdown, or SQL formats.
        Requires existing database with processed packages.
        
        Example:
          mobile-wheels-checker export --json --markdown
          mobile-wheels-checker export --sql --database my-data.realm
        """
    )
    
    @Option(name: .shortAndLong, help: "Database file path (default: mobile-wheels.realm)")
    var database: String?
    
    @Option(name: .shortAndLong, help: "Output directory for exported files")
    var output: String?
    
    @Flag(name: .shortAndLong, help: "Export to JSON format")
    var json: Bool = false
    
    @Flag(name: .shortAndLong, help: "Export to Markdown format")
    var markdown: Bool = false
    
    @Flag(name: .shortAndLong, help: "Export to SQL format (to be implemented)")
    var sql: Bool = false
    
    mutating func validate() throws {
        guard json || markdown || sql else {
            throw ValidationError("At least one export format must be specified (--json, --markdown, or --sql)")
        }
    }
    
    @MainActor
    func run() async throws {
        print("🔍 Mobile Wheels Checker - Export")
        print("==================================\n")
        
        let outputDir = output ?? FileManager.default.currentDirectoryPath
        let dbPath = database ?? (outputDir as NSString).appendingPathComponent("mobile-wheels.realm")
        
        guard FileManager.default.fileExists(atPath: dbPath) else {
            throw ValidationError("Database not found at \(dbPath)")
        }
        
        let db = try PackageDatabase(path: dbPath)
        print("💾 Using database: \(dbPath)")
        print("📊 Stats: \(db.getProcessedCount())/\(db.getTotalPackages()) packages processed\n")
        
        // Export JSON
        if json {
            print("📤 Exporting to JSON...")
            let jsonData = db.exportToJSON()
            let jsonFilename = (outputDir as NSString).appendingPathComponent("mobile-wheels-results.json")
            
            let jsonOutput = try JSONSerialization.data(withJSONObject: jsonData, options: [.prettyPrinted, .sortedKeys])
            try jsonOutput.write(to: URL(fileURLWithPath: jsonFilename))
            
            print("✅ JSON exported: \(jsonFilename)")
            
            // Also create JSON chunks if large dataset
            let packages = db.getPackagesSortedByRank()
            let processed = Array(packages.filter { $0.isProcessed })
            
            if processed.count > 1000 {
                try await ExportHelpers.exportJSONChunks(
                    packagesArray: processed,
                    outputDir: outputDir,
                    db: db
                )
                print("✅ JSON chunks exported to: \(outputDir)/json-chunks/")
            }
        }
        
        // Export Markdown
        if markdown {
            print("📤 Exporting to Markdown...")
            
            // TODO: Implement markdown export from database
            // For now, show placeholder
            let markdownFilename = (outputDir as NSString).appendingPathComponent("mobile-wheels-results.md")
            let placeholder = """
            # Mobile Wheels Support Report
            
            Generated from database: \(dbPath)
            Total packages: \(db.getTotalPackages())
            Processed: \(db.getProcessedCount())
            
            (Markdown export to be implemented)
            """
            try placeholder.write(toFile: markdownFilename, atomically: true, encoding: .utf8)
            print("✅ Markdown exported: \(markdownFilename)")
        }
        
        // Export SQL
        if sql {
            print("📤 Exporting to SQL...")
            
            // TODO: Implement SQL export
            let sqlFilename = (outputDir as NSString).appendingPathComponent("mobile-wheels-results.sql")
            let placeholder = """
            -- Mobile Wheels Support Database Export
            -- Generated from: \(dbPath)
            -- Total packages: \(db.getTotalPackages())
            -- Processed: \(db.getProcessedCount())
            
            -- SQL export to be implemented
            """
            try placeholder.write(toFile: sqlFilename, atomically: true, encoding: .utf8)
            print("✅ SQL exported: \(sqlFilename)")
        }
    }
}

// MARK: - Inspect Command
struct Inspect: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Inspect Realm database and show download counts"
    )
    
    @Option(name: .shortAndLong, help: "Database file path (default: mobile-wheels.realm)")
    var database: String?
    
    @Option(name: .shortAndLong, help: "Number of packages to show")
    var limit: Int = 10
    
    @MainActor
    mutating func run() async throws {
        let dbPath = database ?? "mobile-wheels.realm"
        
        print("🔍 Mobile Wheels Checker - Database Inspector")
        print(String(repeating: "=", count: 50))
        print()
        
        let db = try PackageDatabase(path: dbPath)
        
        let packages = db.getPackagesSortedByRank()
        
        print("📊 Top \(limit) packages by download count:")
        print(String(repeating: "-", count: 70))
        
        for (index, package) in packages.prefix(limit).enumerated() {
            print("\n\(index + 1). \(package.name)")
            print("   📥 Downloads: \(package.numberOfDownloads.formatted())")
            print("   🤖 Android: \(package.androidSupport.description) | 🍎 iOS: \(package.iosSupport.description)")
            print("   ✓  Processed: \(package.isProcessed ? "Yes" : "No")")
            if !package.dependencies.isEmpty {
                print("   📦 Dependencies: \(package.dependencies.count) | Status: \(package.dependencyStatus.description)")
            }
        }
        
        print("\n" + String(repeating: "=", count: 70))
        print("📊 Database Statistics:")
        print("  - Total packages: \(packages.count)")
        print("  - Processed: \(packages.filter("isProcessed == true").count)")
        print("  - Packages with downloads > 0: \(packages.filter("numberOfDownloads > 0").count)")
        print("  - Packages with downloads = 0: \(packages.filter("numberOfDownloads == 0").count)")
    }
}
