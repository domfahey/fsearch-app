import os

/// Unified logging. Fixed strings and enum states are public; paths, queries
/// and file names must be `privacy: .private`. Never log per keystroke.
enum Log {
    static let subsystem = "com.domfahey.fsearch"
    static let daemon = Logger(subsystem: subsystem, category: "daemon")
    static let onboarding = Logger(subsystem: subsystem, category: "onboarding")
    static let actions = Logger(subsystem: subsystem, category: "actions")
    static let debug = Logger(subsystem: subsystem, category: "debug")
}
