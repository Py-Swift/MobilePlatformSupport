#!/usr/bin/env swift

import Foundation
import RealmSwift

// Run from project root: swift check-versions.swift

class PackageResult: Object {
    @Persisted(primaryKey: true) var name: String = ""
    @Persisted var latestVersion: String? = nil
    @Persisted var androidVersion: String? = nil
    @Persisted var iosVersion: String? = nil
}

do {
    let config = Realm.Configuration(
        fileURL: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("mobile-wheels.realm")
    )
    
    let realm = try Realm(configuration: config)
    let packages = realm.objects(PackageResult.self).sorted(byKeyPath: "name")
    
    print("Packages with version information:\n")
    print(String(format: "%-30s %-15s %-15s %-15s", "Package", "Latest", "Android", "iOS"))
    print(String(repeating: "-", count: 80))
    
    for package in packages.prefix(20) {
        print(String(format: "%-30s %-15s %-15s %-15s", 
                     package.name,
                     package.latestVersion ?? "N/A",
                     package.androidVersion ?? "N/A",
                     package.iosVersion ?? "N/A"))
    }
    
    print("\nTotal packages: \(packages.count)")
    print("With latest version: \(packages.filter { $0.latestVersion != nil }.count)")
    
} catch {
    print("Error: \(error)")
}
