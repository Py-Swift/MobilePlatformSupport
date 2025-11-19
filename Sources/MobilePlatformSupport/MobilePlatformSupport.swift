import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Platform support status for a package
public enum PlatformSupport: String, Codable {
    case success = "success"     // Has compiled wheels for the platform
    case purePython = "pure-py"  // Only has pure Python wheels
    case warning = "warning"     // No wheels available for the platform
}

/// Mobile platform types
public enum MobilePlatform: String, CaseIterable {
    case android
    case ios
}

/// Package information with platform support
public struct PackageInfo: Codable {
    public let name: String
    public var android: PlatformSupport?
    public var ios: PlatformSupport?
    public var source: PackageIndex?
    
    public init(name: String, android: PlatformSupport? = nil, ios: PlatformSupport? = nil, source: PackageIndex? = nil) {
        self.name = name
        self.android = android
        self.ios = ios
        self.source = source
    }
}

/// PyPI package metadata response
public struct PyPIPackageData: Codable {
    let urls: [PackageDownload]
    let info: PackageMetadata?
}

struct PackageDownload: Codable {
    let packagetype: String
    let filename: String
}

public struct PackageMetadata: Codable {
    let requires_dist: [String]?
    
    enum CodingKeys: String, CodingKey {
        case requires_dist
    }
}

/// Package source index
public enum PackageIndex: String, Codable {
    case pypi = "PyPI"
    case pyswift = "PySwift"
}

/// Mobile platform support checker for Python packages
public class MobilePlatformSupport {
    
    private static let baseURL = "https://pypi.org/pypi"
    private static let pyswiftSimpleURL = "https://pypi.anaconda.org/pyswift/simple"
    
    private var pyswiftPackages: Set<String>?
    
    /// Known deprecated packages that should be excluded
    public static let deprecatedPackages: Set<String> = [
        "BeautifulSoup",
        "bs4",
        "distribute",
        "django-social-auth",
        "nose",
        "pep8",
        "pycrypto",
        "pypular",
        "sklearn",
        "subprocess32"
    ]
    
    /// Packages that cannot be ported to mobile platforms
    public static let nonMobilePackages: Set<String> = [
        // Nvidia/CUDA projects - CUDA isn't available for Android or iOS
        "cuda-bindings",
        "cupy-cuda11x",
        "cupy-cuda12x",
        "jax-cuda12-pjrt",
        "jax-cuda12-plugin",
        "nvidia-cublas-cu11",
        "nvidia-cublas-cu12",
        "nvidia-cuda-cupti-cu11",
        "nvidia-cuda-cupti-cu12",
        "nvidia-cuda-nvcc-cu12",
        "nvidia-cuda-nvrtc-cu11",
        "nvidia-cuda-nvrtc-cu12",
        "nvidia-cuda-runtime-cu11",
        "nvidia-cuda-runtime-cu12",
        "nvidia-cudnn-cu11",
        "nvidia-cudnn-cu12",
        "nvidia-cufft-cu11",
        "nvidia-cufft-cu12",
        "nvidia-cufile-cu12",
        "nvidia-curand-cu11",
        "nvidia-curand-cu12",
        "nvidia-cusolver-cu11",
        "nvidia-cusolver-cu12",
        "nvidia-cusparse-cu11",
        "nvidia-cusparse-cu12",
        "nvidia-cusparselt-cu12",
        "nvidia-modelopt-core",
        "nvidia-modelopt",
        "nvidia-nccl-cu11",
        "nvidia-nccl-cu12",
        "nvidia-nvshmem-cu12",
        "nvidia-nvtx-cu11",
        "nvidia-nvtx-cu12",
        "sgl-kernel",
        // Intel processors aren't used on mobile platforms
        "intel-cmplr-lib-ur",
        "intel-openmp",
        "mkl",
        "tensorflow-intel",
        // Subprocesses aren't supported on mobile platforms
        "multiprocess",
        // Windows-specific bindings
        "pywin32",
        "pywinpty",
        "windows-curses"
    ]
    
    private let session: URLSession
    
    public init(session: URLSession = .shared) {
        self.session = session
    }
    
