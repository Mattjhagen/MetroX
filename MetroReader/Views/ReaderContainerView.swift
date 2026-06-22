import SwiftUI

struct ReaderContainerView: View {
    let book: Book
    let onClose: () -> Void

    @StateObject private var vm: ReaderViewModel
    @StateObject private var settings = ReadingSettings()
    @StateObject private var audio = AudioReaderService()
    @Environment(\.modelContext) private var modelContext
    @State private var showSettings = false
    @State private var showReaderOverlay = false
    @AppStorage("audioFollowsReading")  private var audioFollowsReading = false
    @AppStorage("ttsHighlightEnabled")  private var ttsHighlightEnabled = false

    @State private var slideOffset: CGFloat = 0
    @State private var pageOpacity: Double  = 1.0
    @State private var liveOffset: CGFloat  = 0

    init(book: Book, onClose: @escaping () -> Void) {
        self.book = book
        self.onClose = onClose
        _vm = StateObject(wrappedValue: ReaderViewModel(book: book, settings: ReadingSettings()))
    }

    var body: some View {
        ZStack {
            Metro.background.ignoresSafeArea()

            if vm.isLoaded {
                contentLayer
                tapZoneLayer
                chromeLayer
                if showReaderOverlay { settingsOverlay }
            } else if let failure = vm.failure {
                failureView(failure)
            } else {
                loadingView
            }
        }
        .statusBarHidden(!vm.showChrome)
        .navigationBarHidden(true)
        .preferredColorScheme(.dark)
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    guard let provider = vm.provider,
                          let text = provider.currentUnitText() else { return }
                    let key = "\(book.id.uuidString)_\(provider.currentUnit)"
                    audio.play(text: text, chunkKey: key)
                }
            }
        }
        .onChange(of: vm.provider?.currentUnit ?? 0) { _, newUnit in
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

    // MARK: - Content

    private var contentLayer: some View {
        vm.renderView(settings: settings)
            .ignoresSafeArea()
            .offset(x: slideOffset + liveOffset)
            .opacity(pageOpacity)
    }

    // MARK: - Tap Zones

    private var tapZoneLayer: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: geo.size.width * 0.28)
                    .contentShape(Rectangle())
                    .onTapGesture { triggerPageTurn(forward: false) }

                Color.clear
                    .frame(width: geo.size.width * 0.44)
                    .contentShape(Rectangle())
                    .onTapGesture { vm.toggleChrome() }

                Color.clear
                    .frame(width: geo.size.width * 0.28)
                    .contentShape(Rectangle())
                    .onTapGesture { triggerPageTurn(forward: true) }
            }
            .gesture(
                DragGesture(minimumDistance: 15, coordinateSpace: .local)
                    .onChanged { value in
                        let h = value.translation.width
                        guard abs(h) > abs(value.translation.height) else { return }
                        liveOffset = h * 0.35
                    }
                    .onEnded { value in
                        let h = value.translation.width
                        let predictedH = value.predictedEndTranslation.width
                        guard abs(h) > abs(value.translation.height) else { snapBack(); return }
                        if      h < -50 || predictedH < -150 { triggerPageTurn(forward: true)  }
                        else if h >  50 || predictedH >  150 { triggerPageTurn(forward: false) }
                        else                                   { snapBack() }
                    }
            )
        }
    }

    // MARK: - Metro Chrome

    @ViewBuilder
    private var chromeLayer: some View {
        if vm.showChrome {
            VStack(spacing: 0) {
                // Top bar
                ZStack {
                    Metro.background.opacity(0.92)
                    HStack {
                        Button {
                            vm.savePosition()
                            onClose()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Metro.primary)
                                .frame(width: 44, height: 44)
                        }

                        Spacer()

                        if !audio.apiKey.isEmpty { audioButton }

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showReaderOverlay = true
                                vm.showChrome = false
                            }
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Metro.primary)
                                .frame(width: 44, height: 44)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .frame(height: 52)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Metro.outlineVariant).frame(height: 1)
                }

                // Oversized chapter title header
                HStack(alignment: .firstTextBaseline) {
                    Text(chapterLabel)
                        .font(Metro.labelSm(size: 10))
                        .foregroundStyle(Metro.onSurfaceVariant)
                    Text("—")
                        .font(Metro.displayHero(size: 42))
                        .foregroundStyle(Metro.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, Metro.margin)
                .padding(.top, 6)
                .background(Metro.background.opacity(0.92))

                Spacer()

                // Bottom — position + progress bar + percentage
                bottomBar
            }
            .transition(.opacity.animation(.easeInOut(duration: 0.18)))
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            // TTS error if any
            if let err = audio.error {
                Text(err)
                    .font(Metro.labelSm(size: 11))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, Metro.margin)
                    .padding(.bottom, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Thin full-width progress bar
            GeometryReader { geo in
                Rectangle()
                    .fill(Metro.primary)
                    .frame(width: geo.size.width * (vm.provider?.progress ?? 0))
                    .frame(height: 2)
            }
            .frame(height: 2)

            HStack(spacing: 0) {
                // Position tile — left
                VStack(alignment: .leading, spacing: 4) {
                    Text("POSITION")
                        .font(Metro.labelSm(size: 9))
                        .foregroundStyle(Metro.primary)
                    Text(positionLabel)
                        .font(Metro.tileTitle())
                        .foregroundStyle(Metro.onSurface)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Metro.surfaceContLow)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Metro.primary).frame(width: 3)
                }

                // Scrubber in the middle (hidden in design but kept for usability)
                Slider(
                    value: Binding(
                        get: { vm.provider?.progress ?? 0 },
                        set: { vm.seek(to: $0) }
                    ),
                    in: 0...1
                )
                .tint(Metro.primary)
                .padding(.horizontal, 16)

                // Progress tile — right
                VStack(alignment: .trailing, spacing: 4) {
                    Text("PROGRESS")
                        .font(Metro.labelSm(size: 9))
                        .foregroundStyle(Metro.primary)
                    Text("\(Int((vm.provider?.progress ?? 0) * 100))%")
                        .font(Metro.tileTitle())
                        .foregroundStyle(Metro.onSurface)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(12)
                .background(Metro.surfaceContLow)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(Metro.primary).frame(width: 3)
                }
            }
            .frame(height: 72)
        }
        .background(Metro.background.opacity(0.92))
    }

    // MARK: - Settings Overlay (full-screen Metro)

    private var settingsOverlay: some View {
        ZStack {
            Color.black.opacity(0.96).ignoresSafeArea()

            VStack(alignment: .leading, spacing: Metro.gap) {
                // Header
                HStack {
                    Text("SETTINGS")
                        .font(Metro.headlineLg())
                        .foregroundStyle(Metro.primary)
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showReaderOverlay = false
                            vm.showChrome = true
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Metro.onSurface)
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.horizontal, Metro.margin)
                .padding(.top, 60)

                ScrollView {
                    VStack(spacing: Metro.gap) {
                        // Typography tile
                        settingsTile(label: "TYPOGRAPHY") {
                            VStack(spacing: 0) {
                                Picker("Font Size", selection: Binding(
                                    get: { settings.fontSizeRaw },
                                    set: { settings.fontSizeRaw = $0 }
                                )) {
                                    ForEach(FontSize.allCases, id: \.rawValue) {
                                        Text($0.rawValue).tag($0.rawValue)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .padding(.bottom, 12)

                                Picker("Margin", selection: Binding(
                                    get: { settings.marginRaw },
                                    set: { settings.marginRaw = $0 }
                                )) {
                                    ForEach(Margin.allCases, id: \.rawValue) {
                                        Text($0.rawValue).tag($0.rawValue)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }
                        }

                        // Theme tile
                        settingsTile(label: "DISPLAY") {
                            HStack(spacing: Metro.gap) {
                                ForEach(ReadingTheme.allCases, id: \.rawValue) { theme in
                                    let active = settings.themeRaw == theme.rawValue
                                    Button { settings.themeRaw = theme.rawValue } label: {
                                        Text(theme.rawValue.uppercased())
                                            .font(Metro.labelSm(size: 13))
                                            .foregroundStyle(active ? Metro.background : Metro.onSurface)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 10)
                                            .background(active ? Metro.primary : Metro.surfaceContHigh)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // ElevenLabs tile (if key is set)
                        if !audio.apiKey.isEmpty {
                            settingsTile(label: "ELEVENLABS") {
                                Button { showSettings = true } label: {
                                    HStack {
                                        Text("VOICE & TTS SETTINGS")
                                            .font(Metro.labelSm(size: 13))
                                            .foregroundStyle(Metro.onSurface)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12))
                                            .foregroundStyle(Metro.onSurfaceVariant)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        } else {
                            settingsTile(label: "ELEVENLABS TTS") {
                                Button { showSettings = true } label: {
                                    HStack {
                                        Text("ADD API KEY TO ENABLE AUDIO")
                                            .font(Metro.labelSm(size: 13))
                                            .foregroundStyle(Metro.onSurfaceVariant)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 12))
                                            .foregroundStyle(Metro.onSurfaceVariant)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        // Return to library — wide primary tile
                        Button {
                            vm.savePosition()
                            onClose()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("NAVIGATION")
                                        .font(Metro.labelSm())
                                        .foregroundStyle(Metro.onPrimary.opacity(0.7))
                                    Text("RETURN TO LIBRARY")
                                        .font(Metro.headlineLg(size: 24))
                                        .foregroundStyle(Metro.onPrimary)
                                }
                                Spacer()
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 32, weight: .medium))
                                    .foregroundStyle(Metro.onPrimary)
                            }
                            .padding(20)
                            .frame(maxWidth: .infinity)
                            .background(Metro.primary)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, Metro.margin)
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .transition(.opacity.animation(.easeInOut(duration: 0.2)))
    }

    private func settingsTile<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(label)
                .font(Metro.labelSm())
                .foregroundStyle(Metro.primary)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Metro.surfaceCont)
        .padding(.horizontal, Metro.margin)
    }

    // MARK: - Audio Button

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
                        .tint(Metro.primary)
                        .scaleEffect(0.75)
                } else {
                    Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Metro.primary)
                }
            }
            .frame(width: 44, height: 44)
        }
        .disabled(audio.isLoading)
    }

    // MARK: - Utility Views

    private var loadingView: some View {
        ProgressView()
            .tint(Metro.primary)
    }

    private func failureView(_ failure: ReaderFailure) -> some View {
        VStack(spacing: 20) {
            Text("!")
                .font(Metro.displayHero())
                .foregroundStyle(Metro.primary)
            Text(failure.localizedDescription)
                .font(Metro.bodyMd())
                .foregroundStyle(Metro.onSurface)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Metro.margin)
            Button {
                onClose()
            } label: {
                Text("BACK TO LIBRARY")
                    .font(Metro.labelSm(size: 14))
                    .foregroundStyle(Metro.background)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Metro.primary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Labels

    private var chapterLabel: String {
        guard let p = vm.provider else { return "" }
        let idx = p.currentUnit + 1
        let isEPUB = book.fileURL.pathExtension.lowercased() == "epub"
        return isEPUB ? "CH.\(String(format: "%02d", idx))" : "P.\(idx)"
    }

    private var positionLabel: String {
        guard let p = vm.provider else { return "—" }
        let isEPUB = book.fileURL.pathExtension.lowercased() == "epub"
        let prefix = isEPUB ? "CH." : "P."
        return "\(prefix)\(p.currentUnit + 1)"
    }

    // MARK: - Animation

    private func triggerPageTurn(forward: Bool) {
        if audio.isActive && !audioFollowsReading { audio.stop() }
        let screenW = UIScreen.main.bounds.width
        let dir: CGFloat = forward ? -1 : 1

        withAnimation(.easeIn(duration: 0.13)) {
            slideOffset = dir * screenW * 0.45
            pageOpacity = 0
            liveOffset  = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) {
            vm.advance(forward: forward)
            slideOffset = -dir * screenW * 0.25
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
