import SwiftUI
import Combine
import SwiftData

enum ReaderFailure: LocalizedError {
    case fileNotFound
    case providerLoadFailed(String)
    case midStreamFailure(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound:              return "Book file could not be found. It may have been deleted."
        case .providerLoadFailed(let m): return m
        case .midStreamFailure(let m):   return "Reading interrupted: \(m)"
        }
    }
}

@MainActor
final class ReaderViewModel: ObservableObject {
    @Published var isLoaded = false
    @Published var showChrome = false
    @Published var failure: ReaderFailure?

    private(set) var provider: AnyContentProvider?

    let book: Book
    let settings: ReadingSettings

    /// Injected by ReaderContainerView so forceExitToLibrary can trigger navigation
    /// without the VM holding a direct reference to the view hierarchy.
    var onExitToLibrary: (() -> Void)?

    private var saveTask: Task<Void, Never>?
    private var renderFailureTask: Task<Void, Never>?
    private var modelContext: ModelContext?

    init(book: Book, settings: ReadingSettings) {
        self.book = book
        self.settings = settings
    }

    func setContext(_ context: ModelContext) {
        self.modelContext = context
    }

    // MARK: - Load

    func load() async {
        guard BookValidation.isReadable(book) else {
            RecoveryLogger.log(.fileMissing(bookID: book.id, path: book.fileURL.path))
            forceExitToLibrary(reason: .fileNotFound)
            return
        }

        if let ctx = modelContext {
            BookSanitizer.sanitize(book, context: ctx)
        }

        guard let p = ContentProviderFactory.provider(for: book) else {
            forceExitToLibrary(reason: .fileNotFound)
            return
        }

        do {
            try await p.load()
        } catch {
            RecoveryLogger.log(.providerLoadFailed(
                bookID: book.id,
                format: book.format == .epub ? "EPUB" : "PDF",
                error: error.localizedDescription
            ))
            forceExitToLibrary(reason: .providerLoadFailed(error.localizedDescription))
            return
        }

        guard p.totalUnits > 0 else {
            forceExitToLibrary(reason: .providerLoadFailed("File opened with no readable content."))
            return
        }

        // Wire render-failure callback through the debounce window — not directly
        // to forceExitToLibrary. Transient WKWebView states and PDFKit lazy-load
        // delays get 500ms to self-resolve before we treat them as real failures.
        p.setRenderFailureCallback { [weak self] in
            self?.scheduleRenderFailureExit()
        }
        // Wire render-success callback so passive self-healing (WKWebView CSS reflow,
        // late DOM population) cancels the failure window without requiring navigation.
        p.setRenderSuccessCallback { [weak self] in
            self?.cancelRenderFailureWindow()
        }

        self.provider = p
        isLoaded = true
    }

    // MARK: - Hard exit contract

    /// Guaranteed escape hatch. Tears down all reader state then fires
    /// onExitToLibrary. Safe to call from any failure path.
    func forceExitToLibrary(reason: ReaderFailure?) {
        renderFailureTask?.cancel()
        renderFailureTask = nil
        saveTask?.cancel()
        saveTask = nil

        provider = nil
        isLoaded = false

        if let reason {
            RecoveryLogger.log(.providerLoadFailed(
                bookID: book.id,
                format: book.format == .epub ? "EPUB" : "PDF",
                error: reason.localizedDescription
            ))
            failure = reason
        }

        onExitToLibrary?()
    }

    // MARK: - Render-failure debounce

    /// Opens a 500ms confirmation window before treating a render failure as fatal.
    ///
    /// Why: WKWebView fires didFailProvisionalNavigation on slow loads and chapter
    /// transitions. PDFKit may return nil for a page during its own lazy-decode.
    /// These are transient — a real corruption is still broken after 500ms.
    ///
    /// The window is cancelled by any successful navigation (advance/seek), because
    /// a user who can navigate cannot be stuck in a dead reader.
    private func scheduleRenderFailureExit() {
        // Coalesce rapid-fire callbacks from the same bad state
        renderFailureTask?.cancel()
        renderFailureTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            forceExitToLibrary(reason: .midStreamFailure(
                "A page could not be rendered. The file may be partially corrupt."
            ))
        }
    }

    // MARK: - Navigation

    func advance(forward: Bool) {
        // Successful navigation is proof the reader is alive — cancel any pending exit.
        cancelRenderFailureWindow()
        provider?.advance(forward: forward)
        schedulePositionSave()
    }

    func seek(to progress: Double) {
        cancelRenderFailureWindow()
        provider?.go(to: provider?.unitFrom(progress: progress) ?? 0)
        schedulePositionSave()
    }

    func toggleChrome() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showChrome.toggle()
        }
    }

    var progressText: String {
        guard let p = provider, p.totalUnits > 0 else { return "" }
        let pct = Int((p.progress * 100).rounded())
        return "\(pct)%  ·  \(p.currentUnit + 1) of \(p.totalUnits)"
    }

    func renderView(settings: ReadingSettings) -> AnyView {
        provider?.renderView(settings: settings) ?? AnyView(EmptyView())
    }

    // MARK: - Persistence

    private func schedulePositionSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            savePosition()
        }
    }

    func savePosition() {
        guard let p = provider else { return }
        book.readingPosition = p.progress
        book.lastOpenedDate = Date()
        try? modelContext?.save()
    }

    private func cancelRenderFailureWindow() {
        renderFailureTask?.cancel()
        renderFailureTask = nil
    }
}
