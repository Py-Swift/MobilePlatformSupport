#!/usr/bin/env swift

import Foundation
import RealmSwift

// Define the schema matching the database
class PackageResult: Object {
    @Persisted(primaryKey: true) var name: String = ""
    @Persisted var androidSupport: String = ""
    @Persisted var iosSupport: String = ""
    @Persisted var androidVersion: String?
    @Persisted var iosVersion: String?
    @Persisted var latestVersion: String?
    @Persisted var source: String = ""
    @Persisted var category: String = ""
    @Persisted var processed: Bool = false
    @Persisted var dependencyStatus: String = ""
    @Persisted var dependencies: List<DependencyInfo>
}

class DependencyInfo: Object {
    @Persisted var name: String = ""
    @Persisted var androidSupport: String = ""
    @Persisted var iosSupport: String = ""
    @Persisted var androidVersion: String?
    @Persisted var iosVersion: String?
    @Persisted var source: String = ""
}

// Get database path from arguments
guard CommandLine.arguments.count >= 2 else {
    print("Usage: swift inspect-deps.swift <database-path> [package-name]")
    exit(1)
}

let dbPath = CommandLine.arguments[1]
let packageFilter = CommandLine.arguments.count >= 3 ? CommandLine.arguments[2] : nil

// Open database
let config = Realm.Configuration(
    fileURL: URL(fileURLWithPath: dbPath),
    schemaVersion: 6,
    readOnly: true
)

do {
    let realm = try Realm(configuration: config)
    
    let results: Results<PackageResult>
    if let filter = packageFilter {
        results = realm.objects(PackageResult.self).filter("name CONTAINS[c] %@", filter)
    } else {
        results = realm.objects(PackageResult.self).filter("dependencies.@count > 0")
    }
    
    print("📦 Packages with dependencies: \(results.count)\n")
    
    for package in results.prefix(20) {
        print("Package: \(package.name)")
        print("  Status: Android=\(package.androidSupport), iOS=\(package.iosSupport)")
        print("  Dependency Status: \(package.dependencyStatus)")
        print("  Dependencies (\(package.dependencies.count)):")
        for dep in package.dependencies {
            print("    - \(dep.name): Android=\(dep.androidSupport), iOS=\(dep.iosSupport)")
        }
        print()
    }
} catch {
    print("Error: \(error)")
    exit(1)
}
