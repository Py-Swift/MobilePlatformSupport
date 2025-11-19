import Foundation
import MobilePlatformSupport

public struct MarkdownReportGenerator {
    public init() {}
    
    public func generate(
        limit: Int,
        depsEnabled: Bool,
        officialBinaryWheels: [PackageInfo],
        pyswiftBinaryWheels: [PackageInfo],
        purePython: [PackageInfo],
        binaryWithoutMobile: [PackageInfo],
        purePythonSorted: [PackageInfo],
        binaryWithoutMobileSorted: [PackageInfo],
        allPackagesWithDeps: [(PackageInfo, [PackageInfo], Bool)],
        timestamp: Date,
        mainFilename: String = "mobile-wheels-results.md",
        purePythonFilename: String = "pure-python-packages.md",
        binaryWithoutMobileFilename: String = "binary-without-mobile.md"
    ) throws {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let dateString = dateFormatter.string(from: timestamp)
        
        // Extract just the filename for relative links (not the full path)
        let purePythonLinkName = (purePythonFilename as NSString).lastPathComponent
        let binaryWithoutMobileLinkName = (binaryWithoutMobileFilename as NSString).lastPathComponent
        
        var markdown = """
        # Mobile Platform Support Report
        
        **Generated:** \(dateString)  
        **Packages Checked:** \(limit)  
        **Dependency Checking:** \(depsEnabled ? "Enabled" : "Disabled")
        
        ---
        
        ## 🔧 Official Binary Wheels (PyPI)
        
        Packages with official iOS/Android wheels available on PyPI.
        
        | Package | Android | iOS |\(depsEnabled ? " Dependencies |" : "")
        |---------|---------|-----|\(depsEnabled ? "-------------|" : "")
        
        """
        
        for package in officialBinaryWheels {
            let androidStatus = formatStatusMarkdown(package.android)
            let iosStatus = formatStatusMarkdown(package.ios)
            
            if depsEnabled {
                if let depInfo = allPackagesWithDeps.first(where: { $0.0.name == package.name }) {
                    let depsOK = depInfo.2 ? "✅ All supported" : "⚠️ Some unsupported"
                    let depCount = depInfo.1.count
                    markdown += "| `\(package.name)` | \(androidStatus) | \(iosStatus) | \(depsOK) (\(depCount)) |\n"
                }
            } else {
                markdown += "| `\(package.name)` | \(androidStatus) | \(iosStatus) |\n"
            }
        }
        
        if officialBinaryWheels.isEmpty {
            markdown += "\n_No packages found._\n"
        }
        
        markdown += """
        
        
        ## 🔧 PySwift Binary Wheels
        
        Custom iOS/Android builds from [pypi.anaconda.org/pyswift/simple](https://pypi.anaconda.org/pyswift/simple).
        
        | Package | Android | iOS |\(depsEnabled ? " Dependencies |" : "")
        |---------|---------|-----|\(depsEnabled ? "-------------|" : "")
        
        """
        
        for package in pyswiftBinaryWheels {
            let androidStatus = formatStatusMarkdown(package.android)
            let iosStatus = formatStatusMarkdown(package.ios)
            
            if depsEnabled {
                if let depInfo = allPackagesWithDeps.first(where: { $0.0.name == package.name }) {
                    let depsOK = depInfo.2 ? "✅ All supported" : "⚠️ Some unsupported"
                    let depCount = depInfo.1.count
                    markdown += "| `\(package.name)` | \(androidStatus) | \(iosStatus) | \(depsOK) (\(depCount)) |\n"
                }
            } else {
                markdown += "| `\(package.name)` | \(androidStatus) | \(iosStatus) |\n"
            }
        }
        
        if pyswiftBinaryWheels.isEmpty {
            markdown += "\n_No packages found._\n"
        }
        
        markdown += """
        
        
        ## 🐍 Pure Python Packages
        
        Packages that work on all platforms (no binary dependencies).
        
        """
        
        if purePython.count > 100 {
            markdown += "_Showing first 100 packages by download popularity. Total: \(purePython.count)_\n\n"
            markdown += "📄 **[View all \(purePython.count) pure Python packages (A-Z)](\(purePythonLinkName))**\n\n"
        }
        
        markdown += """
        | Package | Android | iOS |\(depsEnabled ? " Dependencies |" : "")
        |---------|---------|-----|\(depsEnabled ? "-------------|" : "")
        
        """
        
        let maxDisplay = min(100, purePython.count)
        for package in purePython.prefix(maxDisplay) {
            let androidStatus = formatStatusMarkdown(package.android)
            let iosStatus = formatStatusMarkdown(package.ios)
            
            if depsEnabled {
                if let depInfo = allPackagesWithDeps.first(where: { $0.0.name == package.name }) {
                    let depsOK = depInfo.2 ? "✅ All supported" : "⚠️ Some unsupported"
                    let depCount = depInfo.1.count
                    markdown += "| `\(package.name)` | \(androidStatus) | \(iosStatus) | \(depsOK) (\(depCount)) |\n"
                }
            } else {
                markdown += "| `\(package.name)` | \(androidStatus) | \(iosStatus) |\n"
            }
        }
        
        if purePython.count > 100 {
            markdown += "\n_... and \(purePython.count - 100) more packages. [View full list](\(purePythonLinkName))_\n"
        }
        
        markdown += """
        
        
        ## ❌ Binary Packages Without Mobile Support
        
        Packages with binary wheels but no iOS/Android support.
        
        """
        
        if binaryWithoutMobile.count > 100 {
            markdown += "_Showing first 100 packages by download popularity. Total: \(binaryWithoutMobile.count)_\n\n"
            markdown += "📄 **[View all \(binaryWithoutMobile.count) packages without mobile support (A-Z)](\(binaryWithoutMobileLinkName))**\n\n"
        }
        
        markdown += """
        | Package | Android | iOS |\(depsEnabled ? " Dependencies |" : "")
        |---------|---------|-----|\(depsEnabled ? "-------------|" : "")
        
        """
        
        let maxBinaryDisplay = min(100, binaryWithoutMobile.count)
        for package in binaryWithoutMobile.prefix(maxBinaryDisplay) {
            let androidStatus = formatStatusMarkdown(package.android)
            let iosStatus = formatStatusMarkdown(package.ios)
            
            if depsEnabled {
                if let depInfo = allPackagesWithDeps.first(where: { $0.0.name == package.name }) {
                    let depsOK = depInfo.2 ? "✅ All supported" : "⚠️ Some unsupported"
                    let depCount = depInfo.1.count
                    markdown += "| `\(package.name)` | \(androidStatus) | \(iosStatus) | \(depsOK) (\(depCount)) |\n"
                }
            } else {
                markdown += "| `\(package.name)` | \(androidStatus) | \(iosStatus) |\n"
            }
        }
        
        if binaryWithoutMobile.isEmpty {
            markdown += "\n_No packages found._\n"
        } else if binaryWithoutMobile.count > 100 {
            markdown += "\n_... and \(binaryWithoutMobile.count - 100) more packages. [View full list](\(binaryWithoutMobileLinkName))_\n"
        }
        
        // Summary statistics
        let allBinaryWheels = officialBinaryWheels + pyswiftBinaryWheels
        let androidSuccess = allBinaryWheels.filter { $0.android == .success }.count
        let iosSuccess = allBinaryWheels.filter { $0.ios == .success }.count
        let bothSupported = allBinaryWheels.filter { $0.android == .success && $0.ios == .success }.count
        
        markdown += """
        
        
        ## 📈 Summary Statistics
        
        ### Package Distribution
        
        | Category | Count | Percentage |
        |----------|-------|------------|
        | Official Binary Wheels (PyPI) | \(officialBinaryWheels.count) | \(String(format: "%.1f%%", Double(officialBinaryWheels.count) / Double(limit) * 100)) |
        | PySwift Binary Wheels | \(pyswiftBinaryWheels.count) | \(String(format: "%.1f%%", Double(pyswiftBinaryWheels.count) / Double(limit) * 100)) |
        | Pure Python | \(purePython.count) | \(String(format: "%.1f%%", Double(purePython.count) / Double(limit) * 100)) |
        | Binary Without Mobile Support | \(binaryWithoutMobile.count) | \(String(format: "%.1f%%", Double(binaryWithoutMobile.count) / Double(limit) * 100)) |
        | **Total** | **\(limit)** | **100%** |
        
        ### Platform Support (Binary Wheels)
        
        | Platform | Count | Percentage |
        |----------|-------|------------|
        | Android Support | \(androidSuccess) / \(allBinaryWheels.count) | \(String(format: "%.1f%%", allBinaryWheels.isEmpty ? 0 : Double(androidSuccess) / Double(allBinaryWheels.count) * 100)) |
        | iOS Support | \(iosSuccess) / \(allBinaryWheels.count) | \(String(format: "%.1f%%", allBinaryWheels.isEmpty ? 0 : Double(iosSuccess) / Double(allBinaryWheels.count) * 100)) |
        | Both Platforms | \(bothSupported) / \(allBinaryWheels.count) | \(String(format: "%.1f%%", allBinaryWheels.isEmpty ? 0 : Double(bothSupported) / Double(allBinaryWheels.count) * 100)) |
        
        """
        
        if depsEnabled {
            let allDepsOK = allPackagesWithDeps.filter { $0.2 }.count
            let totalChecked = allPackagesWithDeps.count
            
            markdown += """
            ### Dependency Analysis
            
            | Status | Count | Percentage |
            |--------|-------|------------|
            | All Dependencies Supported | \(allDepsOK) | \(String(format: "%.1f%%", totalChecked == 0 ? 0 : Double(allDepsOK) / Double(totalChecked) * 100)) |
            | Some Dependencies Unsupported | \(totalChecked - allDepsOK) | \(String(format: "%.1f%%", totalChecked == 0 ? 0 : Double(totalChecked - allDepsOK) / Double(totalChecked) * 100)) |
            | **Total Packages with Dependencies** | **\(totalChecked)** | **100%** |
            
            """
        }
        
        markdown += """
        
        ---
        
        **Generated by:** [MobilePlatformSupport](https://github.com/Py-Swift/MobilePlatformSupport)  
        **Data Sources:**
        - PyPI: [pypi.org](https://pypi.org)
        - PySwift: [pypi.anaconda.org/pyswift/simple](https://pypi.anaconda.org/pyswift/simple)
        - Top Packages: [hugovk.github.io/top-pypi-packages](https://hugovk.github.io/top-pypi-packages/)
        
        """
        
        // Write main report file
        let mainFileURL = URL(fileURLWithPath: mainFilename)
        try markdown.write(to: mainFileURL, atomically: true, encoding: .utf8)
        print("\n✅ Markdown report exported to: \(mainFilename)")
        
        // Generate full pure Python packages file if needed
        if purePython.count > 100 {
            try generatePurePythonReport(
                packages: purePythonSorted,
                depsEnabled: depsEnabled,
                allPackagesWithDeps: allPackagesWithDeps,
                timestamp: timestamp,
                filename: purePythonFilename
            )
            print("✅ Full pure Python list exported to: \(purePythonFilename)")
        }
        
        // Generate full binary without mobile file if needed
        if binaryWithoutMobile.count > 100 {
            try generateBinaryWithoutMobileReport(
                packages: binaryWithoutMobileSorted,
                depsEnabled: depsEnabled,
                allPackagesWithDeps: allPackagesWithDeps,
                timestamp: timestamp,
                filename: binaryWithoutMobileFilename
            )
            print("✅ Full binary without mobile list exported to: \(binaryWithoutMobileFilename)")
        }
    }
    
