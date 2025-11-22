#!/usr/bin/env swift

import Foundation
import RealmSwift

// Quick script to inspect Realm database relationships

guard CommandLine.arguments.count > 1 else {
    print("Usage: swift inspect-realm.swift <package-name>")
    exit(1)
}

let packageName = CommandLine.arguments[1]
let dbPath = FileManager.default.currentDirectoryPath + "/mobile-wheels.realm"

do {
    var config = Realm.Configuration()
    config.fileURL = URL(fileURLWithPath: dbPath)
    config.schemaVersion = 2
    
    let realm = try Realm(configuration: config)
    
    guard let package = realm.object(ofType: PackageResult.self, forPrimaryKey: packageName) else {
        print("Package '\(packageName)' not found in database")
        exit(1)
    }
    
    print("\n📦 Package: \(package.name)")
    print("   Download Rank: #\(package.downloadRank)")
    print("   Android: \(package.androidSupport)")
    print("   iOS: \(package.iosSupport)")
    print("   Category: \(package.category)")
    print("   Processed: \(package.isProcessed)")
    
    if !package.dependencies.isEmpty {
        print("\n   📚 Dependencies (\(package.dependencies.count)):")
        for dep in package.dependencies {
            print("      - \(dep.name) (Android: \(dep.androidSupport), iOS: \(dep.iosSupport))")
        }
        print("   All deps supported: \(package.allDepsSupported)")
    } else {
        print("\n   No dependencies")
    }
    
    if !package.dependents.isEmpty {
        print("\n   🔗 Dependents (\(package.dependents.count) packages depend on this):")
        for dependent in package.dependents.prefix(10) {
            print("      - \(dependent.name)")
        }
        if package.dependents.count > 10 {
            print("      ... and \(package.dependents.count - 10) more")
        }
    }
    
    print()
} catch {
    print("Error: \(error)")
    exit(1)
}

// Define the model (copy from RealmModels.swift)
class PackageResult: Object {
    @Persisted(primaryKey: true) var name: String = ""
    @Persisted var downloadRank: Int = 0
    @Persisted var androidSupport: String = "unknown"
    @Persisted var iosSupport: String = "unknown"
    @Persisted var androidVersion: String? = nil
    @Persisted var iosVersion: String? = nil
    @Persisted var source: String = "pypi"
    @Persisted var category: String = "unchecked"
    @Persisted var isProcessed: Bool = false
    @Persisted var dependencies: List<PackageResult> = List<PackageResult>()
    @Persisted(originProperty: "dependencies") var dependents: LinkingObjects<PackageResult>
    @Persisted var allDepsSupported: Bool = true
    @Persisted var lastUpdated: Date = Date()
}
