import SwiftUI
import WebKit
import Combine

enum EPUBProviderError: LocalizedError {
    case fileMissing
    case unzipFailed(Error)
    case emptySpine
    case parseError(Error)

    var errorDescription: String? {
        switch self {
        case .fileMissing:         return "EPUB file is missing. It may have been deleted."
        case .unzipFailed(let e): return "Could not extract EPUB: \(e.localizedDescription)"
        case .emptySpine:          return "EPUB has no readable content."
        case .parseError(let e):  return "EPUB structure is invalid: \(e.localizedDescription)"
        }
    }
}

final class EPUBProvider: ContentProvider {
    @Published var totalUnits: Int = 0
    @Published var currentUnit: Int = 0
    @Published var highlightWordIndex: Int? = nil
    var onRenderFailure: (() -> Void)?
    var onRenderSuccess: (() -> Void)?

    private let book: Book
    private var spineItems: [EPUBSpineItem] = []
    private var textCache: [Int: String] = [:]

    init(book: Book) {
        self.book = book
    }

    func load() async throws {
        guard FileManager.default.fileExists(atPath: book.fileURL.path) else {
            RecoveryLogger.log(.fileMissing(bookID: book.id, path: book.fileURL.path))
            throw EPUBProviderError.fileMissing
        }

        let unzipDir: URL
        do { unzipDir = try Self.unzipDirectory(for: book) } catch {
            throw EPUBProviderError.unzipFailed(error)
        }

        purgeStaleCacheIfNeeded(unzipDir: unzipDir)

        let manifest: EPUBManifest
        do {
            manifest = try EPUBParser.parse(epubURL: book.fileURL, into: unzipDir)
        } catch {
            RecoveryLogger.log(.providerLoadFailed(bookID: book.id, format: "EPUB",
                                                    error: error.localizedDescription))
            throw EPUBProviderError.parseError(error)
        }

        guard !manifest.spineItems.isEmpty else {
            RecoveryLogger.log(.providerLoadFailed(bookID: book.id, format: "EPUB",
                                                    error: "spine empty"))
            throw EPUBProviderError.emptySpine
        }

        await MainActor.run {
            self.spineItems = manifest.spineItems
            self.totalUnits = manifest.spineItems.count
            self.currentUnit = unitFrom(progress: book.readingPosition)
        }
    }

    func go(to unit: Int) {
        currentUnit = max(0, min(unit, totalUnits - 1))
        highlightWordIndex = nil  // clear stale highlight on navigation
    }

    func setHighlightIndex(_ index: Int?) {
        highlightWordIndex = index
    }

    func currentUnitText() -> String? {
        if let cached = textCache[currentUnit] { return cached }
        guard currentUnit < spineItems.count else { return nil }
        let html = (try? String(contentsOfFile: spineItems[currentUnit].href,
                                encoding: .utf8)) ?? ""
        let text = html.strippingHTML()
        guard !text.isEmpty else { return nil }
        textCache[currentUnit] = text
        return text
    }

    func renderView(settings: ReadingSettings) -> AnyView {
        guard currentUnit < spineItems.count else {
            return AnyView(Color(settings.theme.background))
        }
        let item = spineItems[currentUnit]
        return AnyView(
            EPUBChapterView(
                filePath: item.href,
                settings: settings,
                highlightWordIndex: highlightWordIndex,
                onFailure: onRenderFailure,
                onSuccess: onRenderSuccess
            )
            .id(item.id)
        )
    }

    // MARK: - Cache staleness

    private func purgeStaleCacheIfNeeded(unzipDir: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: unzipDir.path) else { return }
        let sourceDate = (try? fm.attributesOfItem(atPath: book.fileURL.path))?[.modificationDate] as? Date ?? .distantPast
        let cacheDate  = (try? fm.attributesOfItem(atPath: unzipDir.path))?[.modificationDate]  as? Date ?? .distantPast
        if sourceDate > cacheDate {
            RecoveryLogger.log(.epubCacheStale(bookID: book.id))
            try? fm.removeItem(at: unzipDir)
        }
    }

    static func unzipDirectory(for book: Book) throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        return support
            .appendingPathComponent("epub_cache")
            .appendingPathComponent(book.id.uuidString)
    }
}

// MARK: - WKWebView chapter renderer

