import Foundation
import ArgumentParser

// MARK: - Inspect Command
struct Inspect: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Inspect Realm database and show download counts"
    )
    
    @Option(name: .shortAndLong, help: "Database file path (default: mobile-wheels.realm)")
    var database: String?
    
    @Option(name: .shortAndLong, help: "Number of packages to show")
    var limit: Int = 10
    
    @Flag(name: .long, help: "Show detailed dependency information")
    var showDeps: Bool = false
    
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
                if showDeps {
                    for dep in package.dependencies {
                        let androidIcon = dep.androidSupport == .success || dep.androidSupport == .purePython ? "✅" : 
                                         dep.androidSupport == .warning ? "⚠️" : "❓"
                        let iosIcon = dep.iosSupport == .success || dep.iosSupport == .purePython ? "✅" : 
                                     dep.iosSupport == .warning ? "⚠️" : "❓"
                        print("      → \(dep.name): Android \(androidIcon) iOS \(iosIcon)")
                    }
                }
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
