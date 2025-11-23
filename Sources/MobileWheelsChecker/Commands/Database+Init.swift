import Foundation
import ArgumentParser
import MobilePlatformSupport

// MARK: - Database Init
extension Database {
    struct Init: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "init",
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
