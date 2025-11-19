import Foundation
import MobilePlatformSupport

struct DependencyChecker {
    
    static func checkPackageWithDependencies(packageName: String, depth: Int = 2) async {
        print("🔍 Dependency Checker for: \(packageName)")
        print(String(repeating: "=", count: 71))
        print()
        
        let checker = MobilePlatformSupport()
        
        do {
            var visited = Set<String>()
            let results = try await checker.checkWithDependencies(
                packageName: packageName,
                depth: depth,
                visited: &visited
            )
            
            guard !results.isEmpty else {
                print("❌ Package not found or has no binary wheels")
                return
            }
            
            // Separate by package type
            let mainPackage = results[packageName]
            let dependencies = results.filter { $0.key != packageName }
            
            // Display main package
            if let main = mainPackage {
                print("📦 Main Package:")
                print(String(repeating: "-", count: 71))
                displayPackage(main)
                print()
            }
            
            // Display dependencies
            if !dependencies.isEmpty {
                print("📚 Dependencies (\(dependencies.count)):")
                print(String(repeating: "-", count: 71))
                print("\("Package".padding(toLength: 30, withPad: " ", startingAt: 0)) \("Android".padding(toLength: 20, withPad: " ", startingAt: 0)) \("iOS".padding(toLength: 20, withPad: " ", startingAt: 0))")
                print(String(repeating: "-", count: 71))
                
                for (name, info) in dependencies.sorted(by: { $0.key < $1.key }) {
                    let androidStatus = formatStatus(info.android)
                    let iosStatus = formatStatus(info.ios)
                    print("\(name.padding(toLength: 30, withPad: " ", startingAt: 0)) \(androidStatus.padding(toLength: 20, withPad: " ", startingAt: 0)) \(iosStatus.padding(toLength: 20, withPad: " ", startingAt: 0))")
                }
                print()
            }
            
            // Summary
            print("📈 Summary:")
            let totalPackages = results.count
            let androidSupport = results.values.filter { $0.android == .success }.count
            let iosSupport = results.values.filter { $0.ios == .success }.count
            let bothSupport = results.values.filter { $0.android == .success && $0.ios == .success }.count
            let unsupported = results.values.filter { 
                ($0.android == .warning || $0.android == nil) && 
                ($0.ios == .warning || $0.ios == nil) 
            }.count
            
            print("- Total packages: \(totalPackages) (\(packageName) + \(dependencies.count) dependencies)")
            print("- Android support: \(androidSupport)/\(totalPackages)")
            print("- iOS support: \(iosSupport)/\(totalPackages)")
            print("- Both platforms: \(bothSupport)/\(totalPackages)")
            
            if unsupported > 0 {
                print("- ⚠️  Unsupported: \(unsupported)/\(totalPackages)")
                print("\n⚠️  Warning: Some dependencies don't have mobile support!")
            } else {
                print("\n✅ All dependencies support mobile platforms!")
            }
            
        } catch {
            print("❌ Error: \(error.localizedDescription)")
        }
    }
    
    static func displayPackage(_ package: PackageInfo) {
        print("  Name: \(package.name)")
        print("  Android: \(formatStatus(package.android))")
        print("  iOS: \(formatStatus(package.ios))")
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

// Parse command line arguments
let args = ProcessInfo.processInfo.arguments

if args.count < 2 {
    print("Usage: dependency-checker <package-name> [depth]")
    print("Example: dependency-checker numpy 2")
    exit(1)
}

let packageName = args[1]
let depth = args.count > 2 ? Int(args[2]) ?? 2 : 2

await DependencyChecker.checkPackageWithDependencies(packageName: packageName, depth: depth)
