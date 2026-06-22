# MetroX

A distraction-free PDF and EPUB reader for iOS and macOS, built with SwiftUI. Inspired by the flat, typographic aesthetic of Windows Phone's Metro design language.

![MetroX App Icon](MetroReader/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png)

---

## Features

### Reading
- **PDF and EPUB support** — import any PDF or EPUB file from Files, Mail, or any share sheet
- **Swipe navigation** — swipe left/right to advance or go back; velocity-aware so a quick flick commits even on a short drag
- **Tap zones** — tap the left third to go back, right third to advance, center to toggle the chrome
- **Kindle-style animation** — pages slide and fade on every turn, giving a physical sense of motion without a fake page curl
- **Reading progress** — slider and percentage/page counter in the bottom chrome bar
- **Resume on launch** — automatically re-opens the last book you were reading (within 72 hours, less than 95% complete)

### ElevenLabs Text-to-Speech
- **Read-aloud mode** — tap the play button in the reader toolbar to synthesize and play the current page or chapter
- **Four voices** — Rachel (calm), Bella (warm), Adam (deep), Daniel (authoritative)
- **Audio caching** — synthesized audio is saved to disk; re-reading a cached page plays instantly with no API call
- **Debounced synthesis** — rapid page turns cancel and restart the 400ms synthesis window, preventing API storms
- **Auto-advance** — when a chunk finishes playing, the reader automatically flips to the next page and begins reading it
- **Audio follows reading** — optional mode where every manual page turn also auto-starts TTS for the new page
- **Word-level highlighting** — optional mode that highlights each word in the EPUB as it is spoken, scrolling the view to keep the active word visible
- **Continuous playback** — audio runs uninterrupted across pages without needing to tap play again

### Reliability
- **Six-layer pipeline** — every book passes through Identity → Integrity → Sanitization → Load → Runtime → Exit before rendering
- **Corruption recovery** — NaN/infinite reading positions are clamped on every fetch; missing files are caught before any provider is created
- **Render failure detection** — EPUB chapters are validated with a JS content probe after load; PDF pages are checked structurally; blank renders exit cleanly within 500ms
- **Hard-exit contract** — a single `forceExitToLibrary()` path tears down all state and returns to the library; nothing can get stuck in a dead reader state
- **Import deduplication** — re-importing the same file (matched by filename + byte count) is silently skipped

### Appearance
- **Three themes** — Light, Dark, Sepia
- **Font size control** — Small, Medium, Large, XL
- **Margin control** — Narrow, Normal, Wide
- **Status bar auto-hides** when chrome is hidden

---

## Requirements

| | Minimum |
|---|---|
| iOS | 17.0 |
| macOS | via Mac Catalyst (Designed for iPhone/iPad) |
| Xcode | 15+ |
| Swift | 5.9 |

---

## Getting Started

### 1. Clone

```bash
git clone git@github.com:Mattjhagen/MetroX.git
cd MetroX
```

### 2. Generate the Xcode project

The project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) so the `.xcodeproj` is reproducible from `project.yml`.

```bash
brew install xcodegen   # first time only
xcodegen generate
```

### 3. Open and run

```bash
open MetroReader.xcodeproj
```

Select your device or simulator and hit **Run**. No additional configuration is required to build and read books.

### 4. Enable TTS (optional)

1. Open a book → tap the center of the screen to show chrome → tap the **Aₐ** settings button
2. Scroll to **ElevenLabs TTS** and paste your API key
3. A **▶** play button appears in the top toolbar
4. Optionally enable **Audio follows reading** and **Highlight while reading**

