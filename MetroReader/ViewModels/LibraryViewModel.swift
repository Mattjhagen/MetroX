import SwiftUI
import SwiftData

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var isImporting = false
    @Published var importError: String?

    @AppStorage("sortOrder") var sortOrderRaw: String = SortOrder.recent.rawValue

    var sortOrder: SortOrder {
        get { SortOrder(rawValue: sortOrderRaw) ?? .recent }
        set { sortOrderRaw = newValue.rawValue }
    }

    // MARK: - Sanitize all books fetched from SwiftData

    /// Call from LibraryView.onAppear. Removes phantom records (file missing) and
    /// repairs any corrupt model state before anything reaches the UI.
    func sanitizeLibrary(books: [Book], context: ModelContext) {
        for book in books {
            let result = BookSanitizer.sanitize(book, context: context)
            if !result.isFileAccessible {
                // Record is orphaned — file gone. Remove it so UI stays clean.
                context.delete(book)
            }
        }
        try? context.save()
    }

    // MARK: - Filtering / sorting

    func filteredBooks(_ books: [Book]) -> [Book] {
        let base = searchText.isEmpty
            ? books
            : books.filter { $0.title.localizedCaseInsensitiveContains(searchText) }

        switch sortOrder {
        case .recent:
            return base.sorted { ($0.lastOpenedDate ?? $0.importedDate) > ($1.lastOpenedDate ?? $1.importedDate) }
        case .oldest:
            return base.sorted { $0.importedDate < $1.importedDate }
        case .unread:
            return base.sorted { lhs, rhs in
                if lhs.readingPosition == 0 && rhs.readingPosition > 0 { return true }
                if lhs.readingPosition > 0 && rhs.readingPosition == 0 { return false }
                return (lhs.lastOpenedDate ?? lhs.importedDate) > (rhs.lastOpenedDate ?? rhs.importedDate)
            }
        }
    }

    func activeBook(from books: [Book]) -> Book? {
        books.first { BookValidation.isResumeEligible($0) }
    }

    // MARK: - Import

    func importBook(url: URL, context: ModelContext, existingBooks: [Book]) throws {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let booksDir = support.appendingPathComponent("books")
        try FileManager.default.createDirectory(at: booksDir, withIntermediateDirectories: true)

        let filename = url.lastPathComponent
        let dest = booksDir.appendingPathComponent(filename)

        // Deduplicate by (filename, byte-count) — catches same file from different
        // folders and prevents filename-only collisions from different files.
        if let incomingToken = BookIdentity.token(for: url),
           existingBooks.contains(where: { BookIdentity.token(for: $0) == incomingToken }) {
            RecoveryLogger.log(.duplicateImportSkipped(filename: filename))
            return
        }

        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: url, to: dest)

        let title = url.deletingPathExtension().lastPathComponent
        let book = Book(title: title, fileURL: dest)
        context.insert(book)
        try context.save()
    }

    // MARK: - Delete

    func deleteBook(_ book: Book, context: ModelContext) {
        try? FileManager.default.removeItem(at: book.fileURL)

        if book.format == .epub,
           let cacheDir = try? EPUBProvider.unzipDirectory(for: book) {
            try? FileManager.default.removeItem(at: cacheDir)
        }
        context.delete(book)
        try? context.save()
    }
}
