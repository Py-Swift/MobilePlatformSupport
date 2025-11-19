# MobilePlatformSupport - Usage Examples

This document provides practical examples of how to use the MobilePlatformSupport package in your Swift projects.

## Example 1: Check a Single Package

```swift
import MobilePlatformSupport

let checker = MobilePlatformSupport()

// Check if numpy has binary wheels
do {
    let isBinary = try await checker.isBinaryPackage("numpy")
    print("numpy has binary wheels: \(isBinary)")
} catch {
    print("Error: \(error)")
}
```

## Example 2: Get Detailed Platform Support

```swift
import MobilePlatformSupport

let checker = MobilePlatformSupport()

do {
    if let info = try await checker.annotatePackage("pillow") {
        print("Package: \(info.name)")
        
        switch info.android {
        case .success:
            print("✅ Android: Fully supported with binary wheels")
        case .purePython:
            print("🐍 Android: Pure Python only (may have reduced performance)")
        case .warning:
            print("⚠️ Android: Not available")
        case .none:
            print("❓ Android: Unknown")
        }
        
        switch info.ios {
        case .success:
            print("✅ iOS: Fully supported with binary wheels")
        case .purePython:
            print("🐍 iOS: Pure Python only (may have reduced performance)")
        case .warning:
            print("⚠️ iOS: Not available")
        case .none:
            print("❓ iOS: Unknown")
        }
    } else {
        print("Package is pure Python or excluded")
    }
} catch {
    print("Error: \(error)")
}
```

## Example 3: Validate Dependencies for Mobile App

```swift
import MobilePlatformSupport

func validateDependencies(_ dependencies: [String]) async throws {
    let checker = MobilePlatformSupport()
    
    print("Validating \(dependencies.count) dependencies for mobile support...")
    
    var unsupportedAndroid: [String] = []
    var unsupportedIOS: [String] = []
    var warnings: [String] = []
    
    for dependency in dependencies {
        if let info = try await checker.annotatePackage(dependency) {
            // Check Android support
            if info.android == .warning {
                unsupportedAndroid.append(dependency)
            } else if info.android == .purePython {
                warnings.append("\(dependency): Android has pure Python only")
            }
            
            // Check iOS support
            if info.ios == .warning {
                unsupportedIOS.append(dependency)
            } else if info.ios == .purePython {
                warnings.append("\(dependency): iOS has pure Python only")
            }
        }
    }
    
    // Report results
    if unsupportedAndroid.isEmpty && unsupportedIOS.isEmpty {
        print("✅ All dependencies have mobile support!")
    } else {
        if !unsupportedAndroid.isEmpty {
            print("⚠️ Missing Android support:")
            for pkg in unsupportedAndroid {
                print("  - \(pkg)")
            }
        }
        if !unsupportedIOS.isEmpty {
            print("⚠️ Missing iOS support:")
            for pkg in unsupportedIOS {
                print("  - \(pkg)")
            }
        }
    }
    
    if !warnings.isEmpty {
        print("\nℹ️ Warnings:")
        for warning in warnings {
            print("  - \(warning)")
        }
    }
}

// Usage
let appDependencies = ["numpy", "pillow", "requests", "pyyaml", "cryptography"]
try await validateDependencies(appDependencies)
```

## Example 4: Generate Report for pyproject.toml Dependencies

```swift
import MobilePlatformSupport
import Foundation

func generateMobileSupportReport(from pyprojectPath: String) async throws {
    // Parse pyproject.toml to extract dependencies (simplified)
    let content = try String(contentsOfFile: pyprojectPath)
    
    // Extract dependency names (this is a simplified example)
    // In production, use a proper TOML parser
    let dependencies = extractDependencies(from: content)
    
    let checker = MobilePlatformSupport()
    let results = try await checker.getBinaryPackages(from: dependencies)
    
    // Generate markdown report
    var report = "# Mobile Platform Support Report\n\n"
    report += "| Package | Android | iOS |\n"
    report += "|---------|---------|-----|\n"
    
    for package in results {
        let android = formatMarkdown(package.android)
        let ios = formatMarkdown(package.ios)
        report += "| \(package.name) | \(android) | \(ios) |\n"
    }
    
    // Save report
    try report.write(toFile: "MOBILE_SUPPORT.md", atomically: true, encoding: .utf8)
    print("Report saved to MOBILE_SUPPORT.md")
}

func formatMarkdown(_ status: PlatformSupport?) -> String {
    guard let status = status else { return "❓ Unknown" }
    
    switch status {
    case .success:
        return "✅ Supported"
    case .purePython:
        return "🐍 Pure Python"
    case .warning:
        return "⚠️ Not Available"
    }
}

func extractDependencies(from content: String) -> [String] {
    // Simplified extraction - use proper TOML parser in production
    var deps: [String] = []
    let lines = content.components(separatedBy: .newlines)
    var inDepsSection = false
    
    for line in lines {
        if line.contains("[project.dependencies]") || line.contains("dependencies = [") {
            inDepsSection = true
            continue
        }
        
        if inDepsSection && line.contains("\"") {
            // Extract package name (before == or >=)
            if let match = line.range(of: "\"([^\">=<~!]+)", options: .regularExpression) {
                let dep = String(line[match]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                deps.append(dep)
            }
        }
        
        if line.contains("]") && inDepsSection {
            break
        }
    }
    
    return deps
}
```

