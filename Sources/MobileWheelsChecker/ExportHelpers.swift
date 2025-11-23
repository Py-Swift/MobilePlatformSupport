import Foundation
import MobilePlatformSupport

/// Export helpers for various formats
@MainActor
struct ExportHelpers {
    /// Exports JSON in chunks for large datasets
    static func exportJSONChunks(packagesArray: [PackageResult], outputDir: String, db: PackageDatabase) async throws {
        let outputDirURL = URL(fileURLWithPath: outputDir)
        let jsonChunksPath = outputDirURL.appendingPathComponent("json-chunks")
        
        try? FileManager.default.createDirectory(at: jsonChunksPath, withIntermediateDirectories: true)
        
        let chunkSize = 1000
        let totalChunks = (packagesArray.count + chunkSize - 1) / chunkSize
        
        print("Exporting \(packagesArray.count) packages in \(totalChunks) chunks...")
        
        for chunkIndex in 0..<totalChunks {
            let start = chunkIndex * chunkSize
            let end = min(start + chunkSize, packagesArray.count)
            let chunk = Array(packagesArray[start..<end])
            
            var jsonChunk: [[String: Any]] = []
            
            for package in chunk {
                var packageDict: [String: Any] = [
                    "name": package.name,
                    "rank": package.downloadRank,
                    "android": package.androidSupport.description,
                    "ios": package.iosSupport.description,
                    "source": package.source.description,
                    "category": package.category.description
                ]
                
                if let androidVersion = package.androidVersion {
                    packageDict["androidVersion"] = androidVersion
                }
                if let iosVersion = package.iosVersion {
                    packageDict["iosVersion"] = iosVersion
                }
                if let latestVersion = package.latestVersion {
                    packageDict["version"] = latestVersion
                }
                
                // dependencies is now List<PackageResult>, convert to names
                let dependencyNames = package.dependencies.map { $0.name }
                if !dependencyNames.isEmpty {
                    packageDict["dependencies"] = dependencyNames
                    packageDict["allDepsSupported"] = package.allDepsSupported
                }
                
                jsonChunk.append(packageDict)
            }
            
            let chunkFilename = jsonChunksPath.appendingPathComponent("chunk-\(chunkIndex + 1)-of-\(totalChunks).json")
            let jsonData = try JSONSerialization.data(withJSONObject: jsonChunk, options: [.prettyPrinted, .sortedKeys])
            try jsonData.write(to: chunkFilename)
            
            let percentage = Int((Double(end) / Double(packagesArray.count)) * 100)
            print("\r\u{001B}[K[\(end)/\(packagesArray.count)] [\(percentage)%] exporting JSON chunks...", terminator: "")
            fflush(stdout)
        }
        
        print()
    }
}

/// Realm helper utilities
struct RealmHelpers {
    /// Converts MobilePlatformSupport.PlatformSupport to Realm PlatformSupportCategory
    static func platformSupportToCategory(_ support: PlatformSupport) -> PlatformSupportCategory {
        switch support {
        case .success: return .success
        case .purePython: return .purePython
        case .warning: return .warning
        }
    }
    
    /// Converts PackageIndex to PackageSourceIndex
    static func packageIndexToSource(_ index: PackageIndex) -> PackageSourceIndex {
        switch index {
        case .pypi: return .pypi
        case .pyswift: return .pyswift
        case .kivyschool: return .kivyschool
        }
    }
    
    /// Categorizes a package based on its platform support
    static func categorizePackage(_ package: PackageInfo) -> PackageCategoryType {
        guard let android = package.android, let ios = package.ios else {
            return .unprocessed
        }
        
        let androidSupported = android == .success || android == .purePython
        let iosSupported = ios == .success || ios == .purePython
        let isPurePython = android == .purePython && ios == .purePython
        
        if isPurePython {
            return .purePython
        } else if androidSupported && iosSupported {
            return .bothPlatforms
        } else if androidSupported {
            return .androidOnly
        } else if iosSupported {
            return .iosOnly
        } else {
            return .noMobileSupport
        }
    }
}
