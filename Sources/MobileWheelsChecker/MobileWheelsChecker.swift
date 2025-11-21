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
        Results are displayed in the terminal and exported to markdown files.
        
        Data sources:
          • Default: Top ~8k packages from hugovk.github.io (pre-ranked)
          • --all:   All ~700k packages from pypi.org/simple (sorted by downloads)
        
        Output files:
          • mobile-wheels-results.md (main report)
          • pure-python-packages.md (full list if >100 packages)
          • binary-without-mobile.md (full list if >100 packages)
          • excluded-packages.md (GPU/CUDA/Windows packages filtered out)
        
        Performance: Uses concurrent requests (default: 10) for speed.
        """,
        version: "1.0.0"
    )
    
    @Argument(help: "Number of packages to check (0 = all packages)")
    var limit: Int = 1000
    
    @Flag(name: .shortAndLong, help: "Enable recursive dependency checking")
    var deps: Bool = false
    
    @Flag(name: .shortAndLong, help: "Use PyPI Simple Index (all ~700k packages)")
    var all: Bool = false
    
    @Option(name: .shortAndLong, help: "Number of concurrent requests (1-50)")
    var concurrent: Int = 10
    
    @Option(name: .shortAndLong, help: "Output directory for exported files (default: current directory)")
    var output: String?
    
    mutating func validate() throws {
        guard limit >= 0 else {
            throw ValidationError("Limit must be non-negative (0 = all packages)")
        }
        guard concurrent >= 1 && concurrent <= 50 else {
            throw ValidationError("Concurrent must be between 1 and 50")
        }
        
        // Validate output directory if provided
        if let outputPath = output {
            var isDirectory: ObjCBool = false
            let fileManager = FileManager.default
            
            // Check if path exists
            if fileManager.fileExists(atPath: outputPath, isDirectory: &isDirectory) {
                guard isDirectory.boolValue else {
                    throw ValidationError("Output path must be a directory, not a file")
                }
            } else {
                // Try to create the directory if it doesn't exist
                do {
                    try fileManager.createDirectory(atPath: outputPath, withIntermediateDirectories: true)
                } catch {
                    throw ValidationError("Cannot create output directory: \(error.localizedDescription)")
                }
            }
        }
    }
    
    static func downloadTopPackages(limit: Int = 100) async throws -> ([String], [(String, String)]) {
        let url = URL(string: "https://hugovk.github.io/top-pypi-packages/top-pypi-packages-30-days.min.json")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(TopPyPIResponse.self, from: data)
        
        // If limit is 0, use all packages; otherwise limit
        let packages = limit == 0 ? response.rows.map { $0.project } : response.rows.prefix(limit).map { $0.project }
        
        // Categorize excluded packages with reasons
        var excludedPackages: [(String, String)] = []
        for package in packages {
            let reason = getExclusionReason(package)
            if reason != nil {
                excludedPackages.append((package, reason!))
            }
        }
        
        // Filter out GPU/CUDA and non-mobile packages
        let filteredPackages = MobilePlatformSupport.filterMobileCompatiblePackages(Array(packages))
        
        print("📥 Downloaded top \(limit == 0 ? "all" : String(packages.count)) packages from PyPI")
        print("🔍 Filtered to \(filteredPackages.count) mobile-compatible packages (removed \(packages.count - filteredPackages.count) GPU/CUDA/Windows/non-mobile packages)\n")
        return (filteredPackages, excludedPackages)
    }
    
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
    
    static func downloadAllPackagesFromSimpleIndex(sortedByDownloads: Bool = false) async throws -> ([String], [(String, String)]) {
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
        
        // Categorize excluded packages with reasons
        var excludedPackages: [(String, String)] = []
        for package in packages {
            let reason = getExclusionReason(package)
            if reason != nil {
                excludedPackages.append((package, reason!))
            }
        }
        
        // Filter out GPU/CUDA and non-mobile packages early
        let beforeFilterCount = packages.count
        packages = MobilePlatformSupport.filterMobileCompatiblePackages(packages)
        print("🔍 Filtered to \(packages.count) mobile-compatible packages (removed \(beforeFilterCount - packages.count) GPU/CUDA/Windows/non-mobile packages)")
        
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
        
        return (packages, excludedPackages)
    }
    
    mutating func run() async throws {
        print("🔍 Mobile Wheels Checker")
        print("========================\n")
        
        let checker = MobilePlatformSupport()
        
        do {
            // Download PySwift and KivySchool indexes first
            print("📥 Downloading PySwift and KivySchool indexes...")
            _ = try await checker.fetchPySwiftPackages()
            _ = try await checker.fetchKivySchoolPackages()
            print()
            
            // Download packages from PyPI
            let testPackages: [String]
            var excludedPackages: [(String, String)] = []
            
            if all {
                // Get all packages from simple index, sorted by downloads
                let (allPackages, excluded) = try await Self.downloadAllPackagesFromSimpleIndex(sortedByDownloads: true)
                excludedPackages = excluded
                // Limit to requested number (or all if limit is 0 or >= total)
                testPackages = (limit == 0 || limit >= allPackages.count) ? allPackages : Array(allPackages.prefix(limit))
            } else {
                // Get top packages from hugovk
                let (packages, excluded) = try await Self.downloadTopPackages(limit: limit)
                testPackages = packages
                excludedPackages = excluded
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
            
            let kivyschoolBinaryWheels = results.filter {
                $0.source == .kivyschool &&
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
            
            // Display KivySchool Binary Wheels
            print("\n🔧 KivySchool Binary Wheels (pypi.anaconda.org/kivyschool/simple):")
            print(String(repeating: "=", count: 71))
            if deps {
                print("\("Package".padding(toLength: 20, withPad: " ", startingAt: 0)) \("Android".padding(toLength: 20, withPad: " ", startingAt: 0)) \("iOS".padding(toLength: 20, withPad: " ", startingAt: 0)) \("Deps OK".padding(toLength: 10, withPad: " ", startingAt: 0))")
            } else {
                print("\("Package".padding(toLength: 20, withPad: " ", startingAt: 0)) \("Android".padding(toLength: 25, withPad: " ", startingAt: 0)) \("iOS".padding(toLength: 25, withPad: " ", startingAt: 0))")
            }
            print(String(repeating: "-", count: 71))
            
            for package in kivyschoolBinaryWheels {
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
            
            let maxBinaryDisplay = 100
            for (index, package) in binaryWithoutMobile.enumerated() {
                if index >= maxBinaryDisplay {
                    let remaining = binaryWithoutMobile.count - maxBinaryDisplay
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
            
            print("\n📈 Summary:")
            print("- Total packages checked: \(testPackages.count)")
            print("- Official binary wheels (PyPI): \(officialBinaryWheels.count)")
            print("- PySwift binary wheels: \(pyswiftBinaryWheels.count)")
            print("- KivySchool binary wheels: \(kivyschoolBinaryWheels.count)")
            print("- Pure Python: \(purePython.count)")
            print("- Binary without mobile support: \(binaryWithoutMobile.count)")
            print("")
            
            let allBinaryWheels = officialBinaryWheels + pyswiftBinaryWheels + kivyschoolBinaryWheels
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
            
            // Construct file paths based on output directory
            let outputDir = output ?? FileManager.default.currentDirectoryPath
            let mainFilename = (outputDir as NSString).appendingPathComponent("mobile-wheels-results.md")
            let purePythonFilename = (outputDir as NSString).appendingPathComponent("pure-python-packages.md")
            let binaryWithoutMobileFilename = (outputDir as NSString).appendingPathComponent("binary-without-mobile.md")
            
            try reportGenerator.generate(
                limit: limit,
                depsEnabled: deps,
                officialBinaryWheels: officialBinaryWheels,
                pyswiftBinaryWheels: pyswiftBinaryWheels,
                kivyschoolBinaryWheels: kivyschoolBinaryWheels,
                purePython: purePython,
                binaryWithoutMobile: binaryWithoutMobile,
                purePythonSorted: purePythonSorted,
                binaryWithoutMobileSorted: binaryWithoutMobileSorted,
                allPackagesWithDeps: allPackagesWithDeps,
                timestamp: Date(),
                mainFilename: mainFilename,
                purePythonFilename: purePythonFilename,
                binaryWithoutMobileFilename: binaryWithoutMobileFilename
            )
            
            // Export excluded packages report if any were filtered
            if !excludedPackages.isEmpty {
                let excludedFilename = (outputDir as NSString).appendingPathComponent("excluded-packages.md")
                try Self.generateExcludedPackagesReport(
                    excludedPackages: excludedPackages,
                    timestamp: Date(),
                    filename: excludedFilename
                )
            }
            
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
    
    static func generateExcludedPackagesReport(
        excludedPackages: [(String, String)],
        timestamp: Date,
        filename: String
    ) throws {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let dateString = dateFormatter.string(from: timestamp)
        
        // Group packages by reason
        var gpuCudaPackages: [String] = []
        var windowsPackages: [String] = []
        var deprecatedPackages: [String] = []
        var otherNonMobilePackages: [String] = []
        
        for (package, reason) in excludedPackages {
            switch reason {
            case "GPU/CUDA":
                gpuCudaPackages.append(package)
            case "Windows-only":
                windowsPackages.append(package)
            case "Deprecated":
                deprecatedPackages.append(package)
            case "Non-mobile":
                otherNonMobilePackages.append(package)
            default:
                otherNonMobilePackages.append(package)
            }
        }
        
        // Sort alphabetically
        gpuCudaPackages.sort { $0.lowercased() < $1.lowercased() }
        windowsPackages.sort { $0.lowercased() < $1.lowercased() }
        deprecatedPackages.sort { $0.lowercased() < $1.lowercased() }
        otherNonMobilePackages.sort { $0.lowercased() < $1.lowercased() }
        
        var markdown = """
        # Excluded Packages - Not Compatible with Mobile Platforms
        
        **Generated:** \(dateString)  
        **Total Excluded:** \(excludedPackages.count)
        
        This document lists packages that were automatically filtered out during mobile platform support checking. These packages are **not compatible with mobile platforms** (iOS/Android) and should never be used in mobile applications.
        
        ---
        
        """
        
        // GPU/CUDA Packages
        if !gpuCudaPackages.isEmpty {
            markdown += """
            ## 🎮 GPU/CUDA Packages (\(gpuCudaPackages.count))
            
            These packages require GPU hardware and CUDA drivers which are not available on mobile platforms.
            
            | Package | Reason |
            |---------|--------|
            
            """
            
            for package in gpuCudaPackages {
                markdown += "| `\(package)` | Requires GPU/CUDA (not available on iOS/Android) |\n"
            }
            
            markdown += "\n"
        }
        
        // Windows-only Packages
        if !windowsPackages.isEmpty {
            markdown += """
            ## 🪟 Windows-Only Packages (\(windowsPackages.count))
            
            These packages are specific to Windows operating system and cannot run on mobile platforms.
            
            | Package | Reason |
            |---------|--------|
            
            """
            
            for package in windowsPackages {
                markdown += "| `\(package)` | Windows-specific APIs (not available on iOS/Android) |\n"
            }
            
            markdown += "\n"
        }
        
        // Deprecated Packages
        if !deprecatedPackages.isEmpty {
            markdown += """
            ## ⚠️ Deprecated Packages (\(deprecatedPackages.count))
            
            These packages are deprecated and should not be used in any new projects.
            
            | Package | Reason |
            |---------|--------|
            
            """
            
            for package in deprecatedPackages {
                markdown += "| `\(package)` | Deprecated by Python community |\n"
            }
            
            markdown += "\n"
        }
        
        // Other Non-mobile Packages
        if !otherNonMobilePackages.isEmpty {
            markdown += """
            ## 🚫 Other Non-Mobile Packages (\(otherNonMobilePackages.count))
            
            These packages have architecture or system requirements incompatible with mobile platforms.
            
            | Package | Reason |
            |---------|--------|
            
            """
            
            for package in otherNonMobilePackages {
                markdown += "| `\(package)` | Architecture/system incompatible with mobile |\n"
            }
            
            markdown += "\n"
        }
        
        markdown += """
        ---
        
        ## Summary
        
        | Category | Count | Percentage |
        |----------|-------|------------|
        | GPU/CUDA Packages | \(gpuCudaPackages.count) | \(String(format: "%.1f%%", Double(gpuCudaPackages.count) / Double(excludedPackages.count) * 100)) |
        | Windows-Only Packages | \(windowsPackages.count) | \(String(format: "%.1f%%", Double(windowsPackages.count) / Double(excludedPackages.count) * 100)) |
        | Deprecated Packages | \(deprecatedPackages.count) | \(String(format: "%.1f%%", Double(deprecatedPackages.count) / Double(excludedPackages.count) * 100)) |
        | Other Non-Mobile | \(otherNonMobilePackages.count) | \(String(format: "%.1f%%", Double(otherNonMobilePackages.count) / Double(excludedPackages.count) * 100)) |
        | **Total** | **\(excludedPackages.count)** | **100%** |
        
        ---
        
        **Why These Packages Are Excluded:**
        
        1. **GPU/CUDA Packages**: Require NVIDIA GPU hardware and CUDA runtime which don't exist on mobile devices
        2. **Windows-Only Packages**: Use Windows-specific APIs (Win32, COM, etc.) not available on iOS/Android
        3. **Deprecated Packages**: Outdated packages that have been superseded or abandoned
        4. **Other Non-Mobile**: Packages with Intel-specific optimizations, subprocess requirements, or other incompatibilities
        
        **For Mobile Development**: Use pure Python packages or packages with official iOS/Android binary wheels instead.
        
        ---
        
        **Generated by:** [MobilePlatformSupport](https://github.com/Py-Swift/MobilePlatformSupport)
        
        """
        
        let fileURL = URL(fileURLWithPath: filename)
        try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
        print("✅ Excluded packages list exported to: \(filename)")
    }
}