    /// Download and parse the PySwift simple index to get available packages
    public func fetchPySwiftPackages() async throws -> Set<String> {
        if let cached = pyswiftPackages {
            return cached
        }
        
        guard let url = URL(string: Self.pyswiftSimpleURL) else {
            throw MobilePlatformError.invalidResponse
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw MobilePlatformError.invalidResponse
        }
        
        guard let html = String(data: data, encoding: .utf8) else {
            throw MobilePlatformError.invalidResponse
        }
        
        // Parse HTML to extract package names
        // Simple index format: <a href="package-name/">package-name</a>
        var packages = Set<String>()
        let lines = html.components(separatedBy: .newlines)
        
        for line in lines {
            // Look for <a href="...">package-name</a>
            if let startRange = line.range(of: "<a href=\""),
               let endRange = line.range(of: "\">", range: startRange.upperBound..<line.endIndex),
               let closeTag = line.range(of: "</a>", range: endRange.upperBound..<line.endIndex) {
                let packageName = String(line[endRange.upperBound..<closeTag.lowerBound])
                // Normalize package name according to PEP 503
                let normalized = normalizePackageName(packageName)
                packages.insert(normalized)
            }
        }
        
        pyswiftPackages = packages
        print("📦 Loaded \(packages.count) packages from PySwift index")
        return packages
    }
    
