import Foundation
import RealmSwift

/// Platform support status as integer enum for efficient storage
enum PlatformSupportCategory: Int, PersistableEnum {
    case unknown = 0
    case success = 1           // Has binary wheels for the platform
    case purePython = 2        // Pure Python package (works on all platforms)
    case warning = 3           // No binary wheels available
    
    var description: String {
        switch self {
        case .unknown: return "unknown"
        case .success: return "success"
        case .purePython: return "pure-python"
        case .warning: return "warning"
        }
    }
}

/// Package source index as integer enum
enum PackageSourceIndex: Int, PersistableEnum {
    case pypi = 0
    case pyswift = 1
    case kivyschool = 2
    
    var description: String {
        switch self {
        case .pypi: return "pypi"
        case .pyswift: return "pyswift"
        case .kivyschool: return "kivy-school"
        }
    }
}

/// Overall package category as integer enum
enum PackageCategoryType: Int, PersistableEnum {
    case unprocessed = 0
    case bothPlatforms = 1
    case androidOnly = 2
    case iosOnly = 3
    case purePython = 4
    case noMobileSupport = 5
    
    var description: String {
        switch self {
        case .unprocessed: return "unprocessed"
        case .bothPlatforms: return "both-platforms"
        case .androidOnly: return "android-only"
        case .iosOnly: return "ios-only"
        case .purePython: return "pure-python"
        case .noMobileSupport: return "no-mobile-support"
        }
    }
}

/// Dependency status as integer enum
enum DependencyStatus: Int, PersistableEnum {
    case noIssues = 0           // All dependencies found and supported
    case warning = 1            // One or more dependencies not found (status unknown)
    case error = 2              // Contains non-mobile binary, GPU lib, or other issues
    
    var description: String {
        switch self {
        case .noIssues: return "no-issues"
        case .warning: return "warning"
        case .error: return "error"
        }
    }
}

/// Realm model for storing package analysis results
class PackageResult: Object {
    @Persisted(primaryKey: true) var name: String = ""
    @Persisted var numberOfDownloads: Int = 0  // Actual download count from PyPI stats
    @Persisted var androidSupport: PlatformSupportCategory = .unknown
    @Persisted var iosSupport: PlatformSupportCategory = .unknown
    @Persisted var androidVersion: String? = nil
    @Persisted var iosVersion: String? = nil
    @Persisted var latestVersion: String? = nil
    @Persisted var source: PackageSourceIndex = .pypi
    @Persisted var category: PackageCategoryType = .unprocessed
    @Persisted var isProcessed: Bool = false
    
    // One-to-many: This package depends on these packages
    @Persisted var dependencies: List<PackageResult> = List<PackageResult>()
    
    // Inverse relationship: Packages that depend on this package (many-to-one from their perspective)
    @Persisted(originProperty: "dependencies") var dependents: LinkingObjects<PackageResult>
    
    @Persisted var dependencyStatus: DependencyStatus = .noIssues
    @Persisted var lastUpdated: Date = Date()
    
