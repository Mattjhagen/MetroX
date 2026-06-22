import Foundation
import OSLog

/// Central recovery event sink. All sanitization and fallback code logs here.
/// Entries persist across runs so crashes are diagnosable in Console.app.
enum RecoveryLogger {
    private static let logger = Logger(subsystem: "com.metroreader.app", category: "recovery")

    enum Event {
        case progressClamped(bookID: UUID, from: Double, to: Double)
        case fileMissing(bookID: UUID, path: String)
        case providerLoadFailed(bookID: UUID, format: String, error: String)
        case duplicateImportSkipped(filename: String)
        case autoResumeBlocked(bookID: UUID, reason: String)
        case epubCacheStale(bookID: UUID)
        case pdfPageCountZero(bookID: UUID)
        case positionResetOnCompletion(bookID: UUID)
    }

    static func log(_ event: Event) {
        switch event {
        case .progressClamped(let id, let from, let to):
            logger.warning("[\(id)] progress clamped \(from, format: .fixed(precision: 4)) → \(to, format: .fixed(precision: 4))")
        case .fileMissing(let id, let path):
            logger.error("[\(id)] file missing at \(path)")
        case .providerLoadFailed(let id, let fmt, let err):
            logger.error("[\(id)] \(fmt) provider failed: \(err)")
        case .duplicateImportSkipped(let name):
            logger.info("duplicate import skipped: \(name)")
        case .autoResumeBlocked(let id, let reason):
            logger.warning("[\(id)] auto-resume blocked: \(reason)")
        case .epubCacheStale(let id):
            logger.info("[\(id)] stale epub cache removed, will re-unzip")
        case .pdfPageCountZero(let id):
            logger.error("[\(id)] PDF opened with 0 pages — treating as corrupt")
        case .positionResetOnCompletion(let id):
            logger.info("[\(id)] position reset because book was re-opened after completion")
        }
    }
}
