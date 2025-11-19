# MobilePlatformSupport Package

✅ **Successfully created!**

## What was created

A complete Swift package that replicates the functionality of [beeware/mobile-wheels utils.py](https://github.com/beeware/mobile-wheels/blob/main/utils.py) for checking Python package mobile platform support.

## Files Created

```
MobilePlatformSupport/
├── Package.swift                          # Swift package manifest
├── README.md                              # Complete documentation
├── EXAMPLES.md                            # Usage examples
└── Sources/
    ├── MobilePlatformSupport/
    │   └── MobilePlatformSupport.swift   # Main library implementation
    └── MobileWheelsChecker/
        └── main.swift                     # Example CLI tool
```

## Key Features

### ✅ Core Functionality
- **Check if packages have binary wheels** (not pure Python)
- **Detect Android/iOS platform support** for packages
- **Filter deprecated and non-mobile packages** automatically
- **Async/await API** for efficient operations
- **Returns array of binary packages** with platform support details

### ✅ Built-in Lists
- `deprecatedPackages`: Known deprecated packages (pycrypto, nose, etc.)
- `nonMobilePackages`: Packages incompatible with mobile (CUDA, Intel MKL, subprocess-based, etc.)

### ✅ Platform Support Status
- `success`: Has binary wheels for the platform ✅
- `pure-py`: Only pure Python wheels 🐍
- `warning`: No wheels available ⚠️

## Quick Usage

```swift
import MobilePlatformSupport

let checker = MobilePlatformSupport()

// Check if a package is binary
let isBinary = try await checker.isBinaryPackage("numpy")

// Get platform support details
if let info = try await checker.annotatePackage("numpy") {
    print("\(info.name) - Android: \(info.android), iOS: \(info.ios)")
}

// Get all binary packages from a list
let packages = ["numpy", "pandas", "pillow", "lxml"]
let results = try await checker.getBinaryPackages(from: packages)
```

## Running the Example Tool

```bash
cd MobilePlatformSupport
swift run mobile-wheels-checker
```

This will check 10 popular packages and display their mobile support status.

## Integration with PSProject

This package can be used to:
1. Validate dependencies in `pyproject.toml` for mobile compatibility
2. Generate mobile platform support reports
3. Warn users about packages without mobile support
4. Help developers choose mobile-friendly dependencies

## Related Documentation

- [KIVY_LIBRARY_GUIDELINES.md](../KIVY_LIBRARY_GUIDELINES.md) - Guidelines for creating mobile libraries
- [README.md](README.md) - Full API documentation
- [EXAMPLES.md](EXAMPLES.md) - Detailed usage examples

## Technical Details

The implementation mirrors the Python version:
- Fetches package metadata from PyPI JSON API (`https://pypi.org/pypi/{package}/json`)
- Parses wheel filenames following the [wheel filename convention](https://packaging.python.org/en/latest/specifications/binary-distribution-format/#file-name-convention)
- Extracts platform tags from: `{distribution}-{version}(-{build})?-{python}-{abi}-{platform}.whl`
- Filters out pure Python wheels (platform tag = "any")

## Next Steps

You can now:
1. ✅ Import this package in other Swift projects
2. ✅ Use it in PSProject's Update command to validate dependencies
3. ✅ Generate reports for your Python mobile projects
4. ✅ Build CLI tools for package validation
