import Foundation
import SQLite3

/// SQLite database wrapper for exporting package data
///
/// Integer Enum Values (for space efficiency):
/// - android_support / ios_support: 0=unknown, 1=success, 2=pure-python, 3=warning
/// - source: 0=pypi, 1=pyswift, 2=kivyschool
/// - category: 0=unprocessed, 1=supported, 4=pure-python, 5=no-mobile-support
/// - dependency_status: 0=no-issues, 1=warning, 2=error
class SQLiteDatabase {
    private var db: OpaquePointer?
    private let path: String
    
    init(path: String) throws {
        self.path = path
        
        let result = sqlite3_open(path, &db)
        guard result == SQLITE_OK else {
            throw SQLiteError.openDatabase(message: String(cString: sqlite3_errmsg(db)))
        }
    }
    
    deinit {
        close()
    }
    
    func close() {
        if db != nil {
            sqlite3_close(db)
            db = nil
        }
    }
    
    /// Creates the database schema
    func createTables() throws {
        let createPackagesTable = """
        CREATE TABLE IF NOT EXISTS packages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            downloads INTEGER NOT NULL,
            android_support INTEGER NOT NULL,
            ios_support INTEGER NOT NULL,
            source INTEGER NOT NULL,
            category INTEGER NOT NULL,
            android_version TEXT,
            ios_version TEXT,
            latest_version TEXT,
            dependency_status INTEGER NOT NULL
        );
        """
        
        let createDependenciesTable = """
        CREATE TABLE IF NOT EXISTS dependencies (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            package_name TEXT NOT NULL,
            dependency_name TEXT NOT NULL,
            FOREIGN KEY (package_name) REFERENCES packages(name),
            UNIQUE(package_name, dependency_name)
        );
        """
        
        try execute(sql: createPackagesTable)
        try execute(sql: createDependenciesTable)
    }
    
    /// Creates indexes for better query performance
    func createIndexes() throws {
        let indexes = [
            "CREATE INDEX IF NOT EXISTS idx_name ON packages(name);",
            "CREATE INDEX IF NOT EXISTS idx_downloads ON packages(downloads DESC);",
            "CREATE INDEX IF NOT EXISTS idx_category ON packages(category);",
            "CREATE INDEX IF NOT EXISTS idx_android ON packages(android_support);",
            "CREATE INDEX IF NOT EXISTS idx_ios ON packages(ios_support);",
            "CREATE INDEX IF NOT EXISTS idx_source ON packages(source);",
            "CREATE INDEX IF NOT EXISTS idx_dep_package ON dependencies(package_name);",
            "CREATE INDEX IF NOT EXISTS idx_dep_dependency ON dependencies(dependency_name);"
        ]
        
        for index in indexes {
            try execute(sql: index)
        }
    }
    
    /// Inserts a package and its dependencies
    func insertPackage(_ package: PackageResult) throws {
        let insertSQL = """
        INSERT OR REPLACE INTO packages (
            name, downloads, android_support, ios_support, source, category,
            android_version, ios_version, latest_version, dependency_status
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteError.prepare(message: String(cString: sqlite3_errmsg(db)))
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        // Bind values
        sqlite3_bind_text(statement, 1, (package.name as NSString).utf8String, -1, nil)
        sqlite3_bind_int64(statement, 2, Int64(package.numberOfDownloads))
        sqlite3_bind_int(statement, 3, Int32(package.androidSupport.rawValue))
        sqlite3_bind_int(statement, 4, Int32(package.iosSupport.rawValue))
        sqlite3_bind_int(statement, 5, Int32(package.source.rawValue))
        sqlite3_bind_int(statement, 6, Int32(package.category.rawValue))
        
        if let androidVersion = package.androidVersion {
            sqlite3_bind_text(statement, 7, (androidVersion as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(statement, 7)
        }
        
        if let iosVersion = package.iosVersion {
            sqlite3_bind_text(statement, 8, (iosVersion as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(statement, 8)
        }
        
        if let latestVersion = package.latestVersion {
            sqlite3_bind_text(statement, 9, (latestVersion as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(statement, 9)
        }
        
        sqlite3_bind_int(statement, 10, Int32(package.dependencyStatus.rawValue))
        
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteError.step(message: String(cString: sqlite3_errmsg(db)))
        }
        
        // Insert dependencies
        if !package.dependencies.isEmpty {
            try insertDependencies(packageName: package.name, dependencies: Array(package.dependencies))
        }
    }
    
    /// Inserts dependencies for a package
    private func insertDependencies(packageName: String, dependencies: [PackageResult]) throws {
        let insertSQL = "INSERT OR IGNORE INTO dependencies (package_name, dependency_name) VALUES (?, ?);"
        
        var statement: OpaquePointer?
        
        guard sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteError.prepare(message: String(cString: sqlite3_errmsg(db)))
        }
        
        defer {
            sqlite3_finalize(statement)
        }
        
        for dependency in dependencies {
            sqlite3_reset(statement)
            sqlite3_bind_text(statement, 1, (packageName as NSString).utf8String, -1, nil)
            sqlite3_bind_text(statement, 2, (dependency.name as NSString).utf8String, -1, nil)
            
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw SQLiteError.step(message: String(cString: sqlite3_errmsg(db)))
            }
        }
    }
    
    /// Executes a SQL statement
    private func execute(sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        
        guard sqlite3_exec(db, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(errorMessage)
            throw SQLiteError.execute(message: message)
        }
    }
}

/// SQLite error types
enum SQLiteError: Error, CustomStringConvertible {
    case openDatabase(message: String)
    case prepare(message: String)
    case step(message: String)
    case execute(message: String)
    
    var description: String {
        switch self {
        case .openDatabase(let message):
            return "Failed to open database: \(message)"
        case .prepare(let message):
            return "Failed to prepare statement: \(message)"
        case .step(let message):
            return "Failed to execute statement: \(message)"
        case .execute(let message):
            return "Failed to execute SQL: \(message)"
        }
    }
}
