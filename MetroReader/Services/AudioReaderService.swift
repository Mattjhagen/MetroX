import AVFoundation
import SwiftUI

@MainActor
final class AudioReaderService: NSObject, ObservableObject, AVAudioPlayerDelegate {

    @Published var isPlaying = false
    @Published var isLoading = false
    @Published var error: String?
    /// Current word index within the playing chunk. nil when stopped or no timings.
    @Published var currentWordIndex: Int? = nil

    var onUnitFinished: (() -> Void)?

    @AppStorage("elevenLabsAPIKey")    var apiKey:           String = ""
    @AppStorage("elevenLabsVoiceID")   var voiceID:          String = ElevenLabsVoice.default.id
    @AppStorage("ttsHighlightEnabled") var highlightEnabled: Bool   = false

    private var player: AVAudioPlayer?
    private var currentTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?
    private var highlightTimer: Timer?
    private var wordTimings: [WordTiming] = []
    private var pendingKey: String?

    // MARK: - Public API

    // Debounced 400ms: rapid page turns cancel and restart the clock, preventing
    // API storms and mid-turn synthesis.
    func play(text: String, chunkKey: String) {
        if isPlaying && pendingKey == chunkKey { return }
        cancelDebounce()
        stopPlayer()
        pendingKey = chunkKey

        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.synthesizeAndPlay(text: text, chunkKey: chunkKey)
        }
    }

    func stop() {
        cancelDebounce()
        stopPlayer()
        isLoading = false
        pendingKey = nil
        wordTimings = []
        stopHighlightTimer()
    }

    func toggle(text: String, chunkKey: String) {
        if isPlaying || isLoading { stop() } else { play(text: text, chunkKey: chunkKey) }
    }

    var isActive: Bool { isPlaying || isLoading }

    // MARK: - AVAudioPlayerDelegate

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.stopHighlightTimer()
            self.isPlaying = false
            self.player = nil
            self.currentWordIndex = nil
            if flag { self.onUnitFinished?() }
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            self.stopHighlightTimer()
            self.isPlaying = false
            self.player = nil
            self.currentWordIndex = nil
            self.error = error?.localizedDescription ?? "Audio decode error."
        }
    }

    // MARK: - Private

    private func cancelDebounce() {
        debounceTask?.cancel()
        debounceTask = nil
    }

    private func stopPlayer() {
        currentTask?.cancel()
        currentTask = nil
        player?.stop()
        player = nil
        isPlaying = false
        stopHighlightTimer()
    }

    private func synthesizeAndPlay(text: String, chunkKey: String) async {
        // Read fresh from UserDefaults at call time — @AppStorage can lag
        // behind when the value is set in a different view context.
        let rawStored = UserDefaults.standard.string(forKey: "elevenLabsAPIKey")
        print("[MetroReader] synthesize — rawStored len=\(rawStored?.count ?? -1) prefix=\(String((rawStored ?? "").prefix(6)))")
        let liveKey = (rawStored ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let liveVoice = (UserDefaults.standard.string(forKey: "elevenLabsVoiceID") ?? voiceID)
        print("[MetroReader] synthesize — liveKey len=\(liveKey.count) voice=\(liveVoice)")

        guard !liveKey.isEmpty else {
            print("[MetroReader] synthesize — ABORT: key is empty")
            error = ElevenLabsError.noAPIKey.errorDescription
            return
        }

        let truncated = String(text.prefix(2500))
        isLoading = true
        error = nil

        do {
            let audioData: Data
            if highlightEnabled {
                let (data, timings) = try await ElevenLabsService.synthesizeWithTimings(
                    text: truncated, apiKey: liveKey, voiceID: liveVoice
                )
                audioData = data
                wordTimings = timings
            } else {
                audioData = try await ElevenLabsService.synthesize(
                    text: truncated, apiKey: liveKey, voiceID: liveVoice
                )
                wordTimings = []
            }

            guard !Task.isCancelled else { return }

            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(chunkKey).mp3")
            try audioData.write(to: tmp)

            try await Task.detached(priority: .userInitiated) {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
                try AVAudioSession.sharedInstance().setActive(true)
            }.value

            let p = try AVAudioPlayer(contentsOf: tmp)
            p.delegate = self
            p.prepareToPlay()
            player = p
            isLoading = false
            isPlaying = true
            p.play()

            if highlightEnabled && !wordTimings.isEmpty {
                startHighlightTimer()
            }
        } catch {
            guard !Task.isCancelled else { return }
            isLoading = false
            self.error = error.localizedDescription
        }
    }

    // MARK: - Word highlight timer

    private func startHighlightTimer() {
        highlightTimer?.invalidate()
        highlightTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let p = self.player, self.isPlaying else { return }
                let t = p.currentTime
                // Binary-style scan: find the word whose window contains the current time
                let idx = self.wordTimings.indices.last(where: { self.wordTimings[$0].startTime <= t })
                if self.currentWordIndex != idx { self.currentWordIndex = idx }
            }
        }
    }

    private func stopHighlightTimer() {
        highlightTimer?.invalidate()
        highlightTimer = nil
        currentWordIndex = nil
    }
}
