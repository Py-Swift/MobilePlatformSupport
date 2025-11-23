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
    public var androidVersion: String?
    public var iosVersion: String?
    public var version: String?
    
    public init(name: String, android: PlatformSupport? = nil, ios: PlatformSupport? = nil, source: PackageIndex? = nil, androidVersion: String? = nil, iosVersion: String? = nil, version: String? = nil) {
        self.name = name
        self.android = android
        self.ios = ios
        self.source = source
        self.androidVersion = androidVersion
        self.iosVersion = iosVersion
        self.version = version
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
    case kivyschool = "KivySchool"
}

/// Mobile platform support checker for Python packages
public class MobilePlatformSupport {
    
    private static let baseURL = "https://pypi.org/pypi"
    private static let pyswiftSimpleURL = "https://pypi.anaconda.org/pyswift/simple"
    private static let kivyschoolSimpleURL = "https://pypi.anaconda.org/kivyschool/simple"
    
    private var pyswiftPackages: Set<String>?
    private var kivyschoolPackages: Set<String>?
    
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
        "windows-curses",
        "pywinauto",
        "winshell",
        "wmi",
        "comtypes",
        "pythonnet",
        "pywin32-ctypes",
        "winreg",
        "win32-setctime"
    ]
    
    /// Check if a package name is GPU/CUDA related (should be filtered out for mobile)
    public static func isGPUPackage(_ packageName: String) -> Bool {
        let normalized = packageName.lowercased()
        
        // Common GPU/CUDA prefixes and keywords
        let gpuPatterns = [
            "cuda", "cupy", "nvidia-", "nvcc", "nccl", "cupti", "nvtx",
            "cublas", "cudnn", "cufft", "curand", "cusolver", "cusparse",
            "nvrtc", "nvjitlink", "tensorrt", "-gpu", "-cuda",
            "jax-cuda", "torch-cuda", "tensorflow-gpu", "paddlepaddle-gpu",
            "onnxruntime-gpu", "mxnet-cu", "triton"
        ]
        
        // Check patterns
        for pattern in gpuPatterns {
            if normalized.contains(pattern) {
                return true
            }
        }
        
        // Check if it starts with gpu- (like gpu-enabled)
        if normalized.hasPrefix("gpu-") {
            return true
        }
        
        return false
    }
    
    /// Check if a package name is Windows-only (should be filtered out for mobile)
    public static func isWindowsPackage(_ packageName: String) -> Bool {
        let normalized = packageName.lowercased()
        
        // Windows-specific patterns and keywords
        let windowsPatterns = [
            "pywin", "win32", "winreg", "wmi", "windows-", "pywinauto",
            "winshell", "pywinusb", "win-", "-win32", "msvc", "comtypes",
            "pywinpty", "windows-curses", "winsys", "winappdbg"
        ]
        
        // Check patterns
        for pattern in windowsPatterns {
            if normalized.contains(pattern) {
                return true
            }
        }
        
        return false
    }
    
    /// Filter out GPU/CUDA and non-mobile packages from a list
    public static func filterMobileCompatiblePackages(_ packages: [String]) -> [String] {
        return packages.filter { packageName in
            let normalized = normalizePackageName(packageName)
            
            // Exclude if it's deprecated
            if deprecatedPackages.contains(normalized) {
                return false
            }
            
            // Exclude if it's non-mobile
            if nonMobilePackages.contains(normalized) {
                return false
            }
            
            // Exclude if it's GPU-related
            if isGPUPackage(normalized) {
                return false
            }
            
            // Exclude if it's Windows-only
            if isWindowsPackage(normalized) {
                return false
            }
            
            return true
        }
    }
    
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
                let normalized = Self.normalizePackageName(packageName)
                packages.insert(normalized)
            }
        }
        
        pyswiftPackages = packages
        print("📦 Loaded \(packages.count) packages from PySwift index")
        return packages
    }
    
    /// Normalize package name for comparison (PEP 503)
    /// Converts to lowercase and replaces hyphens, underscores, and dots with hyphens
    public static func normalizePackageName(_ name: String) -> String {
        return name.lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: ".", with: "-")
    }
    
    /// Check if a package is available in PySwift index
    public func isAvailableInPySwift(_ packageName: String) async throws -> Bool {
        let packages = try await fetchPySwiftPackages()
        let normalized = Self.normalizePackageName(packageName)
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
    
    /// Download and parse the KivySchool simple index to get available packages
    public func fetchKivySchoolPackages() async throws -> Set<String> {
        if let cached = kivyschoolPackages {
            return cached
        }
        
        guard let url = URL(string: Self.kivyschoolSimpleURL) else {
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
        var packages = Set<String>()
        let lines = html.components(separatedBy: .newlines)
        
        for line in lines {
            if let startRange = line.range(of: "<a href=\""),
               let endRange = line.range(of: "\">", range: startRange.upperBound..<line.endIndex),
               let closeTag = line.range(of: "</a>", range: endRange.upperBound..<line.endIndex) {
                let packageName = String(line[endRange.upperBound..<closeTag.lowerBound])
                let normalized = Self.normalizePackageName(packageName)
                packages.insert(normalized)
            }
        }
        
        kivyschoolPackages = packages
        print("📦 Loaded \(packages.count) packages from KivySchool index")
        return packages
    }
    
    /// Check if a package is available in KivySchool index
    public func isAvailableInKivySchool(_ packageName: String) async throws -> Bool {
        let packages = try await fetchKivySchoolPackages()
        let normalized = Self.normalizePackageName(packageName)
        return packages.contains(normalized)
    }
    
    /// Fetch wheel filenames from KivySchool package page
    public func fetchKivySchoolWheels(for packageName: String) async throws -> [String] {
        guard let url = getKivySchoolPackageURL(for: packageName) else {
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
        let normalized = Self.normalizePackageName(packageName)
        return URL(string: "\(Self.pyswiftSimpleURL)/\(normalized)/")
    }
    
    /// Get KivySchool package URL
    private func getKivySchoolPackageURL(for packageName: String) -> URL? {
        let normalized = Self.normalizePackageName(packageName)
        return URL(string: "\(Self.kivyschoolSimpleURL)/\(normalized)/")
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
    
    /// Extract version and Python version from wheel filename
    /// Wheel filename format: {distribution}-{version}(-{build tag})?-{python tag}-{abi tag}-{platform tag}.whl
    private func extractVersionInfo(from filename: String) -> (version: String?, pythonVersion: Int?) {
        let withoutExtension = filename.replacingOccurrences(of: ".whl", with: "")
        let components = withoutExtension.split(separator: "-")
        
        var packageVersion: String? = nil
        var pythonVersion: Int? = nil
        
        // Version is typically the second component
        // Example: numpy-1.24.3-cp313-cp313-ios_arm64.whl
        if components.count >= 2 {
            packageVersion = String(components[1])
        }
        
        // Extract Python version from tag (cp313, cp312, etc.)
        for component in components {
            let str = String(component)
            if str.hasPrefix("cp") {
                if let pyVer = Int(str.dropFirst(2)) {
                    pythonVersion = pyVer
                    break
                }
            }
        }
        
        return (packageVersion, pythonVersion)
    }
    
    /// Compare two semantic versions (e.g., "3.10.7" vs "3.8.2")
    /// Returns true if version1 is greater than version2
    private func isVersionGreater(_ version1: String, _ version2: String) -> Bool {
        let v1Parts = version1.split(separator: ".").compactMap { Int($0) }
        let v2Parts = version2.split(separator: ".").compactMap { Int($0) }
        
        let maxLength = max(v1Parts.count, v2Parts.count)
        
        for i in 0..<maxLength {
            let v1 = i < v1Parts.count ? v1Parts[i] : 0
            let v2 = i < v2Parts.count ? v2Parts[i] : 0
            
            if v1 > v2 {
                return true
            } else if v1 < v2 {
                return false
            }
        }
        
        return false  // Equal versions
    }
    
    
    /// Compare two semantic versions (e.g., "3.10.7" vs "3.8.2")
    
    
    
    /// Annotate a package with platform support information
    /// Extract version from wheel filename
    /// Wheel filename format: {distribution}-{version}(-{build tag})?-{python tag}-{abi tag}-{platform tag}.whl
    private func extractVersion(from filename: String) -> String? {
        let withoutExtension = filename.replacingOccurrences(of: ".whl", with: "")
        let components = withoutExtension.split(separator: "-")
        
        // Version is typically the second component
        // Example: numpy-1.24.3-cp39-cp39-ios_arm64.whl -> version is "1.24.3"
        if components.count >= 2 {
            return String(components[1])
        }
        return nil
    }

    /// Also checks if package is available in PySwift and KivySchool indexes and reads their wheels
    public func annotatePackage(_ packageName: String) async throws -> PackageInfo? {
        // Skip deprecated and non-mobile packages
        if Self.deprecatedPackages.contains(packageName) || Self.nonMobilePackages.contains(packageName) {
            return nil
        }
        
        var availablePlatforms = Set<String>()
        var pypiPlatforms = Set<String>()
        var pyswiftPlatforms = Set<String>()
        var kivyschoolPlatforms = Set<String>()
        var pypiVersions: [String: (version: String, pyVer: Int)] = [:]  // platform -> (version, python_version)
        var pyswiftVersions: [String: (version: String, pyVer: Int)] = [:]
        var kivyschoolVersions: [String: (version: String, pyVer: Int)] = [:]
        
        // Check PyPI first (official source takes priority)
        do {
            let data = try await fetchPackageData(for: packageName)
            for download in data.urls where download.packagetype == "bdist_wheel" {
                let platformTag = extractPlatformTag(from: download.filename)
                pypiPlatforms.insert(platformTag)
                availablePlatforms.insert(platformTag)
                
                // Track version with Python version for later selection
                let versionInfo = extractVersionInfo(from: download.filename)
                if let version = versionInfo.version, let pyVer = versionInfo.pythonVersion {
                    // Keep the version with highest Python version (prefer cp313, cp314, etc.)
                    if let existing = pypiVersions[platformTag] {
                        if pyVer > existing.pyVer || (pyVer == existing.pyVer && isVersionGreater(version, existing.version)) {
                            pypiVersions[platformTag] = (version, pyVer)
                        }
                    } else {
                        pypiVersions[platformTag] = (version, pyVer)
                    }
                }
            }
        } catch {
            // PyPI error, will check PySwift and KivySchool as fallback
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
                
                // Track version with Python version for later selection
                let versionInfo = extractVersionInfo(from: filename)
                if let version = versionInfo.version, let pyVer = versionInfo.pythonVersion {
                    // Keep the version with highest Python version (prefer cp313, cp314, etc.)
                    if let existing = pyswiftVersions[platformTag] {
                        if pyVer > existing.pyVer || (pyVer == existing.pyVer && isVersionGreater(version, existing.version)) {
                            pyswiftVersions[platformTag] = (version, pyVer)
                        }
                    } else {
                        pyswiftVersions[platformTag] = (version, pyVer)
                    }
                }
            }
        }
        
        // Check if package is in KivySchool
        let inKivySchool = try await isAvailableInKivySchool(packageName)
        
        if inKivySchool {
            // Fetch wheels from KivySchool
            let kivyschoolWheels = try await fetchKivySchoolWheels(for: packageName)
            for filename in kivyschoolWheels {
                let platformTag = extractPlatformTag(from: filename)
                kivyschoolPlatforms.insert(platformTag)
                availablePlatforms.insert(platformTag)
                
                // Track version with Python version for later selection
                let versionInfo = extractVersionInfo(from: filename)
                if let version = versionInfo.version, let pyVer = versionInfo.pythonVersion {
                    // Keep the version with highest Python version (prefer cp313, cp314, etc.)
                    if let existing = kivyschoolVersions[platformTag] {
                        if pyVer > existing.pyVer || (pyVer == existing.pyVer && isVersionGreater(version, existing.version)) {
                            kivyschoolVersions[platformTag] = (version, pyVer)
                        }
                    } else {
                        kivyschoolVersions[platformTag] = (version, pyVer)
                    }
                }
            }
        }
        
        // If no platforms found at all, it might be a pure source package
        // Treat it as unknown/pure Python
        if availablePlatforms.isEmpty {
            var package = PackageInfo(name: packageName, source: .pypi)
            package.android = .purePython
            package.ios = .purePython
            return package
        }
        
        // Determine if this is a pure Python package (only "any" platform)
        let isPurePython = availablePlatforms == ["any"]
        
        // Determine source: PyPI official wheels are preferred, then PySwift, then KivySchool
        let pypiHasMobileWheels = pypiPlatforms.contains("ios") || pypiPlatforms.contains("android")
        let pyswiftHasMobileWheels = pyswiftPlatforms.contains("ios") || pyswiftPlatforms.contains("android")
        let kivyschoolHasMobileWheels = kivyschoolPlatforms.contains("ios") || kivyschoolPlatforms.contains("android")
        let source: PackageIndex = pypiHasMobileWheels ? .pypi : (pyswiftHasMobileWheels ? .pyswift : (kivyschoolHasMobileWheels ? .kivyschool : .pypi))
        
        var package = PackageInfo(name: packageName, source: source)
        
        // Find the latest version across all wheels (priority: PyPI > PySwift > KivySchool)
        var latestVersion: String? = nil
        if !pypiVersions.isEmpty {
            latestVersion = pypiVersions.values.map { $0.version }.max(by: { !isVersionGreater($0, $1) })
        } else if !pyswiftVersions.isEmpty {
            latestVersion = pyswiftVersions.values.map { $0.version }.max(by: { !isVersionGreater($0, $1) })
        } else if !kivyschoolVersions.isEmpty {
            latestVersion = kivyschoolVersions.values.map { $0.version }.max(by: { !isVersionGreater($0, $1) })
        }
        package.version = latestVersion
        
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
                // Set version from highest Python version wheel (priority: PyPI > PySwift > KivySchool)
                if source == .pypi, let versionInfo = pypiVersions["android"] {
                    package.androidVersion = versionInfo.version
                } else if source == .pyswift, let versionInfo = pyswiftVersions["android"] {
                    package.androidVersion = versionInfo.version
                } else if source == .kivyschool, let versionInfo = kivyschoolVersions["android"] {
                    package.androidVersion = versionInfo.version
                }
            case .ios:
                package.ios = support
                // Set version from highest Python version wheel (priority: PyPI > PySwift > KivySchool)
                if source == .pypi, let versionInfo = pypiVersions["ios"] {
                    package.iosVersion = versionInfo.version
                } else if source == .pyswift, let versionInfo = pyswiftVersions["ios"] {
                    package.iosVersion = versionInfo.version
                } else if source == .kivyschool, let versionInfo = kivyschoolVersions["ios"] {
                    package.iosVersion = versionInfo.version
                }
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
                        let percentage = Int((Double(processedCount) / Double(packagesToCheck.count)) * 100)
                        print("\r\u{001B}[K[\(results.count)/\(limit)] [\(percentage)%] processing...", terminator: "")
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
                let percentage = Int((Double(processedCount) / Double(packagesToCheck.count)) * 100)
                print("\r\u{001B}[K[\(results.count)/\(limit)] [\(percentage)% done] processing...", terminator: "")
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
    /// Note: Relies on the `requires_dist` field in PyPI package metadata.
    /// Some packages (e.g., kivymd) may have incomplete metadata on PyPI,
    /// resulting in missing dependencies in the output.
    public func getDependencies(for packageName: String) async throws -> [String] {
        do {
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
        } catch {
            // If we can't fetch package data, return empty dependencies
            // This allows the tool to continue instead of crashing
            return []
        }
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
            
            // Get and check dependencies only if depth > 1
            if depth > 1 {
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