struct EPUBChapterView: UIViewRepresentable {
    let filePath: String
    let settings: ReadingSettings
    let highlightWordIndex: Int?
    let onFailure: (() -> Void)?
    let onSuccess: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onFailure: onFailure, onSuccess: onSuccess)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = true
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = UIColor(settings.theme.background)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onFailure = onFailure
        context.coordinator.onSuccess = onSuccess

        guard FileManager.default.fileExists(atPath: filePath) else {
            onFailure?()
            return
        }

        let fileURL = URL(fileURLWithPath: filePath)
        guard let rawHTML = try? String(contentsOf: fileURL, encoding: .utf8) else {
            onFailure?()
            return
        }

        // Reload HTML only when the file path changes; highlight updates are
        // delivered via JS without reloading the page.
        if context.coordinator.loadedPath != filePath {
            context.coordinator.loadedPath = filePath
            context.coordinator.lastHighlightIndex = nil
            let styledHTML = injectCSS(rawHTML)
            webView.loadHTMLString(styledHTML, baseURL: fileURL.deletingLastPathComponent())
            webView.scrollView.backgroundColor = UIColor(settings.theme.background)
        }

        // Deliver highlight update whenever the index changes
        if context.coordinator.lastHighlightIndex != highlightWordIndex {
            context.coordinator.lastHighlightIndex = highlightWordIndex
            let idx = highlightWordIndex ?? -1
            webView.evaluateJavaScript("ttsHighlight(\(idx))", completionHandler: nil)
        }
    }

    // MARK: - CSS injection

    private func injectCSS(_ html: String) -> String {
        let css = """
        <style>
        :root { color-scheme: \(settings.theme == .dark ? "dark" : "light"); }
        body {
            background-color: \(settings.theme.background.hexString);
            color: \(settings.theme.foreground.hexString);
            font-size: \(settings.fontSize.cssValue);
            margin: 2em \(settings.margin.cssValue);
            line-height: 1.7;
            font-family: -apple-system, Georgia, serif;
            word-break: break-word;
        }
        img { max-width: 100%; height: auto; }
        a   { color: inherit; }
        /* TTS word highlight */
        .tts-w { display: inline; }
        .tts-w.tts-hi {
            background-color: rgba(255, 220, 50, 0.45);
            border-radius: 3px;
            padding: 0 1px;
            transition: background-color 0.05s ease;
        }
        </style>
        """
        if let range = html.range(of: "<head>", options: .caseInsensitive) {
            var result = html
            result.insert(contentsOf: css, at: range.upperBound)
            return result
        }
        return css + html
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate {
        var onFailure: (() -> Void)?
        var onSuccess: (() -> Void)?
        var loadedPath: String? = nil
        var lastHighlightIndex: Int? = -2   // sentinel so first real update always fires
        private var failureFired = false

        init(onFailure: (() -> Void)?, onSuccess: (() -> Void)?) {
            self.onFailure = onFailure
            self.onSuccess = onSuccess
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            failureFired = false
            injectWordWrapJS(in: webView)
            validateContent(in: webView)
        }

        // Inject word-wrapping + highlight JS after every page load.
        // The span indices exactly match the word-split order in AudioReaderService
        // because both use the same whitespace-tokenisation logic.
        private func injectWordWrapJS(in webView: WKWebView) {
            let js = """
            (function() {
                if (window._ttsWrapped) return;
                window._ttsWrapped = true;
                var idx = 0;
                function wrap(node) {
                    if (node.nodeType === 3) {
                        var text = node.textContent;
                        if (!text.trim()) return;
                        var parts = text.split(/(\\s+)/);
                        var frag = document.createDocumentFragment();
                        for (var i = 0; i < parts.length; i++) {
                            if (parts[i].match(/\\S/)) {
                                var span = document.createElement('span');
                                span.className = 'tts-w';
                                span.setAttribute('data-i', idx++);
                                span.textContent = parts[i];
                                frag.appendChild(span);
                            } else {
                                frag.appendChild(document.createTextNode(parts[i]));
                            }
                        }
                        node.parentNode.replaceChild(frag, node);
                    } else if (node.nodeType === 1) {
                        var tag = (node.tagName || '').toUpperCase();
                        if (tag === 'SCRIPT' || tag === 'STYLE') return;
                        Array.from(node.childNodes).forEach(wrap);
                    }
                }
                if (document.body) wrap(document.body);
            })();

            function ttsHighlight(idx) {
                var prev = document.querySelector('.tts-hi');
                if (prev) prev.classList.remove('tts-hi');
                if (idx < 0) return;
                var el = document.querySelector('.tts-w[data-i="' + idx + '"]');
                if (el) {
                    el.classList.add('tts-hi');
                    el.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
                }
            }
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        private func validateContent(in webView: WKWebView) {
            let js = """
            (function() {
                var b = document.body;
                if (!b) return false;
                return b.innerText.trim().length > 0
                    || b.scrollHeight > 50
                    || document.images.length > 0;
            })()
            """
            webView.evaluateJavaScript(js) { [weak self] result, _ in
                guard let self else { return }
                let ok = (result as? Bool) == true
                DispatchQueue.main.async {
                    if ok { self.onSuccess?() } else { self.fireFailureOnce() }
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            let nsErr = error as NSError
            guard nsErr.code != NSURLErrorCancelled else { return }
            fireFailureOnce()
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
            let nsErr = error as NSError
            guard nsErr.code != NSURLErrorCancelled else { return }
            fireFailureOnce()
        }

        private func fireFailureOnce() {
            guard !failureFired else { return }
            failureFired = true
            DispatchQueue.main.async { self.onFailure?() }
        }
    }
}

private extension Color {
    var hexString: String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r*255), Int(g*255), Int(b*255))
    }
}