    /// Normalize package name for comparison (PEP 503)
    /// Converts to lowercase and replaces hyphens, underscores, and dots with hyphens
    private func normalizePackageName(_ name: String) -> String {
        return name.lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: ".", with: "-")
    }
    
    /// Check if a package is available in PySwift index
    public func isAvailableInPySwift(_ packageName: String) async throws -> Bool {
        let packages = try await fetchPySwiftPackages()
        let normalized = normalizePackageName(packageName)
        return packages.contains(normalized)
    }
    
    /// Fetch wheel filenames from PySwift package page
    public func fetchPySwiftWheels(for packageName: String) async throws -> [String] {
        guard let url = getPySwiftPackageURL(for: packageName) else {
            throw MobilePlatformError.invalidPackageName(packageName)
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return []
        }
        
        guard let html = String(data: data, encoding: .utf8) else {
            return []
        }
        
        // Parse HTML to extract wheel filenames
        // Format: <a href="package-1.0-py3-none-ios.whl">package-1.0-py3-none-ios.whl</a>
        var wheels: [String] = []
        let lines = html.components(separatedBy: .newlines)
        
        for line in lines {
            if let startRange = line.range(of: "<a href=\""),
               let endRange = line.range(of: "\">", range: startRange.upperBound..<line.endIndex),
               let closeTag = line.range(of: "</a>", range: endRange.upperBound..<line.endIndex) {
                let filename = String(line[endRange.upperBound..<closeTag.lowerBound])
                if filename.hasSuffix(".whl") {
                    wheels.append(filename)
                }
            }
        }
        
        return wheels
    }
    
    /// Get JSON URL for a package
    private func getJSONURL(for packageName: String) -> URL? {
        return URL(string: "\(Self.baseURL)/\(packageName)/json")
    }
    
    /// Get PySwift package URL
    private func getPySwiftPackageURL(for packageName: String) -> URL? {
        let normalized = normalizePackageName(packageName)
        return URL(string: "\(Self.pyswiftSimpleURL)/\(normalized)/")
    }
    
    /// Fetch package data from PyPI
    public func fetchPackageData(for packageName: String) async throws -> PyPIPackageData {
        guard let url = getJSONURL(for: packageName) else {
            throw MobilePlatformError.invalidPackageName(packageName)
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MobilePlatformError.invalidResponse
        }
        
        guard httpResponse.statusCode == 200 else {
            throw MobilePlatformError.httpError(statusCode: httpResponse.statusCode)
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(PyPIPackageData.self, from: data)
    }
    
    /// Check if a package has binary wheels (not pure Python)
    public func isBinaryPackage(_ packageName: String) async throws -> Bool {
        let data = try await fetchPackageData(for: packageName)
        
        for download in data.urls where download.packagetype == "bdist_wheel" {
            let platformTag = extractPlatformTag(from: download.filename)
            if platformTag != "any" {
                return true
            }
        }
        
        return false
    }
    
    /// Extract platform tag from wheel filename
    /// Wheel filename format: {distribution}-{version}(-{build tag})?-{python tag}-{abi tag}-{platform tag}.whl
    private func extractPlatformTag(from filename: String) -> String {
        let withoutExtension = filename.replacingOccurrences(of: ".whl", with: "")
        let components = withoutExtension.split(separator: "-")
        guard let lastComponent = components.last else { return "any" }
        
        // Platform tag can have multiple parts separated by underscores
        // e.g., "macosx_10_9_x86_64" -> "macosx"
        let platformParts = String(lastComponent).split(separator: "_")
        return String(platformParts.first ?? "any")
    }
    
    /// Annotate a package with platform support information
    /// Also checks if package is available in PySwift index and reads its wheels
    public func annotatePackage(_ packageName: String) async throws -> PackageInfo? {
        // Skip deprecated and non-mobile packages
        if Self.deprecatedPackages.contains(packageName) || Self.nonMobilePackages.contains(packageName) {
            return nil
        }
        
        var availablePlatforms = Set<String>()
        var pypiPlatforms = Set<String>()
        var pyswiftPlatforms = Set<String>()
        
        // Check PyPI first (official source takes priority)
        do {
            let data = try await fetchPackageData(for: packageName)
            for download in data.urls where download.packagetype == "bdist_wheel" {
                let platformTag = extractPlatformTag(from: download.filename)
                pypiPlatforms.insert(platformTag)
                availablePlatforms.insert(platformTag)
            }
        } catch {
            // PyPI error, will check PySwift as fallback
        }
        
        // Check if package is in PySwift
        let inPySwift = try await isAvailableInPySwift(packageName)
        
        if inPySwift {
            // Fetch wheels from PySwift
            let pyswiftWheels = try await fetchPySwiftWheels(for: packageName)
            for filename in pyswiftWheels {
                let platformTag = extractPlatformTag(from: filename)
                pyswiftPlatforms.insert(platformTag)
                availablePlatforms.insert(platformTag)
            }
        }
        
        // If no platforms found at all, throw error
        if availablePlatforms.isEmpty {
            throw MobilePlatformError.invalidResponse
        }
        
        // Determine if this is a pure Python package (only "any" platform)
        let isPurePython = availablePlatforms == ["any"]
        
        // Determine source: PyPI official wheels are preferred
        // Only use PySwift if PyPI doesn't have iOS/Android wheels but PySwift does
        let pypiHasMobileWheels = pypiPlatforms.contains("ios") || pypiPlatforms.contains("android")
        let pyswiftHasMobileWheels = pyswiftPlatforms.contains("ios") || pyswiftPlatforms.contains("android")
        let source: PackageIndex = pypiHasMobileWheels ? .pypi : (pyswiftHasMobileWheels ? .pyswift : .pypi)
        
        var package = PackageInfo(name: packageName, source: source)
        
        // Determine support for each platform
        for platform in MobilePlatform.allCases {
            let platformString = platform.rawValue
            let support: PlatformSupport
            
            if isPurePython {
                // Pure Python packages work on all platforms
                support = .purePython
            } else if availablePlatforms.contains(platformString) {
                // Has binary wheels for this platform
                support = .success
            } else if availablePlatforms.contains("any") {
                // Has pure Python wheels (but also has other binary wheels)
                support = .purePython
            } else {
                // No support for this platform
                support = .warning
            }
            
            switch platform {
            case .android:
                package.android = support
            case .ios:
                package.ios = support
            }
        }
        
        return package
    }
    
    /// Get all binary packages from a list of package names
    /// Cross-checks with PySwift index to mark packages available there
    /// - Parameters:
    ///   - packageNames: Array of package names to check
    ///   - maxResults: Maximum number of results to return (nil for all)
    ///   - concurrency: Number of concurrent requests (default: 10)
    /// - Returns: Array of PackageInfo with platform support details
    public func getBinaryPackages(from packageNames: [String], maxResults: Int? = nil, concurrency: Int = 10) async throws -> [PackageInfo] {
        let limit = maxResults ?? packageNames.count
        let packagesToCheck = Array(packageNames.prefix(limit))
        
        return try await withThrowingTaskGroup(of: (Int, PackageInfo?).self) { group in
            var results: [Int: PackageInfo] = [:]
            var processedCount = 0
            
            // Process packages in batches
            for (index, packageName) in packagesToCheck.enumerated() {
                // Wait if we've hit the concurrency limit
                if index >= concurrency {
                    if let (idx, package) = try await group.next() {
                        processedCount += 1
                        if let package = package {
                            results[idx] = package
                        }
                        print("\r\u{001B}[K[\(results.count)/\(limit)] [\(processedCount)/\(packagesToCheck.count)] processing...", terminator: "")
                        fflush(stdout)
                    }
                }
                
                // Add new task
                group.addTask {
                    do {
                        let package = try await self.annotatePackage(packageName)
                        return (index, package)
                    } catch {
                        return (index, nil)
                    }
                }
            }
            
            // Collect remaining results
            for try await (idx, package) in group {
                processedCount += 1
                if let package = package {
                    results[idx] = package
                }
                print("\r\u{001B}[K[\(results.count)/\(limit)] [\(processedCount)/\(packagesToCheck.count)] processing...", terminator: "")
                fflush(stdout)
            }
            
            print()  // Final newline
            
            // Return results in original order
            return packagesToCheck.indices.compactMap { results[$0] }
        }
    }
    
    /// Get all binary packages from a list of package names (sequential version)
    /// Cross-checks with PySwift index to mark packages available there
    /// - Parameters:
    ///   - packageNames: Array of package names to check
    ///   - maxResults: Maximum number of results to return (nil for all)
    /// - Returns: Array of PackageInfo with platform support details
    public func getBinaryPackagesSequential(from packageNames: [String], maxResults: Int? = nil) async throws -> [PackageInfo] {
        var results: [PackageInfo] = []
        let limit = maxResults ?? packageNames.count
        
        for (index, packageName) in packageNames.enumerated() {
            if results.count >= limit {
                break
            }
            
            // Use carriage return and clear line to update same line
            print("\r\u{001B}[K[\(results.count + 1)/\(limit)] [\(index + 1)/\(packageNames.count)] \(packageName)", terminator: "")
            fflush(stdout)
            
            do {
                if let annotated = try await annotatePackage(packageName) {
                    results.append(annotated)
                }
            } catch {
                print("\r\u{001B}[K ! Skipping \(packageName): \(error.localizedDescription)")
                continue
            }
        }
        
        // Print newline after loop completes
        print()
        
        return results
    }
    
    /// Filter packages to only those with binary wheels
    public func filterBinaryPackages(from packageNames: [String]) async throws -> [String] {
        var binaryPackages: [String] = []
        
        for packageName in packageNames {
            // Skip deprecated and non-mobile packages
            if Self.deprecatedPackages.contains(packageName) || Self.nonMobilePackages.contains(packageName) {
                continue
            }
            
            do {
                if try await isBinaryPackage(packageName) {
                    binaryPackages.append(packageName)
                }
            } catch {
                print(" ! Error checking \(packageName): \(error.localizedDescription)")
                continue
            }
        }
        
        return binaryPackages
    }
    
    /// Parse package name from a dependency string
    /// Example: "requests>=2.0.0" -> "requests"
    /// Example: "numpy (>=1.19.0)" -> "numpy"
    private func parsePackageName(from dependency: String) -> String {
        let name = dependency
            .split(separator: " ")[0]  // Remove version specifiers with space
            .split(separator: "(")[0]  // Remove parentheses
            .split(separator: "[")[0]  // Remove extras
        
        // Remove comparison operators
        let cleanName = String(name)
            .components(separatedBy: CharacterSet(charactersIn: ">=<!~"))
            .first ?? String(name)
        
        return cleanName.trimmingCharacters(in: .whitespaces).lowercased()
    }
    
    /// Get dependencies for a package
    public func getDependencies(for packageName: String) async throws -> [String] {
        let data = try await fetchPackageData(for: packageName)
        
        guard let requiresDist = data.info?.requires_dist else {
            return []
        }
        
        var dependencies: Set<String> = []
        
        for requirement in requiresDist {
            // Skip optional dependencies (those with "extra ==")
            if requirement.contains("extra ==") {
                continue
            }
            
            let packageName = parsePackageName(from: requirement)
            
            // Skip empty names and known excluded packages
            if !packageName.isEmpty && 
               !Self.deprecatedPackages.contains(packageName) &&
               !Self.nonMobilePackages.contains(packageName) {
                dependencies.insert(packageName)
            }
        }
        
        return Array(dependencies).sorted()
    }
    
    /// Check if a package and all its dependencies support mobile platforms
    /// - Parameters:
    ///   - packageName: The package to check
    ///   - depth: Maximum recursion depth (default 2 to avoid infinite loops)
    ///   - visited: Set of already visited packages
    /// - Returns: Dictionary mapping package names to their support info
    public func checkWithDependencies(
        packageName: String,
        depth: Int = 2,
        visited: inout Set<String>
    ) async throws -> [String: PackageInfo] {
        
        // Prevent cycles and limit depth
        guard depth > 0, !visited.contains(packageName) else {
            return [:]
        }
        
        visited.insert(packageName)
        var results: [String: PackageInfo] = [:]
        
        // Check the package itself
        if let packageInfo = try await annotatePackage(packageName) {
            results[packageName] = packageInfo
            
            // Get and check dependencies
            let dependencies = try await getDependencies(for: packageName)
            
            for dependency in dependencies {
                let depResults = try await checkWithDependencies(
                    packageName: dependency,
                    depth: depth - 1,
                    visited: &visited
                )
                results.merge(depResults) { current, _ in current }
            }
        }
        
        return results
    }
}

/// Errors that can occur when checking mobile platform support
public enum MobilePlatformError: Error, LocalizedError {
    case invalidPackageName(String)
    case invalidResponse
    case httpError(statusCode: Int)
    
    public var errorDescription: String? {
        switch self {
        case .invalidPackageName(let name):
            return "Invalid package name: \(name)"
        case .invalidResponse:
            return "Invalid response from PyPI"
        case .httpError(let code):
            return "HTTP error: \(code)"
        }
    }
}
