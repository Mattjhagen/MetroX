import SwiftUI
import Combine
import Foundation

protocol ContentProvider: ObservableObject {
    var totalUnits: Int { get }
    var currentUnit: Int { get set }
    /// Fires when a page renders blank or a resource fails to decode at runtime.
    var onRenderFailure: (() -> Void)? { get set }
    /// Fires when content is confirmed rendered. Cancels any pending failure window.
    var onRenderSuccess: (() -> Void)? { get set }
    func advance(forward: Bool)
    func go(to unit: Int)
    func renderView(settings: ReadingSettings) -> AnyView
    func load() async throws
    /// Plain text for the current unit. Used by AudioReaderService for TTS.
    /// Returns nil for units with no extractable text (image-only pages, etc.).
    func currentUnitText() -> String?
    /// Drives live word highlighting. Pass nil to clear. No-op for PDF.
    func setHighlightIndex(_ index: Int?)
}

extension ContentProvider {
    func advance(forward: Bool) {
        let next = currentUnit + (forward ? 1 : -1)
        go(to: max(0, min(next, totalUnits - 1)))
    }

    var progress: Double {
        guard totalUnits > 1 else { return 0 }
        return Double(currentUnit) / Double(totalUnits - 1)
    }

    func unitFrom(progress: Double) -> Int {
        guard totalUnits > 1 else { return 0 }
        return Int((progress * Double(totalUnits - 1)).rounded())
    }
}

// Factory — returns nil when BookValidation.isReadable fails so callers get
// a clean nil rather than a provider that will immediately throw on load().
enum ContentProviderFactory {
    static func provider(for book: Book) -> AnyContentProvider? {
        guard BookValidation.isReadable(book) else {
            RecoveryLogger.log(.fileMissing(bookID: book.id, path: book.fileURL.path))
            return nil
        }
        switch book.format {
        case .epub: return AnyContentProvider(EPUBProvider(book: book))
        case .pdf:  return AnyContentProvider(PDFProvider(book: book))
        }
    }
}

// Type-erased wrapper
final class AnyContentProvider: ObservableObject {
    private let _totalUnits: () -> Int
    private let _getCurrentUnit: () -> Int
    private let _setCurrentUnit: (Int) -> Void
    private let _advance: (Bool) -> Void
    private let _goTo: (Int) -> Void
    private let _renderView: (ReadingSettings) -> AnyView
    private let _load: () async throws -> Void
    private let _setRenderFailure: (@escaping () -> Void) -> Void
    private let _setRenderSuccess: (@escaping () -> Void) -> Void
    private let _currentUnitText: () -> String?
    private let _setHighlightIndex: (Int?) -> Void
    private var cancellable: AnyCancellable?

    init<P: ContentProvider>(_ provider: P) {
        _totalUnits         = { provider.totalUnits }
        _getCurrentUnit     = { provider.currentUnit }
        _setCurrentUnit     = { provider.currentUnit = $0 }
        _advance            = { provider.advance(forward: $0) }
        _goTo               = { provider.go(to: $0) }
        _renderView         = { provider.renderView(settings: $0) }
        _load               = { try await provider.load() }
        _setRenderFailure   = { provider.onRenderFailure = $0 }
        _setRenderSuccess   = { provider.onRenderSuccess = $0 }
        _currentUnitText    = { provider.currentUnitText() }
        _setHighlightIndex  = { provider.setHighlightIndex($0) }
        cancellable = provider.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    func setRenderFailureCallback(_ cb: @escaping () -> Void) { _setRenderFailure(cb) }
    func setRenderSuccessCallback(_ cb: @escaping () -> Void) { _setRenderSuccess(cb) }

    var totalUnits: Int  { _totalUnits() }
    var currentUnit: Int {
        get { _getCurrentUnit() }
        set { _setCurrentUnit(newValue) }
    }
    var progress: Double {
        guard totalUnits > 1 else { return 0 }
        return Double(currentUnit) / Double(totalUnits - 1)
    }
    func unitFrom(progress: Double) -> Int {
        guard totalUnits > 1 else { return 0 }
        return Int((progress * Double(totalUnits - 1)).rounded())
    }
    func advance(forward: Bool) { _advance(forward) }
    func go(to unit: Int)       { _goTo(unit) }
    func renderView(settings: ReadingSettings) -> AnyView { _renderView(settings) }
    func load() async throws    { try await _load() }
    func currentUnitText() -> String? { _currentUnitText() }
    func setHighlightIndex(_ index: Int?) { _setHighlightIndex(index) }
}
