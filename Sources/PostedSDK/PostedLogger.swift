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
        case signal
    }

#if DEBUG
    // Test-only hook — nil in production. Set in tests to spy on warn calls.
    static var _warnSink: ((String, String) -> Void)?
    // Test-only hook — nil in production. Set in tests to spy on signal() calls.
    static var _signalSink: ((String, String) -> Void)?
#endif

    static func debug(_ tag: String, _ message: String) {
        log(tag: tag, level: .debug, message: message)
    }

    static func warn(_ tag: String, _ message: String) {
#if DEBUG
        _warnSink?(tag, message)
#endif
        log(tag: tag, level: .warn, message: message)
    }

    /// Emits a structured, queryable signal for a discrete occurrence (POS-246) — distinct from
    /// the prose `debug`/`warn`/`error` levels so it can be counted/filtered independently (e.g.
    /// how often a bounded gate times out in the field). `name` must be a static, privacy-safe
    /// identifier: no clipboard contents, no PII, no other user data.
    static func signal(_ tag: String, _ name: String) {
#if DEBUG
        _signalSink?(tag, name)
#endif
        log(tag: tag, level: .signal, message: "[Posted:SIGNAL] \(name)")
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
            case .signal:
                logger.log(level: .info, "\(message, privacy: .public)")
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
        case .signal:
            logType = .info
        }

        os_log("%{public}@", log: osLog, type: logType, message)
    }
}
