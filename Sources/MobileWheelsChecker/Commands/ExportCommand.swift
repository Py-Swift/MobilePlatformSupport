import Foundation
import ArgumentParser
import MobilePlatformSupport

// MARK: - Export Command
struct Export: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export database to various formats",
        discussion: """
        Exports analyzed package data to JSON, Markdown, or SQLite formats.
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
    
    @Flag(name: .shortAndLong, help: "Export to SQLite format")
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
        
        // Export SQLite
        if sql {
            print("📤 Exporting to SQLite...")
            
            let sqliteFilename = (outputDir as NSString).appendingPathComponent("mobile-wheels-results.sqlite")
            let packages = db.getPackagesSortedByRank()
            let processed = Array(packages.filter { $0.isProcessed })
            
            try ExportHelpers.exportToSQLite(
                packagesArray: processed,
                outputPath: sqliteFilename,
                db: db
            )
            
            print("✅ SQLite database exported: \(sqliteFilename)")
            print("   - Packages: \(processed.count)")
            print("   - Tables: packages, dependencies")
            print("   - Indexes: created for optimal query performance")
        }
    }
}
