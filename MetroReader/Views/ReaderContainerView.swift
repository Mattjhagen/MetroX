import SwiftUI

struct ReaderContainerView: View {
    let book: Book
    let onClose: () -> Void

    @StateObject private var vm: ReaderViewModel
    @StateObject private var settings = ReadingSettings()
    @StateObject private var audio = AudioReaderService()
    @Environment(\.modelContext) private var modelContext
    @State private var showSettings = false
    @AppStorage("audioFollowsReading")   private var audioFollowsReading   = false
    @AppStorage("ttsHighlightEnabled") private var ttsHighlightEnabled = false

    // Animation state for Kindle-style slide+fade between units
    @State private var slideOffset: CGFloat = 0
    @State private var pageOpacity: Double = 1.0
    // Tracks finger position during a live drag
    @State private var liveOffset: CGFloat = 0

    init(book: Book, onClose: @escaping () -> Void) {
        self.book = book
        self.onClose = onClose
        _vm = StateObject(wrappedValue: ReaderViewModel(book: book, settings: ReadingSettings()))
    }

    var body: some View {
        ZStack {
            settings.theme.background.ignoresSafeArea()

            if vm.isLoaded {
                contentLayer
                tapZoneLayer
                chromeLayer
            } else if let failure = vm.failure {
                failureView(failure)
            } else {
                loadingView
            }
        }
        .statusBarHidden(!vm.showChrome)
        .navigationBarHidden(true)
        .preferredColorScheme(settings.theme.colorScheme)
        .task {
            vm.setContext(modelContext)
            vm.onExitToLibrary = onClose
            await vm.load()
        }
        .onDisappear {
            vm.savePosition()
            audio.stop()
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(settings: settings)
        }
        .onAppear {
            audio.onUnitFinished = {
                triggerPageTurn(forward: true)
                // Animation takes ~0.31s total. Read the new currentUnit after it
                // settles, then auto-play — regardless of audioFollowsReading.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    guard let provider = vm.provider,
                          let text = provider.currentUnitText() else { return }
                    let key = "\(book.id.uuidString)_\(provider.currentUnit)"
                    audio.play(text: text, chunkKey: key)
                }
            }
        }
        .onChange(of: vm.provider?.currentUnit ?? 0) { _, newUnit in
            // When audioFollowsReading is on and audio was playing, auto-start the
            // next chunk. The 400ms debounce in AudioReaderService absorbs rapid turns.
            guard audioFollowsReading, audio.isActive || audio.isPlaying else { return }
            if let text = vm.provider?.currentUnitText() {
                let key = "\(book.id.uuidString)_\(newUnit)"
                audio.play(text: text, chunkKey: key)
            }
        }
        .onChange(of: audio.currentWordIndex) { _, idx in
            guard ttsHighlightEnabled else { return }
            vm.provider?.setHighlightIndex(idx)
        }
        .onChange(of: audio.isPlaying) { _, playing in
            if !playing { vm.provider?.setHighlightIndex(nil) }
        }
    }

    // MARK: - Layers

    private var contentLayer: some View {
        vm.renderView(settings: settings)
            .ignoresSafeArea()
            .offset(x: slideOffset + liveOffset)
            .opacity(pageOpacity)
    }

    private var tapZoneLayer: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: geo.size.width * 0.30)
                    .contentShape(Rectangle())
                    .onTapGesture { triggerPageTurn(forward: false) }

                Color.clear
                    .frame(width: geo.size.width * 0.40)
                    .contentShape(Rectangle())
                    .onTapGesture { vm.toggleChrome() }

                Color.clear
                    .frame(width: geo.size.width * 0.30)
                    .contentShape(Rectangle())
                    .onTapGesture { triggerPageTurn(forward: true) }
            }
            .gesture(
                DragGesture(minimumDistance: 15, coordinateSpace: .local)
                    .onChanged { value in
                        let h = value.translation.width
                        let v = abs(value.translation.height)
                        guard abs(h) > v else { return }
                        // Rubber-band resistance so the page doesn't slide 1:1 with the finger
                        liveOffset = h * 0.35
                    }
                    .onEnded { value in
                        let h = value.translation.width
                        let v = abs(value.translation.height)
                        let predictedH = value.predictedEndTranslation.width

                        guard abs(h) > v else { snapBack(); return }

                        // Commit if displacement OR velocity cross the threshold
                        if h < -50 || predictedH < -150 {
                            triggerPageTurn(forward: true)
                        } else if h > 50 || predictedH > 150 {
                            triggerPageTurn(forward: false)
                        } else {
                            snapBack()
                        }
                    }
            )
        }
    }

    @ViewBuilder
    private var chromeLayer: some View {
        if vm.showChrome {
            VStack {
                HStack {
                    Button {
                        vm.savePosition()
                        onClose()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(settings.theme.foreground)
                            .padding(12)
                            .background(settings.theme.background.opacity(0.85))
                    }

                    Spacer()

                    Text(book.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(settings.theme.foreground)
                        .lineLimit(1)

                    Spacer()

                    if !audio.apiKey.isEmpty {
                        audioButton
                    }

                    Button { showSettings = true } label: {
                        Image(systemName: "textformat.size")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(settings.theme.foreground)
                            .padding(12)
                            .background(settings.theme.background.opacity(0.85))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)
                .background(settings.theme.background.opacity(0.9))

                Spacer()

                VStack(spacing: 6) {
                    if let err = audio.error {
                        Text(err)
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 16)
                            .multilineTextAlignment(.center)
                    }

                    Slider(
                        value: Binding(
                            get: { vm.provider?.progress ?? 0 },
                            set: { vm.seek(to: $0) }
                        ),
                        in: 0...1
                    )
                    .tint(settings.theme.foreground)
                    .padding(.horizontal, 16)

                    Text(vm.progressText)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(settings.theme.foreground.opacity(0.7))
                }
                .padding(.bottom, 24)
                .background(settings.theme.background.opacity(0.9))
            }
            .transition(.opacity)
        }
    }

    private var audioButton: some View {
        Button {
            if let text = vm.provider?.currentUnitText(),
               let unit = vm.provider?.currentUnit {
                let key = "\(book.id.uuidString)_\(unit)"
                audio.toggle(text: text, chunkKey: key)
            }
        } label: {
            Group {
                if audio.isLoading {
                    ProgressView()
                        .tint(settings.theme.foreground)
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(settings.theme.foreground)
                }
            }
            .padding(12)
            .background(settings.theme.background.opacity(0.85))
        }
        .disabled(audio.isLoading)
    }

    private var loadingView: some View {
        ProgressView()
            .tint(settings.theme.foreground)
    }

    private func failureView(_ failure: ReaderFailure) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text(failure.localizedDescription)
                .foregroundStyle(settings.theme.foreground)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Back to Library") { onClose() }
                .foregroundStyle(settings.theme.foreground)
                .padding(.top, 8)
        }
    }

    // MARK: - Animation

    private func triggerPageTurn(forward: Bool) {
        // In audioFollowsReading mode the onChange handler starts the next chunk;
        // only stop here when not in that mode so the transition is clean.
        if audio.isActive && !audioFollowsReading { audio.stop() }

        let screenW = UIScreen.main.bounds.width
        let exitDir: CGFloat = forward ? -1 : 1

        withAnimation(.easeIn(duration: 0.13)) {
            slideOffset = exitDir * screenW * 0.45
            pageOpacity = 0
            liveOffset = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) {
            vm.advance(forward: forward)
            slideOffset = -exitDir * screenW * 0.25

            withAnimation(.easeOut(duration: 0.18)) {
                slideOffset = 0
                pageOpacity = 1
            }
        }
    }

    private func snapBack() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            liveOffset = 0
        }
    }
}