Get an API key at [elevenlabs.io](https://elevenlabs.io).

---

## Project Structure

```
MetroReader/
├── MetroReaderApp.swift          # App entry, RootView, auto-resume logic
├── Models/
│   └── Book.swift                # SwiftData model (id, title, fileURL, readingPosition, …)
├── Providers/
│   ├── ContentProvider.swift     # Protocol + AnyContentProvider type-eraser + factory
│   ├── EPUBProvider.swift        # ZIPFoundation unzip → EPUBParser → WKWebView renderer
│   └── PDFProvider.swift         # PDFKit renderer with structural content probe
├── Services/
│   ├── ElevenLabsService.swift   # API calls, word-timing parsing, disk cache
│   └── AudioReaderService.swift  # Playback, debounce, 50ms highlight timer
├── Settings/
│   └── ReadingSettings.swift     # Theme, font size, margin — persisted via AppStorage
├── Utilities/
│   ├── BookValidation.swift      # isReadable / isResumeEligible + BookIdentity (import dedup)
│   ├── BookSanitizer.swift       # Clamps bad progress values on every SwiftData fetch
│   ├── EPUBParser.swift          # SAX XML parser: container.xml → OPF → spine items
│   ├── HTMLStripper.swift        # Regex HTML → plain text for TTS extraction
│   └── RecoveryLogger.swift      # OSLog sink for all recovery events (visible in Console.app)
├── ViewModels/
│   ├── ReaderViewModel.swift     # Load, navigation, 500ms render-failure debounce, hard exit
│   └── LibraryViewModel.swift    # Import, sanitize, sort, dedup
└── Views/
    ├── LibraryView.swift         # Metro tile grid
    ├── BookTileView.swift        # Single tile (deterministic color from title hash)
    ├── ReaderContainerView.swift # Gesture layer, animation, audio wiring, chrome
    └── SettingsSheet.swift       # Theme/font/margin + ElevenLabs configuration
```

---

## Architecture: Six-Layer Reliability Pipeline

Every book travels through six sequential layers before content is ever rendered.

```
┌─────────────────────────────────────────────────────────┐
│  1. Identity      BookIdentity.token(filename, bytes)   │  dedup on import
│  2. Integrity     BookValidation.isReadable / isResume  │  single source of truth
│  3. Sanitization  BookSanitizer — runs on every fetch   │  clamp NaN/corrupt progress
│  4. Load          ContentProviderFactory + providers    │  typed throws, nil on failure
│  5. Runtime       ReaderViewModel debounce + callbacks  │  500ms render-failure window
│  6. Exit          forceExitToLibrary(reason:)           │  one guaranteed escape hatch
└─────────────────────────────────────────────────────────┘
```

The invariant: **the library is always the safe root state**. Any failure at any layer ends up there.

---

## Content Validity Probes

"Load succeeded" ≠ "content is usable." Both providers validate the rendered output, not just the load pipeline.

**EPUB** (runs after `WKWebView.didFinish`):
```javascript
body.innerText.trim().length > 0   // text chapters
|| body.scrollHeight > 50          // image chapters in flow layout
|| document.images.length > 0      // fixed/absolute-positioned image chapters
```

**PDF** (runs in `PDFKitPageRepresentable.updateUIView`):
```swift
page.pageRef != nil            // CGPDFPage exists — real content stream
page.numberOfCharacters >= 0   // liveness check; 0 is valid for scanned pages
// mediaBox intentionally NOT used — false negatives on scanner PDFs
```

---

## TTS Architecture

```
User taps ▶
    │
    ▼
AudioReaderService.toggle()
    │  400ms debounce (cancels on rapid turns)
    ▼
ElevenLabsService.synthesize[WithTimings]()
    │  checks disk cache first
    │  POST /v1/text-to-speech/{voice_id}[/with-timestamps]
    ▼
AVAudioPlayer.play()
    │
    ├── 50ms Timer → currentWordIndex → provider.setHighlightIndex()
    │       └── WKWebView evaluateJavaScript("ttsHighlight(N)")
    │
    └── audioPlayerDidFinishPlaying
            └── onUnitFinished → triggerPageTurn(forward: true)
                    └── 350ms delay → audio.play(nextUnit)
```

Audio always follows reading, never the reverse. The reader VM is the single source of truth for position; `AudioReaderService` never modifies it.

---

## Dependencies

| Package | Purpose |
|---|---|
| [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) | EPUB unzipping (SPM) |

No other third-party dependencies. PDFKit, WebKit, AVFoundation, and SwiftData are all system frameworks.

---

## License

MIT
