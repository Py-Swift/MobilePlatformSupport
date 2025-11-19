import Foundation
import MobilePlatformSupport
import MarkdownReportGenerator
import ArgumentParser

@main
struct MobileWheelsChecker: AsyncParsableCommand {
    struct TopPyPIPackage: Codable {
        let project: String
        let download_count: Int?
    }

    struct TopPyPIResponse: Codable {
        let last_update: String
        let rows: [TopPyPIPackage]
    }
    
    static let configuration = CommandConfiguration(
        commandName: "mobile-wheels-checker",
        abstract: "Check PyPI packages for iOS/Android wheel support",
        discussion: """
        Checks Python packages for mobile platform (iOS/Android) wheel availability.
        Results are displayed in the terminal and exported to mobile-wheels-results.md.
        
        Data sources:
          • Default: Top ~8k packages from hugovk.github.io (pre-ranked)
          • --all:   All ~700k packages from pypi.org/simple (sorted by downloads)
        
        Performance: Uses concurrent requests (default: 10) for speed.
        """,
        version: "1.0.0"
    )
    
    @Argument(help: "Number of packages to check")
    var limit: Int = 1000
    
    @Flag(name: .shortAndLong, help: "Enable recursive dependency checking")
    var deps: Bool = false
    
    @Flag(name: .shortAndLong, help: "Use PyPI Simple Index (all ~700k packages)")
    var all: Bool = false
    
    @Option(name: .shortAndLong, help: "Number of concurrent requests (1-50)")
    var concurrent: Int = 10
    
    mutating func validate() throws {
        guard limit > 0 else {
            throw ValidationError("Limit must be positive")
        }
        guard concurrent >= 1 && concurrent <= 50 else {
            throw ValidationError("Concurrent must be between 1 and 50")
        }
    }
    
    static func downloadTopPackages(limit: Int = 100) async throws -> [String] {
        let url = URL(string: "https://hugovk.github.io/top-pypi-packages/top-pypi-packages-30-days.min.json")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(TopPyPIResponse.self, from: data)
        
        let packages = response.rows.prefix(limit).map { $0.project }
        print("📥 Downloaded top \(packages.count) packages from PyPI\n")
        return Array(packages)
    }
    
