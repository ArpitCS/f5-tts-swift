import ArgumentParser
import F5TTS
import Foundation
import MLX
import Vocos

@main
struct GenerateAudio: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Generate speech audio with F5-TTS.",
        discussion: "Example:\n  swift run f5-tts-generate --text \"Hello\" --q 4"
    )

    @Argument(help: "Text to generate speech from")
    var text: String
    
    @Option(name: .long, help: "Duration of the generated audio in seconds")
    var duration: Double?
    
    @Option(name: .long, help: "Path to the reference audio file")
    var refAudioPath: String?
    
    @Option(name: .long, help: "Text spoken in the reference audio")
    var refAudioText: String?
    
    @Option(name: .long, help: "Model repo to use")
    var model: String = "lucasnewman/f5-tts-mlx"

    @Option(name: .long, help: "Quantization bits (e.g. 4 or 8). Omit or 0 for full precision.")
    var q: Int?
    
    @Option(name: .long, help: "Output path for the generated audio")
    var outputPath: String = "output.wav"
    
    @Option(name: .long, help: "The number of steps to use for ODE sampling")
    var steps: Int = 8
    
    @Option(name: .long, help: "Method to use for ODE sampling. Options are 'euler', 'midpoint', and 'rk4'.")
    var method: String = "rk4"
    
    @Option(name: .long, help: "Strength of classifier free guidance")
    var cfg: Double = 2.0
    
    @Option(name: .long, help: "Coefficient for sway sampling")
    var sway: Double = -1.0
    
    @Option(name: .long, help: "Speed factor for the duration heuristic")
    var speed: Double = 1.0
    
    @Option(name: .long, help: "Seed for noise generation")
    var seed: Int?
    
    func run() async throws {
        let quantization: F5TTSQuantization
        if let q, q > 0 {
            quantization = .bits(q)
        } else {
            quantization = .none
        }

        let config = F5TTSLoadConfig(repoId: model, quantization: quantization)
        print("Loading F5-TTS model from \(config.repoId) with quantization: \(config.quantization)")
        let f5tts = try await F5TTS.fromPretrained(config: config) { progress in
            print(" -- \(progress.completedUnitCount) of \(progress.totalUnitCount)")
        }
        
        let startTime = Date()
        
        let generatedAudio = try await f5tts.generate(
            text: text,
            referenceAudioURL: refAudioPath != nil ? URL(filePath: refAudioPath!) : nil,
            referenceAudioText: refAudioText,
            duration: duration,
            steps: steps,
            method: F5TTS.ODEMethod(rawValue: method)!,
            cfg: cfg,
            sway: sway,
            speed: speed,
            seed: seed
        )
        
        let elapsedTime = Date().timeIntervalSince(startTime)
        print("Generated \(Double(generatedAudio.shape[0]) / Double(F5TTS.sampleRate)) seconds of audio in \(elapsedTime) seconds.")
        
        try AudioUtilities.saveAudioFile(url: URL(filePath: outputPath), samples: generatedAudio)
        print("Saved audio to: \(outputPath)")
    }
}
