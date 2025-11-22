import Foundation
import RealmSwift

/// Realm model for storing package analysis results
class PackageResult: Object {
    @Persisted(primaryKey: true) var name: String = ""
    @Persisted var downloadRank: Int = 0
    @Persisted var androidSupport: String = "unknown" // "supported", "not_available", "pure_python", "unknown"
    @Persisted var iosSupport: String = "unknown"
    @Persisted var androidVersion: String? = nil
    @Persisted var iosVersion: String? = nil
    @Persisted var source: String = "pypi" // "pypi", "pyswift", "kivyschool"
    @Persisted var category: String = "unchecked" // "official_binary", "pyswift_binary", "kivyschool_binary", "pure_python", "binary_without_mobile", "unchecked"
    @Persisted var isProcessed: Bool = false
    
    // One-to-many: This package depends on these packages
    @Persisted var dependencies: List<PackageResult> = List<PackageResult>()
    
    // Inverse relationship: Packages that depend on this package (many-to-one from their perspective)
    @Persisted(originProperty: "dependencies") var dependents: LinkingObjects<PackageResult>
    
    @Persisted var allDepsSupported: Bool = true
    @Persisted var lastUpdated: Date = Date()
    
    convenience init(name: String, downloadRank: Int) {
        self.init()
        self.name = name
        self.downloadRank = downloadRank
        self.lastUpdated = Date()
    }
}

/// Manager for Realm database operations
class PackageDatabase {
    private let realm: Realm
    
    init(path: String? = nil) throws {
        var config = Realm.Configuration()
        
        if let path = path {
            config.fileURL = URL(fileURLWithPath: path)
        } else {
            // Default to current directory
            config.fileURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("mobile-wheels.realm")
        }
        
        config.schemaVersion = 2
        
        // Migration block for schema changes
        config.migrationBlock = { migration, oldSchemaVersion in
            if oldSchemaVersion < 2 {
                // Migrate from List<String> to List<PackageResult>
                migration.enumerateObjects(ofType: PackageResult.className()) { oldObject, newObject in
                    // Old dependencies were strings, now they're relationships
                    // Leave empty, relationships will be rebuilt on next dependency check
                    if let newObj = newObject {
                        newObj["dependencies"] = List<PackageResult>()
                    }
                }
            }
        }
        
        self.realm = try Realm(configuration: config)
        print("📦 Realm database: \(config.fileURL?.path ?? "unknown")")
    }
    
    /// Add or update a package in the database
    func upsertPackage(name: String, downloadRank: Int) throws {
        try realm.write {
            if let existing = realm.object(ofType: PackageResult.self, forPrimaryKey: name) {
                existing.downloadRank = downloadRank
                existing.lastUpdated = Date()
            } else {
                let package = PackageResult(name: name, downloadRank: downloadRank)
                realm.add(package)
            }
        }
    }
    
    /// Update package with analysis results
    func updatePackageResults(
        name: String,
        androidSupport: String,
        iosSupport: String,
        androidVersion: String?,
        iosVersion: String?,
        source: String,
        category: String
    ) throws {
        try realm.write {
            guard let package = realm.object(ofType: PackageResult.self, forPrimaryKey: name) else {
                return
            }
            
            package.androidSupport = androidSupport
            package.iosSupport = iosSupport
            package.androidVersion = androidVersion
            package.iosVersion = iosVersion
            package.source = source
            package.category = category
            package.isProcessed = true
            package.lastUpdated = Date()
        }
    }
    
    /// Update package dependencies
    func updatePackageDependencies(name: String, dependencyNames: [String], allSupported: Bool) throws {
        try realm.write {
            guard let package = realm.object(ofType: PackageResult.self, forPrimaryKey: name) else {
                return
            }
            
            // Clear existing dependencies
            package.dependencies.removeAll()
            
            // Find and link dependency PackageResult objects
            for depName in dependencyNames {
                if let depPackage = realm.object(ofType: PackageResult.self, forPrimaryKey: depName) {
                    package.dependencies.append(depPackage)
                } else {
                    // Create a placeholder for missing dependencies
                    let placeholder = PackageResult(name: depName, downloadRank: 999999)
                    realm.add(placeholder, update: .modified)
                    package.dependencies.append(placeholder)
                }
            }
            
            package.allDepsSupported = allSupported
            package.lastUpdated = Date()
        }
    }
    
    /// Get all packages sorted by download rank
    func getPackagesSortedByRank() -> Results<PackageResult> {
        return realm.objects(PackageResult.self).sorted(byKeyPath: "downloadRank")
    }
    
    /// Get unprocessed packages sorted by download rank
    func getUnprocessedPackages(limit: Int? = nil) -> [PackageResult] {
        let results = realm.objects(PackageResult.self)
            .filter("isProcessed == false")
            .sorted(byKeyPath: "downloadRank")
        
        if let limit = limit {
            return Array(results.prefix(limit))
        }
        
        return Array(results)
    }
    
    /// Get package by name
    func getPackage(name: String) -> PackageResult? {
        return realm.object(ofType: PackageResult.self, forPrimaryKey: name)
    }
    
    /// Get packages by category
    func getPackagesByCategory(_ category: String) -> Results<PackageResult> {
        return realm.objects(PackageResult.self)
            .filter("category == %@", category)
            .sorted(byKeyPath: "downloadRank")
    }
    
    /// Get total package count
    func getTotalPackages() -> Int {
        return realm.objects(PackageResult.self).count
    }
    
    /// Get processed package count
    func getProcessedCount() -> Int {
        return realm.objects(PackageResult.self).filter("isProcessed == true").count
    }
    
    /// Export to JSON dictionary
    func exportToJSON() -> [String: Any] {
        let packages = realm.objects(PackageResult.self).sorted(byKeyPath: "downloadRank")
        
        var packagesDict: [String: [String: Any]] = [:]
        var packagesList: [[String: Any]] = []
        
        var summary = [
            "officialBinaryWheels": 0,
            "pyswiftBinaryWheels": 0,
            "kivyschoolBinaryWheels": 0,
            "purePython": 0,
            "binaryWithoutMobile": 0,
            "androidSupport": 0,
            "iosSupport": 0,
            "bothPlatforms": 0
        ]
        
        for package in packages {
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
            
            packagesDict[package.name] = pkgDict
            packagesList.append(pkgDict)
            
            // Update summary
            switch package.category {
            case "official_binary": summary["officialBinaryWheels"]! += 1
            case "pyswift_binary": summary["pyswiftBinaryWheels"]! += 1
            case "kivyschool_binary": summary["kivyschoolBinaryWheels"]! += 1
            case "pure_python": summary["purePython"]! += 1
            case "binary_without_mobile": summary["binaryWithoutMobile"]! += 1
            default: break
            }
            
            if package.androidSupport == "supported" {
                summary["androidSupport"]! += 1
            }
            if package.iosSupport == "supported" {
                summary["iosSupport"]! += 1
            }
            if package.androidSupport == "supported" && package.iosSupport == "supported" {
                summary["bothPlatforms"]! += 1
            }
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        return [
            "metadata": [
                "generated": dateFormatter.string(from: Date()),
                "packagesChecked": packages.count,
                "dependencyChecking": false
            ] as [String: Any],
            "packages": packagesDict,
            "packagesList": packagesList,
            "summary": summary
        ]
    }
    
    /// Clear all data
    func clearAll() throws {
        try realm.write {
            realm.deleteAll()
        }
    }
}
