import SwiftUI
import PDFKit
import Combine

enum PDFProviderError: LocalizedError {
    case unreadable
    case noPages

    var errorDescription: String? {
        switch self {
        case .unreadable: return "PDF file could not be opened. It may be corrupt or password-protected."
        case .noPages:    return "PDF opened with no readable pages."
        }
    }
}

final class PDFProvider: ContentProvider {
    @Published var totalUnits: Int = 0
    @Published var currentUnit: Int = 0
    var onRenderFailure: (() -> Void)?
    var onRenderSuccess: (() -> Void)?

    private let book: Book
    private var pdfDocument: PDFDocument?
    private var textCache: [Int: String] = [:]

    init(book: Book) {
        self.book = book
    }

    func load() async throws {
        guard FileManager.default.fileExists(atPath: book.fileURL.path) else {
            RecoveryLogger.log(.fileMissing(bookID: book.id, path: book.fileURL.path))
            throw PDFProviderError.unreadable
        }

        guard let doc = PDFDocument(url: book.fileURL) else {
            RecoveryLogger.log(.providerLoadFailed(bookID: book.id, format: "PDF", error: "PDFDocument returned nil"))
            throw PDFProviderError.unreadable
        }

        guard doc.pageCount > 0 else {
            RecoveryLogger.log(.pdfPageCountZero(bookID: book.id))
            throw PDFProviderError.noPages
        }

        await MainActor.run {
            self.pdfDocument = doc
            self.totalUnits = doc.pageCount
            self.currentUnit = unitFrom(progress: book.readingPosition)
        }
    }

    func go(to unit: Int) {
        currentUnit = max(0, min(unit, totalUnits - 1))
    }

    func currentUnitText() -> String? {
        if let cached = textCache[currentUnit] { return cached }
        let text = pdfDocument?.page(at: currentUnit)?.string
        if let text { textCache[currentUnit] = text }
        return text
    }

    func setHighlightIndex(_ index: Int?) { /* PDF highlighting not supported */ }

    func renderView(settings: ReadingSettings) -> AnyView {
        AnyView(PDFPageView(
            document: pdfDocument,
            pageIndex: currentUnit,
            settings: settings,
            onFailure: onRenderFailure,
            onSuccess: onRenderSuccess
        ))
    }
}

struct PDFPageView: View {
    let document: PDFDocument?
    let pageIndex: Int
    let settings: ReadingSettings
    let onFailure: (() -> Void)?
    let onSuccess: (() -> Void)?

    var body: some View {
        if let document, let page = document.page(at: pageIndex) {
            PDFKitPageRepresentable(page: page, settings: settings, onSuccess: onSuccess, onFailure: onFailure)
                .ignoresSafeArea()
        } else {
            // Document loaded (pageCount > 0 verified) but this page is unrenderable.
            Color(settings.theme.background)
                .ignoresSafeArea()
                .task { onFailure?() }
        }
    }
}

struct PDFKitPageRepresentable: UIViewRepresentable {
    let page: PDFPage
    let settings: ReadingSettings
    let onSuccess: (() -> Void)?
    let onFailure: (() -> Void)?

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePage
        view.autoScales = true
        view.displayDirection = .horizontal
        view.usePageViewController(true, withViewOptions: nil)
        view.backgroundColor = UIColor(settings.theme.background)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if let doc = page.document, view.document !== doc {
            view.document = doc
        }
        if view.currentPage !== page {
            view.go(to: page)
        }
        view.backgroundColor = UIColor(settings.theme.background)

        // Content probe: two independent structural checks.
        //
        // pageRef != nil  — confirms a backing CGPDFPage exists. This is the
        //   primary signal: nil means PDFKit created a page shell with no content
        //   stream (corrupt, partially downloaded, or format-mangled file).
        //
        // numberOfCharacters >= 0  — cheap read that materialises the page's
        //   character map without rendering. Returns 0 for image-only/scanned pages
        //   (valid) and never throws — so it's purely a liveness signal, not a
        //   content-type gate. mediaBox is intentionally NOT used: some valid PDFs
        //   use zero or deferred geometry via CropBox/ArtBox.
        if page.pageRef != nil && page.numberOfCharacters >= 0 {
            onSuccess?()
        } else {
            onFailure?()
        }
    }
}