    private func generatePurePythonReport(
        packages: [PackageInfo],
        depsEnabled: Bool,
        allPackagesWithDeps: [(PackageInfo, [PackageInfo], Bool)],
        timestamp: Date,
        filename: String
    ) throws {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let dateString = dateFormatter.string(from: timestamp)
        
        var markdown = """
        # Pure Python Packages - Full List
        
        **Generated:** \(dateString)  
        **Total Packages:** \(packages.count)
        
        Packages that work on all platforms (no binary dependencies).
        
        """
        
        var currentLetter = ""
        for package in packages {
            let firstLetter = String(package.name.prefix(1).uppercased())
            
            if firstLetter != currentLetter {
                currentLetter = firstLetter
                markdown += """
                
                ---
                
                ## \(currentLetter)
                
                | Package | Android | iOS |\(depsEnabled ? " Dependencies |" : "")
                |---------|---------|-----|\(depsEnabled ? "-------------|" : "")
                
                """
            }
            
            let androidStatus = formatStatusMarkdown(package.android)
            let iosStatus = formatStatusMarkdown(package.ios)
            
            if depsEnabled {
                if let depInfo = allPackagesWithDeps.first(where: { $0.0.name == package.name }) {
                    let depsOK = depInfo.2 ? "✅ All supported" : "⚠️ Some unsupported"
                    let depCount = depInfo.1.count
                    markdown += "| `\(package.name)` | \(androidStatus) | \(iosStatus) | \(depsOK) (\(depCount)) |\n"
                }
            } else {
                markdown += "| `\(package.name)` | \(androidStatus) | \(iosStatus) |\n"
            }
        }
        
        markdown += """
        
        
        ---
        
        **Generated by:** [MobilePlatformSupport](https://github.com/Py-Swift/MobilePlatformSupport)
        
        """
        
        let fileURL = URL(fileURLWithPath: filename)
        try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
    }
    
