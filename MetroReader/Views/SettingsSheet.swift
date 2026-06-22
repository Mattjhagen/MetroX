import SwiftUI

struct SettingsSheet: View {
    @ObservedObject var settings: ReadingSettings
    @Environment(\.dismiss) private var dismiss

    @AppStorage("elevenLabsAPIKey")    private var apiKey:              String = ""
    @AppStorage("elevenLabsVoiceID")   private var voiceID:             String = ElevenLabsVoice.default.id
    @AppStorage("audioFollowsReading") private var audioFollowsReading: Bool   = false
    @AppStorage("ttsHighlightEnabled") private var ttsHighlightEnabled: Bool   = false

    @State private var keyTestResult: String? = nil
    @State private var keyTesting    = false

    var body: some View {
        ZStack {
            Metro.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Metro.gap) {
                    // Header
                    HStack {
                        Text("READING\nSETTINGS")
                            .font(Metro.headlineLg())
                            .foregroundStyle(Metro.primary)
                            .lineLimit(2)
                        Spacer()
                        Button { dismiss() } label: {
                            Text("DONE")
                                .font(Metro.labelSm(size: 14))
                                .foregroundStyle(Metro.background)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 10)
                                .background(Metro.primary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, Metro.margin)
                    .padding(.top, 32)

                    // Theme
                    sectionBlock(label: "THEME") {
                        HStack(spacing: Metro.gap) {
                            ForEach(ReadingTheme.allCases, id: \.rawValue) { theme in
                                let active = settings.themeRaw == theme.rawValue
                                Button { settings.themeRaw = theme.rawValue } label: {
                                    Text(theme.rawValue.uppercased())
                                        .font(Metro.labelSm(size: 13))
                                        .foregroundStyle(active ? Metro.background : Metro.onSurface)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(active ? Metro.primary : Metro.surfaceContHigh)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Font Size
                    sectionBlock(label: "TEXT SIZE") {
                        HStack(spacing: Metro.gap) {
                            ForEach(FontSize.allCases, id: \.rawValue) { size in
                                let active = settings.fontSizeRaw == size.rawValue
                                Button { settings.fontSizeRaw = size.rawValue } label: {
                                    Text(size.rawValue.uppercased())
                                        .font(Metro.labelSm(size: 13))
                                        .foregroundStyle(active ? Metro.background : Metro.onSurface)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(active ? Metro.primary : Metro.surfaceContHigh)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Margins
                    sectionBlock(label: "MARGINS") {
                        HStack(spacing: Metro.gap) {
                            ForEach(Margin.allCases, id: \.rawValue) { margin in
                                let active = settings.marginRaw == margin.rawValue
                                Button { settings.marginRaw = margin.rawValue } label: {
                                    Text(margin.rawValue.uppercased())
                                        .font(Metro.labelSm(size: 13))
                                        .foregroundStyle(active ? Metro.background : Metro.onSurface)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(active ? Metro.primary : Metro.surfaceContHigh)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // ElevenLabs TTS
                    sectionBlock(label: "ELEVENLABS TTS") {
                        VStack(alignment: .leading, spacing: 0) {
                            // API Key input
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("API KEY")
                                        .font(Metro.labelSm(size: 10))
                                        .foregroundStyle(Metro.onSurfaceVariant)
                                    Spacer()
                                    if !apiKey.isEmpty {
                                        Text("\(apiKey.count) chars")
                                            .font(Metro.labelSm(size: 10))
                                            .foregroundStyle(Metro.onSurfaceVariant.opacity(0.6))
                                    }
                                }
                                SecureField("", text: $apiKey,
                                    prompt: Text("Paste key here…").foregroundStyle(Metro.onSurfaceVariant))
                                    .onChange(of: apiKey) { old, v in
                                        let trimmed = v.trimmingCharacters(in: .whitespacesAndNewlines)
                                        if trimmed != v { apiKey = trimmed }
                                        if !old.isEmpty && old != trimmed { ElevenLabsService.clearCache() }
                                        keyTestResult = nil
                                    }
                                    .foregroundStyle(Metro.onSurface)
                                    .font(Metro.bodyMd())
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .padding(.vertical, 10)
                                    .overlay(alignment: .bottom) {
                                        Rectangle()
                                            .fill(apiKey.isEmpty ? Metro.outlineVariant : Metro.primary)
                                            .frame(height: 2)
                                    }

                                // Test Key button + result
                                if !apiKey.isEmpty {
                                    HStack(spacing: 8) {
                                        Button {
                                            keyTesting = true
                                            keyTestResult = nil
                                            Task {
                                                let result = await ElevenLabsService.validateKey(apiKey)
                                                keyTestResult = result ?? "✓ Key is valid"
                                                keyTesting = false
                                            }
                                        } label: {
                                            HStack(spacing: 6) {
                                                if keyTesting {
                                                    ProgressView().scaleEffect(0.7).tint(Metro.background)
                                                } else {
                                                    Image(systemName: "antenna.radiowaves.left.and.right")
                                                        .font(.system(size: 11))
                                                }
                                                Text(keyTesting ? "TESTING…" : "TEST KEY")
                                                    .font(Metro.labelSm(size: 11))
                                            }
                                            .foregroundStyle(Metro.background)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 7)
                                            .background(Metro.primary)
                                        }
                                        .buttonStyle(.plain)
                                        .disabled(keyTesting)

                                        if let result = keyTestResult {
                                            Text(result)
                                                .font(Metro.labelSm(size: 11))
                                                .foregroundStyle(result.hasPrefix("✓") ? Metro.secondary : Color(metroHex: "#ffb4ab"))
                                                .lineLimit(2)
                                        }
                                    }
                                    .padding(.top, 8)
                                }
                            }
                            .padding(.bottom, 16)

                            if !apiKey.isEmpty {
                                // Voice picker
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("VOICE")
                                        .font(Metro.labelSm(size: 10))
                                        .foregroundStyle(Metro.onSurfaceVariant)
                                    Picker("Voice", selection: $voiceID) {
                                        ForEach(ElevenLabsVoice.catalog) { voice in
                                            Text(voice.name.uppercased()).tag(voice.id)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .tint(Metro.primary)
                                    .padding(.vertical, 4)
                                    .overlay(alignment: .bottom) {
                                        Rectangle().fill(Metro.outlineVariant).frame(height: 1)
                                    }
                                }
                                .padding(.bottom, 16)

                                // Toggles
                                settingsToggle("AUDIO FOLLOWS READING", isOn: $audioFollowsReading)
                                    .padding(.bottom, 12)
                                settingsToggle("HIGHLIGHT WHILE READING", isOn: $ttsHighlightEnabled)
                                    .padding(.bottom, 16)

                                // Clear cache
                                Button {
                                    ElevenLabsService.clearCache()
                                } label: {
                                    HStack {
                                        Image(systemName: "trash")
                                            .font(.system(size: 13))
                                        Text("CLEAR AUDIO CACHE")
                                            .font(Metro.labelSm(size: 13))
                                    }
                                    .foregroundStyle(Color(metroHex: "#ffb4ab"))
                                    .padding(.vertical, 10)
                                    .frame(maxWidth: .infinity)
                                    .overlay(
                                        Rectangle().stroke(Color(metroHex: "#ffb4ab"), lineWidth: 2)
                                    )
                                }
                                .buttonStyle(.plain)
                            } else {
                                Text("Add an API key to enable read-aloud. A play button will appear in the reader toolbar.")
                                    .font(Metro.bodyMd())
                                    .foregroundStyle(Metro.onSurfaceVariant)
                            }
                        }
                    }

                    Spacer().frame(height: 40)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Metro.background)
    }

    // MARK: - Components

    private func sectionBlock<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
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

    private func settingsToggle(_ label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label)
                .font(Metro.labelSm(size: 13))
                .foregroundStyle(Metro.onSurface)
            Spacer()
            Toggle("", isOn: isOn)
                .tint(Metro.primaryContainer)
                .labelsHidden()
        }
        .padding(.bottom, 4)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Metro.outlineVariant).frame(height: 1)
        }
    }
}

