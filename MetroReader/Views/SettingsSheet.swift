import SwiftUI

struct SettingsSheet: View {
    @ObservedObject var settings: ReadingSettings
    @Environment(\.dismiss) private var dismiss

    @AppStorage("elevenLabsAPIKey")    private var apiKey:             String = ""
    @AppStorage("elevenLabsVoiceID")   private var voiceID:            String = ElevenLabsVoice.default.id
    @AppStorage("audioFollowsReading") private var audioFollowsReading: Bool   = false
    @AppStorage("ttsHighlightEnabled") private var ttsHighlightEnabled: Bool   = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Theme") {
                    Picker("Theme", selection: $settings.themeRaw) {
                        ForEach(ReadingTheme.allCases, id: \.rawValue) {
                            Text($0.rawValue).tag($0.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                }

                Section("Text Size") {
                    Picker("Font Size", selection: $settings.fontSizeRaw) {
                        ForEach(FontSize.allCases, id: \.rawValue) {
                            Text($0.rawValue).tag($0.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                }

                Section("Margins") {
                    Picker("Margin", selection: $settings.marginRaw) {
                        ForEach(Margin.allCases, id: \.rawValue) {
                            Text($0.rawValue).tag($0.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                }

                Section {
                    SecureField("Paste API key here", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if !apiKey.isEmpty {
                        Picker("Voice", selection: $voiceID) {
                            ForEach(ElevenLabsVoice.catalog) { voice in
                                Text(voice.name).tag(voice.id)
                            }
                        }

                        Toggle("Audio follows reading", isOn: $audioFollowsReading)
                        Toggle("Highlight while reading", isOn: $ttsHighlightEnabled)

                        Button("Clear Audio Cache", role: .destructive) {
                            ElevenLabsService.clearCache()
                        }
                    }
                } header: {
                    Text("ElevenLabs TTS")
                } footer: {
                    if apiKey.isEmpty {
                        Text("Add an ElevenLabs API key to enable read-aloud. A play button appears in the reader toolbar.")
                    }
                }
            }
            .navigationTitle("Reading Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