    private func generateBinaryWithoutMobileReport(
        packages: [PackageInfo],
        depsEnabled: Bool,
        allPackagesWithDeps: [(PackageInfo, [PackageInfo], Bool)],
        timestamp: Date,
        filename: String
    ) throws {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let dateString = dateFormatter.string(from: timestamp)
        
        var markdown = """
        # Binary Packages Without Mobile Support - Full List
        
        **Generated:** \(dateString)  
        **Total Packages:** \(packages.count)
        
        Packages with binary wheels but no iOS/Android support.
        
        """
        
        var currentLetter = ""
        for package in packages {
            let firstLetter = String(package.name.prefix(1).uppercased())
            
            if firstLetter != currentLetter {
                currentLetter = firstLetter
                markdown += """
                
                ---
                
                ## \(currentLetter)
                
                | Package | Android | iOS |\(depsEnabled ? " Dependencies |" : "")
                |---------|---------|-----|\(depsEnabled ? "-------------|" : "")
                
                """
            }
            
            let androidStatus = formatStatusMarkdown(package.android)
            let iosStatus = formatStatusMarkdown(package.ios)
            
            if depsEnabled {
                if let depInfo = allPackagesWithDeps.first(where: { $0.0.name == package.name }) {
                    let depsOK = depInfo.2 ? "✅ All supported" : "⚠️ Some unsupported"
                    let depCount = depInfo.1.count
                    markdown += "| `\(package.name)` | \(androidStatus) | \(iosStatus) | \(depsOK) (\(depCount)) |\n"
                }
            } else {
                markdown += "| `\(package.name)` | \(androidStatus) | \(iosStatus) |\n"
            }
        }
        
        markdown += """
        
        
        ---
        
        **Generated by:** [MobilePlatformSupport](https://github.com/Py-Swift/MobilePlatformSupport)
        
        """
        
        let fileURL = URL(fileURLWithPath: filename)
        try markdown.write(to: fileURL, atomically: true, encoding: .utf8)
    }
    
    private func formatStatusMarkdown(_ status: PlatformSupport?) -> String {
        guard let status = status else {
            return "❓ Unknown"
        }
        
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