    convenience init(name: String, numberOfDownloads: Int) {
        self.init()
        self.name = name
        self.numberOfDownloads = numberOfDownloads
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
        
        config.schemaVersion = 6
        
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
            if oldSchemaVersion < 3 {
                // Added latestVersion field - will be populated on next check
                // No migration needed, field defaults to nil
            }
            if oldSchemaVersion < 4 {
                // Migrated from String to IntEnum for androidSupport, iosSupport, source, category
                // Convert string values to enum integers
                migration.enumerateObjects(ofType: PackageResult.className()) { oldObject, newObject in
                    guard let oldObj = oldObject, let newObj = newObject else { return }
                    
                    // Migrate androidSupport
                    if let oldAndroid = oldObj["androidSupport"] as? String {
                        let enumValue: PlatformSupportCategory = {
                            switch oldAndroid {
                            case "success": return .success
                            case "pure-python": return .purePython
                            case "warning": return .warning
                            default: return .unknown
                            }
                        }()
                        newObj["androidSupport"] = enumValue.rawValue
                    }
                    
                    // Migrate iosSupport
                    if let oldIos = oldObj["iosSupport"] as? String {
                        let enumValue: PlatformSupportCategory = {
                            switch oldIos {
                            case "success": return .success
                            case "pure-python": return .purePython
                            case "warning": return .warning
                            default: return .unknown
                            }
                        }()
                        newObj["iosSupport"] = enumValue.rawValue
                    }
                    
                    // Migrate source
                    if let oldSource = oldObj["source"] as? String {
                        let enumValue: PackageSourceIndex = {
                            switch oldSource {
                            case "pyswift": return .pyswift
                            case "kivy-school", "kivyschool": return .kivyschool
                            default: return .pypi
                            }
                        }()
                        newObj["source"] = enumValue.rawValue
                    }
                    
                    // Migrate category
                    if let oldCategory = oldObj["category"] as? String {
                        let enumValue: PackageCategoryType = {
                            switch oldCategory {
                            case "both-platforms": return .bothPlatforms
                            case "android-only": return .androidOnly
                            case "ios-only": return .iosOnly
                            case "pure-python": return .purePython
                            case "no-mobile-support": return .noMobileSupport
                            default: return .unprocessed
                            }
                        }()
                        newObj["category"] = enumValue.rawValue
                    }
                }
            }
            if oldSchemaVersion < 5 {
                // Renamed downloadRank to numberOfDownloads
                // Keep the value as-is during migration (will be updated with actual download counts)
                migration.enumerateObjects(ofType: PackageResult.className()) { oldObject, newObject in
                    if let oldObj = oldObject, let newObj = newObject {
                        if let oldRank = oldObj["downloadRank"] as? Int {
                            newObj["numberOfDownloads"] = oldRank
                        }
                    }
                }
            }
            if oldSchemaVersion < 6 {
                // Changed allDepsSupported (Bool) to dependencyStatus (IntEnum)
                migration.enumerateObjects(ofType: PackageResult.className()) { oldObject, newObject in
                    if let oldObj = oldObject, let newObj = newObject {
                        if let allSupported = oldObj["allDepsSupported"] as? Bool {
                            // Convert bool to enum: true -> noIssues (0), false -> warning (1)
                            let status: DependencyStatus = allSupported ? .noIssues : .warning
                            newObj["dependencyStatus"] = status.rawValue
                        }
                    }
                }
            }
        }
        
