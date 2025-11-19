# MobilePlatformSupport

A Swift package for checking mobile platform (Android/iOS) support for Python packages on PyPI. This is a Swift equivalent of the [beeware/mobile-wheels](https://github.com/beeware/mobile-wheels) `utils.py` functionality.

## Overview

This package helps you determine whether Python packages have binary wheel support for mobile platforms (Android and iOS). It's particularly useful when building mobile applications with Python, as many packages with C extensions need specific wheels compiled for mobile architectures.

## Features

- ✅ Check if a Python package has binary wheels (not pure Python)
- ✅ Detect platform support for Android and iOS
- ✅ Filter out deprecated and non-mobile packages
- ✅ Async/await API for efficient network operations
- ✅ Built-in lists of packages known to be incompatible with mobile

## Installation

Add this package to your `Package.swift` dependencies:

```swift
dependencies: [
    .package(path: "../MobilePlatformSupport")
]
```

## Usage

### Basic Usage - Check if a Package is Binary

```swift
import MobilePlatformSupport

let checker = MobilePlatformSupport()

// Check if numpy has binary wheels
let isBinary = try await checker.isBinaryPackage("numpy")
print("numpy is binary: \(isBinary)") // true
```

### Get Platform Support Information

```swift
import MobilePlatformSupport

let checker = MobilePlatformSupport()

// Get full platform support details
if let packageInfo = try await checker.annotatePackage("numpy") {
    print("Package: \(packageInfo.name)")
    print("Android support: \(packageInfo.android?.rawValue ?? "unknown")")
    print("iOS support: \(packageInfo.ios?.rawValue ?? "unknown")")
}
```

### Check Multiple Packages

```swift
import MobilePlatformSupport

let checker = MobilePlatformSupport()

let packages = ["numpy", "pandas", "pillow", "cryptography", "lxml"]

// Get all binary packages with platform support
let binaryPackages = try await checker.getBinaryPackages(from: packages)

for package in binaryPackages {
    print("\(package.name):")
    print("  Android: \(package.android?.rawValue ?? "unknown")")
    print("  iOS: \(package.ios?.rawValue ?? "unknown")")
}
```

### Filter Only Binary Packages

```swift
import MobilePlatformSupport

let checker = MobilePlatformSupport()

let allPackages = ["numpy", "requests", "pillow", "click", "pyyaml"]

// Get only the names of packages with binary wheels
let binaryOnly = try await checker.filterBinaryPackages(from: allPackages)
print("Binary packages: \(binaryOnly)")
// Output: ["numpy", "pillow", "pyyaml"]
```

## Platform Support Types

The package returns one of three support levels for each platform:

- **`success`**: Has compiled binary wheels for the platform ✅
- **`pure-py`**: Only has pure Python wheels (will likely work but may have reduced performance) 🐍
- **`warning`**: No wheels available for the platform ⚠️

## Excluded Packages

The package automatically excludes:

### Deprecated Packages
- BeautifulSoup, bs4, distribute, django-social-auth, nose, pep8, pycrypto, pypular, sklearn, subprocess32

### Non-Mobile Packages
- **CUDA/Nvidia packages**: Not available on mobile platforms
- **Intel-specific packages**: Intel processors not used on mobile
- **Subprocess-based packages**: Subprocesses not well supported on mobile
- **Windows-specific packages**: Not relevant for mobile platforms

See `MobilePlatformSupport.deprecatedPackages` and `MobilePlatformSupport.nonMobilePackages` for complete lists.

## API Reference

### `MobilePlatformSupport`

Main class for checking platform support.

#### Methods

- `init(session: URLSession = .shared)`: Initialize with optional custom URLSession
- `isBinaryPackage(_ packageName: String) async throws -> Bool`: Check if package has binary wheels
- `annotatePackage(_ packageName: String) async throws -> PackageInfo?`: Get full platform support info
- `getBinaryPackages(from: [String], maxResults: Int? = nil) async throws -> [PackageInfo]`: Process multiple packages
- `filterBinaryPackages(from: [String]) async throws -> [String]`: Get only binary package names

### `PackageInfo`

```swift
struct PackageInfo {
    let name: String
    var android: PlatformSupport?
    var ios: PlatformSupport?
}
```

### `PlatformSupport`

```swift
enum PlatformSupport: String {
    case success = "success"     // Has compiled wheels
    case purePython = "pure-py"  // Pure Python only
    case warning = "warning"     // No wheels available
}
```

### `MobilePlatform`

```swift
enum MobilePlatform: String {
    case android
    case ios
}
```

## Error Handling

```swift
do {
    let info = try await checker.annotatePackage("numpy")
    // Use info
} catch MobilePlatformError.invalidPackageName(let name) {
    print("Invalid package: \(name)")
} catch MobilePlatformError.httpError(let code) {
    print("HTTP error: \(code)")
} catch {
    print("Other error: \(error)")
}
```

## Implementation Details

This Swift package mirrors the functionality of the Python `utils.py` from [beeware/mobile-wheels](https://github.com/beeware/mobile-wheels):

- Fetches package metadata from PyPI JSON API
- Parses wheel filenames to extract platform tags
- Follows the [wheel filename convention](https://packaging.python.org/en/latest/specifications/binary-distribution-format/#file-name-convention)
- Filters out pure Python wheels (platform tag = "any")

## Related Resources

- [beeware/mobile-wheels](https://github.com/beeware/mobile-wheels) - Original Python implementation
- [Mobile Wheels Website](http://beeware.org/mobile-wheels/) - Visual dashboard of mobile package support
- [KIVY_LIBRARY_GUIDELINES.md](../KIVY_LIBRARY_GUIDELINES.md) - Guidelines for creating mobile-compatible libraries

## Command-Line Tool

The package includes a command-line tool `mobile-wheels-checker` for batch checking packages.

### Installation

```bash
cd MobilePlatformSupport
swift build -c release
```

### Usage

```bash
# Check top 100 most popular packages
swift run mobile-wheels-checker 100

# Check with dependency checking
swift run mobile-wheels-checker 500 --deps

# Check packages from PyPI Simple Index (all packages, alphabetically)
swift run mobile-wheels-checker 1000 --all

# Show help
swift run mobile-wheels-checker --help
```

### Options

| Option | Description |
|--------|-------------|
| `[LIMIT]` | Number of packages to check (default: 1000) |
| `-d, --deps` | Enable recursive dependency checking |
| `-a, --all` | Use PyPI Simple Index instead of top packages |
| `-c, --concurrent N` | Number of concurrent requests (default: 10, max: 50) |
| `-h, --help` | Show help message |

### Performance

The tool uses concurrent requests to significantly speed up package checking:

| Concurrency | 100 packages | 500 packages |
|-------------|-------------|--------------|
| Sequential (c=1) | 4.8s | ~24s |
| Default (c=10) | 3.2s | ~8s |
| Fast (c=20) | 2.5s | ~4s |
| Maximum (c=50) | 2.0s | ~2.5s |

```bash
# Default concurrency (10 concurrent requests)
swift run mobile-wheels-checker 500

# Faster processing with 30 concurrent requests
swift run mobile-wheels-checker 500 -c 30
```

**Note**: Respect PyPI's rate limits. The default (10 concurrent) is recommended for normal use.

### Data Sources

- **Default**: Top packages from [hugovk.github.io/top-pypi-packages](https://hugovk.github.io/top-pypi-packages/) (pre-ranked, ~8k packages)
- **--all flag**: All packages from [pypi.org/simple](https://pypi.org/simple/) (~700k packages, sorted by download count)

The `--all` flag fetches the complete package list from PyPI's Simple Index, then sorts it by download statistics to prioritize the most popular packages. This gives you access to the full PyPI ecosystem while still checking important packages first.

### Output

The tool generates:
1. **Terminal output** with four categorized tables:
   - 🔧 Official Binary Wheels (PyPI)
   - 🔧 PySwift Binary Wheels (custom iOS/Android builds)
   - 🐍 Pure Python Packages (first 100)
   - ❌ Binary Packages Without Mobile Support

2. **Markdown report**: `mobile-wheels-results.md` with complete listings and statistics

### PyPI Simple Index Scraping

The `--all` flag scrapes PyPI's Simple Index to get all available packages, then sorts by download count:

```swift
static func downloadAllPackagesFromSimpleIndex(sortedByDownloads: Bool = false) async throws -> [String] {
    // 1. Download and parse Simple Index HTML
    let url = URL(string: "https://pypi.org/simple/")!
    let (data, _) = try await URLSession.shared.data(from: url)
    
    // Parse HTML: <a href="/simple/package-name/">package-name</a>
    let pattern = #"<a href="/simple/[^/]+/">([^<]+)</a>"#
    // ... regex matching to extract ~700k packages
    
    // 2. If sorting requested, fetch download statistics
    if sortedByDownloads {
        let statsUrl = URL(string: "https://hugovk.github.io/top-pypi-packages/...")!
        let response = try await URLSession.shared.data(from: statsUrl)
        
        // Create ranking map and sort packages
        // Ranked packages first (by download count), then unranked alphabetically
    }
    
    return packages
}
```

This provides:
- **Complete coverage**: Access to all ~700k PyPI packages
- **Smart ordering**: Popular packages checked first (ranked by downloads)
- **Fallback**: Unranked packages appear alphabetically after ranked ones

The sorting ensures that even when checking the full PyPI catalog, you get meaningful results quickly by processing the most important packages first.

## License

This package is part of the PSProject ecosystem.
