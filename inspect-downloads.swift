#!/usr/bin/env swift

import Foundation
import RealmSwift

// Quick script to inspect numberOfDownloads in Realm database

guard CommandLine.arguments.count > 1 else {
    print("Usage: swift inspect-downloads.swift <database-path>")
    exit(1)
}

let dbPath = CommandLine.arguments[1]

// Schema must match current version
enum PlatformSupportCategory: Int, PersistableEnum {
    case unknown = 0, success = 1, purePython = 2, warning = 3
}

enum PackageSourceIndex: Int, PersistableEnum {
    case pypi = 0, pyswift = 1, kivyschool = 2
}

enum PackageCategoryType: Int, PersistableEnum {
    case unprocessed = 0, bothPlatforms = 1, androidOnly = 2, iosOnly = 3, purePython = 4, noMobileSupport = 5
}

enum DependencyStatus: Int, PersistableEnum {
    case noIssues = 0, warning = 1, error = 2
}

class PackageResult: Object {
    @Persisted(primaryKey: true) var name: String = ""
    @Persisted var numberOfDownloads: Int = 0
    @Persisted var androidSupport: PlatformSupportCategory = .unknown
    @Persisted var iosSupport: PlatformSupportCategory = .unknown
    @Persisted var androidVersion: String? = nil
    @Persisted var iosVersion: String? = nil
    @Persisted var latestVersion: String? = nil
    @Persisted var source: PackageSourceIndex = .pypi
    @Persisted var category: PackageCategoryType = .unprocessed
    @Persisted var isProcessed: Bool = false
    @Persisted var dependencies: List<PackageResult> = List<PackageResult>()
    @Persisted(originProperty: "dependencies") var dependents: LinkingObjects<PackageResult>
    @Persisted var dependencyStatus: DependencyStatus = .noIssues
    @Persisted var lastUpdated: Date = Date()
}

do {
    var config = Realm.Configuration()
    config.fileURL = URL(fileURLWithPath: dbPath)
    config.schemaVersion = 6
    config.readOnly = true
    
    let realm = try Realm(configuration: config)
    
    let packages = realm.objects(PackageResult.self).sorted(byKeyPath: "numberOfDownloads", ascending: false)
    
    print("\n📊 Top 10 packages by download count in Realm:")
    print("=" * 70)
    for (index, package) in packages.prefix(10).enumerated() {
        print("\n\(index + 1). \(package.name)")
        print("   Downloads: \(package.numberOfDownloads)")
        print("   Android: \(package.androidSupport) | iOS: \(package.iosSupport)")
        print("   Processed: \(package.isProcessed)")
    }
    
    print("\n" + "=" * 70)
    print("Total packages: \(packages.count)")
    print("Packages with downloads > 0: \(packages.filter("numberOfDownloads > 0").count)")
    print("Packages with downloads = 0: \(packages.filter("numberOfDownloads = 0").count)")
    
} catch {
    print("Error: \(error)")
    exit(1)
}