        self.realm = try Realm(configuration: config)
        print("📦 Realm database: \(config.fileURL?.path ?? "unknown")")
    }
    
    /// Add or update a package in the database
    func upsertPackage(name: String, numberOfDownloads: Int) throws {
        try realm.write {
            if let existing = realm.object(ofType: PackageResult.self, forPrimaryKey: name) {
                existing.numberOfDownloads = numberOfDownloads
                existing.lastUpdated = Date()
            } else {
                let package = PackageResult(name: name, numberOfDownloads: numberOfDownloads)
                realm.add(package)
            }
        }
    }
    
    /// Batch insert/update packages (much faster for large datasets)
    func upsertPackagesBatch(packages: [(name: String, numberOfDownloads: Int)]) throws {
        try realm.write {
            for (name, downloads) in packages {
                if let existing = realm.object(ofType: PackageResult.self, forPrimaryKey: name) {
                    existing.numberOfDownloads = downloads
                    existing.lastUpdated = Date()
                } else {
                    let package = PackageResult(name: name, numberOfDownloads: downloads)
                    realm.add(package)
                }
            }
        }
    }
    
    /// Update package with analysis results
    func updatePackageResults(
        name: String,
        androidSupport: PlatformSupportCategory,
        iosSupport: PlatformSupportCategory,
        androidVersion: String?,
        iosVersion: String?,
        latestVersion: String?,
        source: PackageSourceIndex,
        category: PackageCategoryType
    ) throws {
        try realm.write {
            guard let package = realm.object(ofType: PackageResult.self, forPrimaryKey: name) else {
                return
            }
            
            package.androidSupport = androidSupport
            package.iosSupport = iosSupport
            package.androidVersion = androidVersion
            package.iosVersion = iosVersion
            package.latestVersion = latestVersion
            package.source = source
            package.category = category
            package.isProcessed = true
            package.lastUpdated = Date()
        }
    }
    
    /// Batch update package results (much faster for large datasets)
    func updatePackageResultsBatch(
        updates: [(name: String, androidSupport: PlatformSupportCategory, iosSupport: PlatformSupportCategory, 
                   androidVersion: String?, iosVersion: String?, latestVersion: String?, 
                   source: PackageSourceIndex, category: PackageCategoryType)]
    ) throws {
        try realm.write {
            for update in updates {
                guard let package = realm.object(ofType: PackageResult.self, forPrimaryKey: update.name) else {
                    continue
                }
                
                package.androidSupport = update.androidSupport
                package.iosSupport = update.iosSupport
                package.androidVersion = update.androidVersion
                package.iosVersion = update.iosVersion
                package.latestVersion = update.latestVersion
                package.source = update.source
                package.category = update.category
                package.isProcessed = true
                package.lastUpdated = Date()
            }
        }
    }
    
    /// Update package dependencies
    func updatePackageDependencies(name: String, dependencyNames: [String], status: DependencyStatus) throws {
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
                    let placeholder = PackageResult(name: depName, numberOfDownloads: 0)
                    realm.add(placeholder, update: .modified)
                    package.dependencies.append(placeholder)
                }
            }
            
            package.dependencyStatus = status
            package.lastUpdated = Date()
        }
    }
    
    /// Get all packages sorted by download count (descending)
    func getPackagesSortedByRank() -> Results<PackageResult> {
        return realm.objects(PackageResult.self).sorted(byKeyPath: "numberOfDownloads", ascending: false)
    }
    
    /// Get unprocessed packages sorted by download count (descending)
    func getUnprocessedPackages(limit: Int? = nil) -> [PackageResult] {
        let results = realm.objects(PackageResult.self)
            .filter("isProcessed == false")
            .sorted(byKeyPath: "numberOfDownloads", ascending: false)
        
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
            .sorted(byKeyPath: "numberOfDownloads", ascending: false)
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
        let packages = realm.objects(PackageResult.self).sorted(byKeyPath: "numberOfDownloads", ascending: false)
        
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
                "downloads": package.numberOfDownloads,
                "android": package.androidSupport.description,
                "ios": package.iosSupport.description,
                "source": package.source.description,
                "category": package.category.description
            ]
            
            if let androidVersion = package.androidVersion {
                pkgDict["androidVersion"] = androidVersion
            }
            if let iosVersion = package.iosVersion {
                pkgDict["iosVersion"] = iosVersion
            }
            if let latestVersion = package.latestVersion {
                pkgDict["version"] = latestVersion
            }
            
            // Add dependency information (even if dependencies list is empty)
            if !package.dependencies.isEmpty {
                // Convert PackageResult relationships to array of names
                pkgDict["dependencies"] = package.dependencies.map { $0.name }
            }
            
            // Always include dependency status for processed packages
            if package.isProcessed {
                pkgDict["dependencyStatus"] = package.dependencyStatus.description
            }
            
            packagesDict[package.name] = pkgDict
            packagesList.append(pkgDict)
            
            // Update summary based on category
            switch package.category {
            case .purePython: summary["purePython"]! += 1
            default: break
            }
            
            // Count platform support
            if package.androidSupport == .success {
                summary["androidSupport"]! += 1
            }
            if package.iosSupport == .success {
                summary["iosSupport"]! += 1
            }
            if package.androidSupport == .success && package.iosSupport == .success {
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
