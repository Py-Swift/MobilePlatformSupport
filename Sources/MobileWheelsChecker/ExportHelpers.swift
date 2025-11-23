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
                    "android": package.androidSupport,
                    "ios": package.iosSupport,
                    "source": package.source,
                    "category": package.category
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
    /// Converts platform support enum to string
    static func platformSupportToString(_ support: PlatformSupport) -> String {
        switch support {
        case .success: return "success"
        case .purePython: return "pure-python"
        case .warning: return "warning"
        }
    }
    
    /// Converts string to platform support enum
    static func stringToPlatformSupport(_ string: String) -> PlatformSupport {
        switch string {
        case "success": return .success
        case "pure-python": return .purePython
        case "warning": return .warning
        default: return .warning
        }
    }
    
    /// Converts source enum to string
    static func sourceToString(_ source: PackageIndex) -> String {
        switch source {
        case .pypi: return "pypi"
        case .pyswift: return "pyswift"
        case .kivyschool: return "kivy-school"
        }
    }
    
    /// Categorizes a package based on its platform support
    static func categorizePackage(_ package: PackageInfo) -> String {
        guard let android = package.android, let ios = package.ios else {
            return "unprocessed"
        }
        
        let androidSupported = android == .success || android == .purePython
        let iosSupported = ios == .success || ios == .purePython
        let isPurePython = android == .purePython && ios == .purePython
        
        if isPurePython {
            return "pure-python"
        } else if androidSupported && iosSupported {
            return "both-platforms"
        } else if androidSupported {
            return "android-only"
        } else if iosSupported {
            return "ios-only"
        } else {
            return "no-mobile-support"
        }
    }
}
