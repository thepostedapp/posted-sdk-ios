import Foundation
import os.log
#if canImport(os)
import os
#endif

enum PostedLogger {
    private static let subsystem = "com.postedapp.posted"

    private enum Level {
        case debug
        case warn
        case error
    }

    static func debug(_ tag: String, _ message: String) {
        log(tag: tag, level: .debug, message: message)
    }

    static func warn(_ tag: String, _ message: String) {
        log(tag: tag, level: .warn, message: message)
    }

    static func error(_ tag: String, _ message: String, error: Error? = nil) {
        let formattedMessage: String
        if let error {
            formattedMessage = "\(message) \(error.localizedDescription)"
        } else {
            formattedMessage = message
        }

        log(tag: tag, level: .error, message: formattedMessage)
    }

    private static func log(tag: String, level: Level, message: String) {
        if #available(iOS 14.0, *) {
            let logger = Logger(subsystem: subsystem, category: tag)
            switch level {
            case .debug:
                logger.log(level: .debug, "\(message, privacy: .public)")
            case .warn:
                logger.log(level: .default, "\(message, privacy: .public)")
            case .error:
                logger.log(level: .error, "\(message, privacy: .public)")
            }
            return
        }

        let osLog = OSLog(subsystem: subsystem, category: tag)
        let logType: OSLogType
        switch level {
        case .debug:
            logType = .debug
        case .warn:
            logType = .default
        case .error:
            logType = .error
        }

        os_log("%{public}@", log: osLog, type: logType, message)
    }
}
