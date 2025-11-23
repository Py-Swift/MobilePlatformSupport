import Foundation
import ArgumentParser

// MARK: - Database Command
struct Database: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "database",
        abstract: "Database operations (init, process, update, maintain)",
        subcommands: [Init.self, Process.self, Update.self, Maintain.self],
        defaultSubcommand: Init.self
    )
}
