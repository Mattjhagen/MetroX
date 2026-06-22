import Foundation

// MARK: - Runtime validity (file system + model state)
//
// Answers: "can this book be opened right now?"
// Evolves with: session rules, progress semantics, OS file guarantees.

enum BookValidation {

    /// File is present on disk and progress value is numerically sound.
    static func isReadable(_ book: Book) -> Bool {
        guard !book.readingPosition.isNaN,
              !book.readingPosition.isInfinite
        else { return false }
        return FileManager.default.fileExists(atPath: book.fileURL.path)
    }

    /// Book is in-progress, not finished, file is accessible, and opened within 72h.
    static func isResumeEligible(_ book: Book) -> Bool {
        guard isReadable(book) else { return false }
        guard book.readingPosition > 0, !book.isCompleted else { return false }
        guard let last = book.lastOpenedDate else { return false }
        return Date().timeIntervalSince(last) < 72 * 3600
    }
}

// MARK: - Import identity (deduplication)
//
// Answers: "have we already imported this file?"
// Evolves independently: sync across devices, edition management,
// intentional re-import workflows — none of that touches runtime validity above.

enum BookIdentity {

    /// Stable token derived from (filename, byte-count).
    /// Cheap — no file read — catches the common import noise cases:
    ///  - same file imported from different source folders   → same token
    ///  - renamed file with different content (size differs) → different token
    ///  - different file that happens to share a name        → different token (size differs)
    static func token(for url: URL) -> ImportToken? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int
        else { return nil }
        return ImportToken(filename: url.lastPathComponent, byteCount: size)
    }

    static func token(for book: Book) -> ImportToken? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: book.fileURL.path),
              let size = attrs[.size] as? Int
        else { return nil }
        return ImportToken(filename: book.fileURL.lastPathComponent, byteCount: size)
    }

    struct ImportToken: Equatable {
        let filename: String
        let byteCount: Int
    }
}
