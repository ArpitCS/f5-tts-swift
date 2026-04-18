import SwiftUI
import AVFoundation
import F5TTS
import Combine

#if canImport(MLX)
import MLX
#endif

enum GenerationMode: String, CaseIterable, Identifiable {
    case textOnly = "Text only"
    case cloneVoice = "Clone voice from reference audio"

    var id: String { rawValue }
}

@MainActor
final class F5TTSViewModel: ObservableObject {
    @Published var inputText = "Hello from 4-bit F5-TTS on macOS."
    @Published var referenceText = ""
    @Published var referenceAudioURL: URL?
    @Published var generationMode: GenerationMode = .textOnly
    @Published var isGenerating = false
    @Published var status = "Idle"

    private var f5tts: F5TTS?
    private let audioPlayer = AudioPlaybackHelper()

    var canGenerate: Bool {
        let hasInput = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasRequiredReference = generationMode == .textOnly || referenceAudioURL != nil
        return !isGenerating && hasInput && hasRequiredReference
    }

    func chooseReferenceAudio() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.wav]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Select"
        panel.message = "Choose a mono 24kHz WAV file to use as reference audio."

        if panel.runModal() == .OK {
            referenceAudioURL = panel.url
            status = "Reference selected"
        }
    }

    func generateSpeech() {
        Task {
            await runGeneration()
        }
    }

    private func runGeneration() async {
        isGenerating = true
        defer { isGenerating = false }

        do {
            let model = try await loadModelIfNeeded()

            let useReference = generationMode == .cloneVoice
            if useReference && referenceAudioURL == nil {
                throw NSError(
                    domain: "F5TTS4BitDemo",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Please choose a reference WAV file first."]
                )
            }

            status = "Generating..."
            let generated = try await model.generate(
                text: inputText,
                referenceAudioURL: useReference ? referenceAudioURL : nil,
                referenceAudioText: useReference ? nilIfEmpty(referenceText) : nil,
                duration: nil
            )

            let samples = try convertGeneratedSamples(generated)
            try audioPlayer.play(samples: samples, sampleRate: 24_000)
            status = "Done"
        } catch {
            status = "Error: \(userFacingErrorMessage(error))"
        }
    }

    private func loadModelIfNeeded() async throws -> F5TTS {
        if let f5tts {
            return f5tts
        }

        // First call may download the quantized model weights, so we surface this in status.
        status = "Downloading model..."
        let loaded = try await F5TTS.fromPretrained4BitQuantizedRepo()
        f5tts = loaded
        return loaded
    }

    private func userFacingErrorMessage(_ error: Error) -> String {
        let message = error.localizedDescription

        if message.contains("model.safetensors") || message.contains("Failed to open file") {
            return "Model file missing in cache. Quit app, delete the app container's Documents/huggingface cache, relaunch, and generate again to re-download weights."
        }

        return message
    }

    private func nilIfEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func convertGeneratedSamples(_ generated: Any) throws -> [Float] {
        if let floatSamples = generated as? [Float] {
            return floatSamples
        }

#if canImport(MLX)
        if let mlxSamples = generated as? MLXArray {
            return mlxSamples.asArray(Float.self)
        }
#endif

        throw NSError(
            domain: "F5TTS4BitDemo",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Unsupported audio sample type returned by F5TTS.generate."]
        )
    }
}

final class AudioPlaybackHelper {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()

    init() {
        engine.attach(playerNode)
    }

    func play(samples: [Float], sampleRate: Double) throws {
        guard !samples.isEmpty else {
            throw NSError(
                domain: "F5TTS4BitDemo",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "No samples were generated."]
            )
        }

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        guard
            let format,
            let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(samples.count)
            ),
            let channelData = buffer.floatChannelData?[0]
        else {
            throw NSError(
                domain: "F5TTS4BitDemo",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Unable to create playback buffer."]
            )
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        for (index, sample) in samples.enumerated() {
            channelData[index] = max(-1.0, min(1.0, sample))
        }

        engine.disconnectNodeOutput(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)

        if !engine.isRunning {
            try engine.start()
        }

        playerNode.stop()
        playerNode.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        playerNode.play()
    }
}

struct ContentView: View {
    @StateObject private var viewModel = F5TTSViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("F5-TTS 4-bit Demo")
                .font(.title2.weight(.semibold))

            Text("Input text")
                .font(.headline)

            TextEditor(text: $viewModel.inputText)
                .font(.body)
                .frame(minHeight: 120)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.quaternary)
                )

            Text("Reference text (optional)")
                .font(.headline)

            TextField("Caption/transcript for reference audio", text: $viewModel.referenceText)
                .textFieldStyle(.roundedBorder)

            Picker("Mode", selection: $viewModel.generationMode) {
                ForEach(GenerationMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            GroupBox("Reference audio file") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(viewModel.referenceAudioURL?.path ?? "None")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Button("Choose Reference Audio…") {
                        viewModel.chooseReferenceAudio()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 12) {
                Button("Generate Speech (4-bit)") {
                    viewModel.generateSpeech()
                }
                .disabled(!viewModel.canGenerate)

                if viewModel.isGenerating {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text("Status: \(viewModel.status)")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(minWidth: 700, minHeight: 560)
    }
}

#Preview {
    ContentView()
}
