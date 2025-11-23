import Foundation
import MobilePlatformSupport

/// Helpers for efficient dependency checking with caching and parallel fetching
struct DependencyHelpers {
    
    /// Fetches dependencies in parallel with database-first lookup and in-memory caching
    /// - Parameters:
    ///   - depNames: Array of dependency package names to fetch
    ///   - checker: MobilePlatformSupport instance for API calls
    ///   - db: PackageDatabase for database lookups
    ///   - cache: In-memory cache of already-fetched dependencies (will be checked and updated)
    /// - Returns: Tuple of (fetched dependencies array, updated cache)
    static func fetchDependenciesParallel(
        depNames: [String],
        checker: MobilePlatformSupport,
        db: PackageDatabase,
        cache: [String: PackageInfo]
    ) async -> ([PackageInfo], [String: PackageInfo]) {
        guard !depNames.isEmpty else { return ([], cache) }
        
        var updatedCache = cache
        
        // Use task group for parallel fetching
        let dependencies = await withTaskGroup(of: (String, PackageInfo?).self, returning: [PackageInfo].self) { group in
            for depName in depNames {
                group.addTask { [cache] in
                    // 1. Check in-memory cache first (fastest)
                    if let cached = cache[depName] {
                        return (depName, cached)
                    }
                    
                    // 2. Check database (fast, avoids API call)
                    if let dbPackage = db.getPackage(name: depName),
                       dbPackage.isProcessed,
                       let latestVersion = dbPackage.latestVersion {
                        
                        // Reconstruct PackageInfo from database
                        let info = PackageInfo(
                            name: dbPackage.name,
                            android: dbPackage.androidSupport.toPlatformSupport(),
                            ios: dbPackage.iosSupport.toPlatformSupport(),
                            source: dbPackage.source.toPackageIndex(),
                            androidVersion: dbPackage.androidVersion,
                            iosVersion: dbPackage.iosVersion,
                            version: latestVersion
                        )
                        return (depName, info)
                    }
                    
                    // 3. Fetch from API (slowest, but necessary for new packages)
                    if let result = try? await checker.annotatePackage(depName) {
                        return (depName, result.info)
                    }
                    
                    return (depName, nil)
                }
            }
            
            // Collect results and update cache
            var results: [PackageInfo] = []
            for await (depName, info) in group {
                if let info = info {
                    results.append(info)
                    updatedCache[depName] = info
                }
            }
            return results
        }
        
        return (dependencies, updatedCache)
    }
    
    /// Determines dependency status based on dependency support levels
    static func determineDependencyStatus(dependencies: [PackageInfo]) -> DependencyStatus {
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
            
            // Check if both platforms not supported
            if !(androidCat == .success || androidCat == .purePython) ||
               !(iosCat == .success || iosCat == .purePython) {
                hasUnsupportedDep = true
            }
        }
        
        if hasUnsupportedDep {
            return .error
        } else if hasMissingDep {
            return .warning
        }
        return .noIssues
    }
}

// MARK: - Helper Extensions for converting database enums to PackageInfo enums

extension PlatformSupportCategory {
    func toPlatformSupport() -> PlatformSupport? {
        switch self {
        case .success:
            return .success
        case .purePython:
            return .purePython
        case .warning:
            return .warning
        case .unknown:
            return nil
        }
    }
}

extension PackageSourceIndex {
    func toPackageIndex() -> PackageIndex? {
        switch self {
        case .pypi:
            return .pypi
        case .pyswift:
            return .pyswift
        case .kivyschool:
            return .kivyschool
        }
    }
}
