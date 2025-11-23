import Foundation
import ArgumentParser

@main
struct MobileWheelsChecker: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mobile-wheels-checker",
        abstract: "Check PyPI packages for iOS/Android wheel support",
        discussion: """
        A toolkit for analyzing Python package mobile platform support.
        
        Commands:
          • database init    - Initialize Realm database with package list
          • database process - Process packages and check wheel/dependency support
          • database update  - Re-process packages (force update)
          • database maintain- Smart maintenance with age-based dependency updates
          • export           - Export database to various formats (JSON, Markdown, SQL)
          • inspect          - Inspect database contents and download counts
        
        Workflow:
          1. mobile-wheels-checker database init --limit 1000
          2. mobile-wheels-checker database process --concurrent 20
          3. mobile-wheels-checker export --json --markdown
        """,
        version: "2.0.0",
        subcommands: [Database.self, Export.self, Inspect.self],
        defaultSubcommand: Database.self
    )
}
