import OSLog

extension Logger {
    private static let subsystem = "com.mcfinder.app"

    static let database = Logger(subsystem: subsystem, category: "DatabaseManager")
    static let index = Logger(subsystem: subsystem, category: "IndexManager")
    static let search = Logger(subsystem: subsystem, category: "SearchEngine")
    static let fsEvents = Logger(subsystem: subsystem, category: "FSEventsMonitor")
    static let hotkey = Logger(subsystem: subsystem, category: "HotkeyManager")
    static let bookmark = Logger(subsystem: subsystem, category: "BookmarkManager")
    static let app = Logger(subsystem: subsystem, category: "AppDelegate")
}
