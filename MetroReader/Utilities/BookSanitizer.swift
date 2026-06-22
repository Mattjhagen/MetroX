import Foundation
import SwiftData

/// Run on every Book fetched from SwiftData before it reaches any view or provider.
/// Mutates in-place and logs all repairs so nothing silently propagates bad state.
enum BookSanitizer {

    @discardableResult
    static func sanitize(_ book: Book, context: ModelContext) -> SanitizeResult {
        var repairs: [String] = []

        // 1. NaN / infinity guard — SwiftData can deserialise corrupt doubles
        if book.readingPosition.isNaN || book.readingPosition.isInfinite {
            RecoveryLogger.log(.progressClamped(bookID: book.id, from: book.readingPosition, to: 0))
            book.readingPosition = 0
            repairs.append("progress-nan")
        }

        // 2. Out-of-range clamp (includes values slightly above 1.0 from floating-point drift)
        let clamped = max(0.0, min(1.0, book.readingPosition))
        if clamped != book.readingPosition {
            RecoveryLogger.log(.progressClamped(bookID: book.id, from: book.readingPosition, to: clamped))
            book.readingPosition = clamped
            repairs.append("progress-clamp")
        }

        // 3. File existence — path may be valid URL but file deleted by OS or user
        if !FileManager.default.fileExists(atPath: book.fileURL.path) {
            RecoveryLogger.log(.fileMissing(bookID: book.id, path: book.fileURL.path))
            repairs.append("file-missing")
            // Return early — further checks are irrelevant without the file
            if !repairs.isEmpty { try? context.save() }
            return SanitizeResult(repairs: repairs, isFileAccessible: false)
        }

        // 4. Empty title fallback
        if book.title.trimmingCharacters(in: .whitespaces).isEmpty {
            book.title = book.fileURL.deletingPathExtension().lastPathComponent
            repairs.append("title-empty")
        }

        if !repairs.isEmpty { try? context.save() }
        return SanitizeResult(repairs: repairs, isFileAccessible: true)
    }

    struct SanitizeResult {
        let repairs: [String]
        let isFileAccessible: Bool
        var wasClean: Bool { repairs.isEmpty }
    }
}