    static func downloadAllPackagesFromSimpleIndex(sortedByDownloads: Bool = false) async throws -> [String] {
        print("📥 Downloading package list from PyPI Simple Index...")
        let url = URL(string: "https://pypi.org/simple/")!
        let (data, _) = try await URLSession.shared.data(from: url)
        
        guard let html = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "MobileWheelsChecker", code: 1, 
                         userInfo: [NSLocalizedDescriptionKey: "Failed to decode HTML"])
        }
        
        // Parse package names from HTML
        // Format: <a href="/simple/package-name/">package-name</a>
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
        
        print("📦 Found \(packages.count) packages on PyPI")
        
        // If sorting by downloads is requested, fetch download stats and reorder
        if sortedByDownloads {
            print("📊 Fetching download statistics for sorting...")
            let statsUrl = URL(string: "https://hugovk.github.io/top-pypi-packages/top-pypi-packages-30-days.min.json")!
            let (statsData, _) = try await URLSession.shared.data(from: statsUrl)
            let response = try JSONDecoder().decode(TopPyPIResponse.self, from: statsData)
            
            // Create a ranking map: package name -> rank (lower is more popular)
            var rankMap: [String: Int] = [:]
            for (index, row) in response.rows.enumerated() {
                rankMap[row.project.lowercased()] = index
            }
            
            // Sort packages: ranked first (by download count), then unranked alphabetically
            packages.sort { pkg1, pkg2 in
                let rank1 = rankMap[pkg1.lowercased()]
                let rank2 = rankMap[pkg2.lowercased()]
                
                switch (rank1, rank2) {
                case let (r1?, r2?):
                    // Both have rankings - compare ranks
                    return r1 < r2
                case (_?, nil):
                    // pkg1 has rank, pkg2 doesn't - pkg1 comes first
                    return true
                case (nil, _?):
                    // pkg2 has rank, pkg1 doesn't - pkg2 comes first
                    return false
                case (nil, nil):
                    // Neither has rank - alphabetical
                    return pkg1.lowercased() < pkg2.lowercased()
                }
            }
            
            print("📦 Sorted by download count (top packages first)\n")
        } else {
            print()
        }
        
        return packages
    }
    
    mutating func run() async throws {
        print("🔍 Mobile Wheels Checker")
        print("========================\n")
        
        let checker = MobilePlatformSupport()
        
        do {
            // Download PySwift index first
            print("📥 Downloading PySwift index...")
            _ = try await checker.fetchPySwiftPackages()
            print()
            
            // Download packages from PyPI
            let testPackages: [String]
            if all {
                // Get all packages from simple index, sorted by downloads
                let allPackages = try await Self.downloadAllPackagesFromSimpleIndex(sortedByDownloads: true)
                // Limit to requested number (or all if limit >= total)
                testPackages = limit >= allPackages.count ? allPackages : Array(allPackages.prefix(limit))
            } else {
                // Get top packages from hugovk
                testPackages = try await Self.downloadTopPackages(limit: limit)
            }
            
            print("Checking \(testPackages.count) \(all ? "packages" : "popular packages") for mobile support...")
            if concurrent > 1 {
                print("(Using \(concurrent) concurrent requests)")
            }
            if deps {
                print("(Dependency checking enabled)")
            }
            print("(Note: Only packages with binary wheels will be shown)\n")
            
            let results = try await checker.getBinaryPackages(from: testPackages, concurrency: concurrent)
            
            // If dependency checking is enabled, check each package's dependencies
            var allPackagesWithDeps: [(PackageInfo, [PackageInfo], Bool)] = []  // (package, deps, allDepsSupported)
            
            if deps {
                print("\n🔍 Checking dependencies...\n")
                for package in results {
                    print("  Checking \(package.name)...")
                    var visited = Set<String>()
                    let depResults = try await checker.checkWithDependencies(
                        packageName: package.name,
                        depth: 1,
                        visited: &visited
                    )
                    
                    let dependencies = depResults.filter { $0.key != package.name }.map { $0.value }
                    let allDepsSupported = dependencies.allSatisfy { dep in
                        (dep.android == .success || dep.android == .purePython) &&
                        (dep.ios == .success || dep.ios == .purePython)
                    }
                    
                    allPackagesWithDeps.append((package, dependencies, allDepsSupported))
                }
            }
            
            // Separate results by source and type
            // Keep unsorted (download order) for main report display
            let officialBinaryWheels = results.filter {
                $0.source == .pypi &&
                ($0.android == .success || $0.ios == .success) &&
                !($0.android == .warning && $0.ios == .warning)
            }
            
            let pyswiftBinaryWheels = results.filter {
                $0.source == .pyswift &&
                ($0.android == .success || $0.ios == .success) &&
                !($0.android == .warning && $0.ios == .warning)
            }
            
            let purePython = results.filter { 
                $0.android == .purePython || $0.ios == .purePython
            }
            
            // Binary packages without mobile support (has binary wheels but not for iOS/Android)
            let binaryWithoutMobile = results.filter {
                ($0.android == .warning && $0.ios == .warning) &&
                ($0.android != .purePython && $0.ios != .purePython)
            }
            
            // Create sorted versions for the full separate files
            let purePythonSorted = purePython.sorted { $0.name.lowercased() < $1.name.lowercased() }
            let binaryWithoutMobileSorted = binaryWithoutMobile.sorted { $0.name.lowercased() < $1.name.lowercased() }
            
            // Display Official Binary Wheels
            print("\n🔧 Official Binary Wheels (PyPI):")
            print(String(repeating: "=", count: 71))
            if deps {
                print("\("Package".padding(toLength: 20, withPad: " ", startingAt: 0)) \("Android".padding(toLength: 20, withPad: " ", startingAt: 0)) \("iOS".padding(toLength: 20, withPad: " ", startingAt: 0)) \("Deps OK".padding(toLength: 10, withPad: " ", startingAt: 0))")
            } else {
                print("\("Package".padding(toLength: 20, withPad: " ", startingAt: 0)) \("Android".padding(toLength: 25, withPad: " ", startingAt: 0)) \("iOS".padding(toLength: 25, withPad: " ", startingAt: 0))")
            }
            print(String(repeating: "-", count: 71))
            
            for package in officialBinaryWheels {
                let androidStatus = Self.formatStatus(package.android)
                let iosStatus = Self.formatStatus(package.ios)
                
                if deps {
                    if let depInfo = allPackagesWithDeps.first(where: { $0.0.name == package.name }) {
                        let depsOK = depInfo.2 ? "✅" : "⚠️"
                        let depCount = depInfo.1.count
                        print("\(package.name.padding(toLength: 20, withPad: " ", startingAt: 0)) \(androidStatus.padding(toLength: 20, withPad: " ", startingAt: 0)) \(iosStatus.padding(toLength: 20, withPad: " ", startingAt: 0)) \(depsOK) (\(depCount))")
                    }
                } else {
                    print("\(package.name.padding(toLength: 20, withPad: " ", startingAt: 0)) \(androidStatus.padding(toLength: 25, withPad: " ", startingAt: 0)) \(iosStatus.padding(toLength: 25, withPad: " ", startingAt: 0))")
                }
            }
            
            // Display PySwift Binary Wheels
            print("\n🔧 PySwift Binary Wheels (pypi.anaconda.org/pyswift/simple):")
            print(String(repeating: "=", count: 71))
            if deps {
                print("\("Package".padding(toLength: 20, withPad: " ", startingAt: 0)) \("Android".padding(toLength: 20, withPad: " ", startingAt: 0)) \("iOS".padding(toLength: 20, withPad: " ", startingAt: 0)) \("Deps OK".padding(toLength: 10, withPad: " ", startingAt: 0))")
            } else {
                print("\("Package".padding(toLength: 20, withPad: " ", startingAt: 0)) \("Android".padding(toLength: 25, withPad: " ", startingAt: 0)) \("iOS".padding(toLength: 25, withPad: " ", startingAt: 0))")
            }
            print(String(repeating: "-", count: 71))
            
            for package in pyswiftBinaryWheels {
                let androidStatus = Self.formatStatus(package.android)
                let iosStatus = Self.formatStatus(package.ios)
                
                if deps {
                    if let depInfo = allPackagesWithDeps.first(where: { $0.0.name == package.name }) {
                        let depsOK = depInfo.2 ? "✅" : "⚠️"
                        let depCount = depInfo.1.count
                        print("\(package.name.padding(toLength: 20, withPad: " ", startingAt: 0)) \(androidStatus.padding(toLength: 20, withPad: " ", startingAt: 0)) \(iosStatus.padding(toLength: 20, withPad: " ", startingAt: 0)) \(depsOK) (\(depCount))")
                    }
                } else {
                    print("\(package.name.padding(toLength: 20, withPad: " ", startingAt: 0)) \(androidStatus.padding(toLength: 25, withPad: " ", startingAt: 0)) \(iosStatus.padding(toLength: 25, withPad: " ", startingAt: 0))")
                }
            }
            
            // Display Pure Python
            print("\n🐍 Pure Python Packages:")
            print(String(repeating: "=", count: 71))
            if deps {
                print("\("Package".padding(toLength: 20, withPad: " ", startingAt: 0)) \("Android".padding(toLength: 20, withPad: " ", startingAt: 0)) \("iOS".padding(toLength: 20, withPad: " ", startingAt: 0)) \("Deps OK".padding(toLength: 10, withPad: " ", startingAt: 0))")
            } else {
                print("\("Package".padding(toLength: 20, withPad: " ", startingAt: 0)) \("Android".padding(toLength: 25, withPad: " ", startingAt: 0)) \("iOS".padding(toLength: 25, withPad: " ", startingAt: 0))")
            }
            print(String(repeating: "-", count: 71))
            
            let maxPurePythonDisplay = 100
            for (index, package) in purePython.enumerated() {
                if index >= maxPurePythonDisplay {
                    let remaining = purePython.count - maxPurePythonDisplay
                    print("... +\(remaining) more")
                    break
                }
                
                let androidStatus = Self.formatStatus(package.android)
                let iosStatus = Self.formatStatus(package.ios)
                
                if deps {
                    if let depInfo = allPackagesWithDeps.first(where: { $0.0.name == package.name }) {
                        let depsOK = depInfo.2 ? "✅" : "⚠️"
                        let depCount = depInfo.1.count
                        print("\(package.name.padding(toLength: 20, withPad: " ", startingAt: 0)) \(androidStatus.padding(toLength: 20, withPad: " ", startingAt: 0)) \(iosStatus.padding(toLength: 20, withPad: " ", startingAt: 0)) \(depsOK) (\(depCount))")
                    }
                } else {
                    print("\(package.name.padding(toLength: 20, withPad: " ", startingAt: 0)) \(androidStatus.padding(toLength: 25, withPad: " ", startingAt: 0)) \(iosStatus.padding(toLength: 25, withPad: " ", startingAt: 0))")
                }
            }
            
            // Display Binary Packages Without Mobile Support
            print("\n❌ Binary Packages Without Mobile Support:")
            print(String(repeating: "=", count: 71))
            if deps {
                print("\("Package".padding(toLength: 20, withPad: " ", startingAt: 0)) \("Android".padding(toLength: 20, withPad: " ", startingAt: 0)) \("iOS".padding(toLength: 20, withPad: " ", startingAt: 0)) \("Deps OK".padding(toLength: 10, withPad: " ", startingAt: 0))")
            } else {
                print("\("Package".padding(toLength: 20, withPad: " ", startingAt: 0)) \("Android".padding(toLength: 25, withPad: " ", startingAt: 0)) \("iOS".padding(toLength: 25, withPad: " ", startingAt: 0))")
            }
            print(String(repeating: "-", count: 71))
            
            for package in binaryWithoutMobile {
                let androidStatus = Self.formatStatus(package.android)
                let iosStatus = Self.formatStatus(package.ios)
                
                if deps {
                    if let depInfo = allPackagesWithDeps.first(where: { $0.0.name == package.name }) {
                        let depsOK = depInfo.2 ? "✅" : "⚠️"
                        let depCount = depInfo.1.count
                        print("\(package.name.padding(toLength: 20, withPad: " ", startingAt: 0)) \(androidStatus.padding(toLength: 20, withPad: " ", startingAt: 0)) \(iosStatus.padding(toLength: 20, withPad: " ", startingAt: 0)) \(depsOK) (\(depCount))")
                    }
                } else {
                    print("\(package.name.padding(toLength: 20, withPad: " ", startingAt: 0)) \(androidStatus.padding(toLength: 25, withPad: " ", startingAt: 0)) \(iosStatus.padding(toLength: 25, withPad: " ", startingAt: 0))")
                }
            }
            
            print("\n📈 Summary:")
            print("- Total packages checked: \(testPackages.count)")
            print("- Official binary wheels (PyPI): \(officialBinaryWheels.count)")
            print("- PySwift binary wheels: \(pyswiftBinaryWheels.count)")
            print("- Pure Python: \(purePython.count)")
            print("- Binary without mobile support: \(binaryWithoutMobile.count)")
            print("")
            
            let allBinaryWheels = officialBinaryWheels + pyswiftBinaryWheels
            let androidSuccess = allBinaryWheels.filter { $0.android == .success }.count
            let iosSuccess = allBinaryWheels.filter { $0.ios == .success }.count
            let bothSupported = allBinaryWheels.filter { $0.android == .success && $0.ios == .success }.count
            
            print("Binary Wheels Platform Support:")
            print("- Android support: \(androidSuccess)/\(allBinaryWheels.count)")
            print("- iOS support: \(iosSuccess)/\(allBinaryWheels.count)")
            print("- Both platforms: \(bothSupported)/\(allBinaryWheels.count)")
            
            if deps {
                let allDepsOK = allPackagesWithDeps.filter { $0.2 }.count
                let totalChecked = allPackagesWithDeps.count
                print("")
                print("Dependency Status:")
                print("- All dependencies supported: \(allDepsOK)/\(totalChecked)")
                if allDepsOK < totalChecked {
                    print("- ⚠️  Some packages have unsupported dependencies")
                }
            }
            
            // Export markdown report
            let reportGenerator = MarkdownReportGenerator()
            try reportGenerator.generate(
                limit: limit,
                depsEnabled: deps,
                officialBinaryWheels: officialBinaryWheels,
                pyswiftBinaryWheels: pyswiftBinaryWheels,
                purePython: purePython,
                binaryWithoutMobile: binaryWithoutMobile,
                purePythonSorted: purePythonSorted,
                binaryWithoutMobileSorted: binaryWithoutMobileSorted,
                allPackagesWithDeps: allPackagesWithDeps,
                timestamp: Date()
            )
            
        } catch {
            print("❌ Error: \(error.localizedDescription)")
        }
    }
    
    static func formatStatus(_ status: PlatformSupport?) -> String {
        guard let status = status else {
            return "Unknown"
        }
        
        switch status {
        case .success:
            return "✅ Supported"
        case .purePython:
            return "🐍 Pure Python"
        case .warning:
            return "⚠️  Not available"
        }
    }
}

