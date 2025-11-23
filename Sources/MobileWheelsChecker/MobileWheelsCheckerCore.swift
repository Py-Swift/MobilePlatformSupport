import Foundation
import MobilePlatformSupport

/// Core functionality for Mobile Wheels Checker
struct MobileWheelsCheckerCore {
    struct TopPyPIPackage: Codable {
        let project: String
        let download_count: Int?
    }

    struct TopPyPIResponse: Codable {
        let last_update: String
        let rows: [TopPyPIPackage]
    }
    
    /// Downloads top packages from hugovk's top packages list
    /// Returns (packages with download counts, excluded packages with reasons)
    static func downloadTopPackages(limit: Int = 100) async throws -> ([(String, Int)], [(String, String)]) {
        let url = URL(string: "https://hugovk.github.io/top-pypi-packages/top-pypi-packages-30-days.min.json")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(TopPyPIResponse.self, from: data)
        
        let rows = limit == 0 ? response.rows : Array(response.rows.prefix(limit))
        
        // Categorize excluded packages with reasons
        var excludedPackages: [(String, String)] = []
        var packagesWithCounts: [(String, Int)] = []
        
        for row in rows {
            if let reason = getExclusionReason(row.project) {
                excludedPackages.append((row.project, reason))
            } else {
                // Include package with its download count (default to 0 if missing)
                packagesWithCounts.append((row.project, row.download_count ?? 0))
            }
        }
        
        return (packagesWithCounts, excludedPackages)
    }
    
    /// Downloads all packages from PyPI Simple Index
    static func downloadAllPackages() async throws -> [String] {
        let url = URL(string: "https://pypi.org/simple/")!
        let (data, _) = try await URLSession.shared.data(from: url)
        
        guard let html = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "MobileWheelsChecker", code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to decode HTML"])
        }
        
        // Parse package names from HTML
        var packages: [String] = []
        let pattern = #"<a href="/simple/[^/]+/">([^<]+)</a>"#
        
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let matches = regex.matches(in: html, options: [],
                                       range: NSRange(html.startIndex..., in: html))
            
            for match in matches {
                if let range = Range(match.range(at: 1), in: html) {
                    let packageName = String(html[range])
                    packages.append(packageName)
                }
            }
        }
        
        return packages
    }
    
    /// Gets the exclusion reason for a package
    static func getExclusionReason(_ packageName: String) -> String? {
        let normalized = MobilePlatformSupport.normalizePackageName(packageName)
        
        if MobilePlatformSupport.deprecatedPackages.contains(normalized) {
            return "Deprecated"
        }
        
        if MobilePlatformSupport.isGPUPackage(normalized) {
            return "GPU/CUDA"
        }
        
        if MobilePlatformSupport.isWindowsPackage(normalized) {
            return "Windows-only"
        }
        
        if MobilePlatformSupport.nonMobilePackages.contains(normalized) {
            return "Non-mobile"
        }
        
        return nil
    }
    
    /// Checks if a package should be excluded
    static func isExcluded(_ packageName: String) -> Bool {
        return getExclusionReason(packageName) != nil
    }
}