## Example 5: Integration with PSProject Update Command

```swift
import MobilePlatformSupport
import Foundation

extension Update {
    func validateMobilePlatformSupport() async throws {
        print("🔍 Validating mobile platform support...")
        
        let checker = MobilePlatformSupport()
        
        // Get dependencies from pyproject.toml
        let dependencies = try loadDependencies()
        
        // Check for binary packages
        let binaryPackages = try await checker.filterBinaryPackages(from: dependencies)
        
        if binaryPackages.isEmpty {
            print("✅ All dependencies are pure Python")
            return
        }
        
        print("\n📦 Found \(binaryPackages.count) binary packages:")
        
        for packageName in binaryPackages {
            guard let info = try await checker.annotatePackage(packageName) else {
                continue
            }
            
            print("\n  \(info.name):")
            
            // Warn about unsupported platforms
            if info.android == .warning {
                print("    ⚠️  Android: No wheels available")
                print("       This package may not work on Android devices")
            }
            
            if info.ios == .warning {
                print("    ⚠️  iOS: No wheels available")
                print("       This package may not work on iOS devices")
            }
            
            if info.android == .success && info.ios == .success {
                print("    ✅ Both platforms supported")
            }
        }
    }
}
```

## Example 6: Command-Line Tool

```swift
// Sources/MobileWheelsChecker/main.swift
import Foundation
import MobilePlatformSupport

@main
struct MobileWheelsChecker {
    static func main() async {
        let arguments = CommandLine.arguments.dropFirst()
        
        if arguments.isEmpty {
            printUsage()
            return
        }
        
        let checker = MobilePlatformSupport()
        
        for packageName in arguments {
            print("\n📦 Checking \(packageName)...")
            
            do {
                if let info = try await checker.annotatePackage(packageName) {
                    printPackageInfo(info)
                } else {
                    print("  Pure Python package (no binary wheels)")
                }
            } catch {
                print("  ❌ Error: \(error.localizedDescription)")
            }
        }
    }
    
    static func printUsage() {
        print("""
        Usage: mobile-wheels-checker <package1> [package2] ...
        
        Examples:
          mobile-wheels-checker numpy
          mobile-wheels-checker numpy pandas pillow
        """)
    }
    
    static func printPackageInfo(_ info: PackageInfo) {
        print("  Name: \(info.name)")
        print("  Android: \(formatStatus(info.android))")
        print("  iOS: \(formatStatus(info.ios))")
    }
    
    static func formatStatus(_ status: PlatformSupport?) -> String {
        guard let status = status else { return "❓ Unknown" }
        
        switch status {
        case .success:
            return "✅ Supported"
        case .purePython:
            return "🐍 Pure Python"
        case .warning:
            return "⚠️ Not available"
        }
    }
}
```

Run it:
```bash
swift run mobile-wheels-checker numpy pandas pillow
```

## Running the Example Checker

Build and run the included command-line tool:

```bash
cd MobilePlatformSupport
swift build
swift run mobile-wheels-checker
```

This will check 10 popular packages and display their mobile platform support status.

## Integration Tips

1. **Error Handling**: Always wrap async calls in `do-catch` blocks
2. **Rate Limiting**: Consider adding delays between requests for large package lists
3. **Caching**: The checker uses URLSession, so you can provide a custom session with caching
4. **Excluded Packages**: Check against `MobilePlatformSupport.deprecatedPackages` and `nonMobilePackages` before querying
5. **Pure Python**: Packages with only "any" platform wheels are filtered out automatically

## See Also

- [KIVY_LIBRARY_GUIDELINES.md](../../KIVY_LIBRARY_GUIDELINES.md) - Guidelines for mobile library development
- [README.md](README.md) - Full API documentation
- [beeware/mobile-wheels](https://github.com/beeware/mobile-wheels) - Original Python implementation
