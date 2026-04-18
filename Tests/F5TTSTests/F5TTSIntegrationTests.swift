import Foundation
import F5TTS
import MLX
import XCTest

final class F5TTSIntegrationTests: XCTestCase {
    private func requireIntegrationEnabled() throws {
        let env = ProcessInfo.processInfo.environment
        guard env["F5TTS_RUN_INTEGRATION"] == "1" else {
            throw XCTSkip(
                "Skipping integration test. Set F5TTS_RUN_INTEGRATION=1 to enable model download/inference tests."
            )
        }
    }

    private func assertModelCanGenerate(_ model: F5TTS) async throws {
        let audio = try await model.generate(
            text: "test",
            referenceAudioURL: nil,
            referenceAudioText: nil,
            duration: 1.0,
            steps: 2,
            method: .euler,
            cfg: 1.0,
            sway: 0.0,
            speed: 1.0,
            seed: 0
        )

        XCTAssertGreaterThan(audio.shape[0], 0)

        // Ensure generated audio is not all zeros.
        MLX.eval(audio)
        let energy = Double(audio.square().sum().item(Float.self))
        XCTAssertGreaterThan(energy, 0)
    }

    func testFromPretrainedConfigFullPrecisionAndSwift4BitPaths() async throws {
        try requireIntegrationEnabled()

        let fullPrecisionConfig = F5TTSLoadConfig(
            repoId: "lucasnewman/f5-tts-mlx",
            quantization: .none
        )
        let fullPrecisionModel = try await F5TTS.fromPretrained(config: fullPrecisionConfig)
        try await assertModelCanGenerate(fullPrecisionModel)

        let fourBitConfig = F5TTSLoadConfig(
            repoId: "lucasnewman/f5-tts-mlx",
            quantization: .bits(4)
        )
        let fourBitModel = try await F5TTS.fromPretrained(config: fourBitConfig)
        try await assertModelCanGenerate(fourBitModel)
    }

    func testFromPretrainedConfigDedicated4BitRepoPath() async throws {
        try requireIntegrationEnabled()

        let config = F5TTSLoadConfig.fourBitDefault()
        let model = try await F5TTS.fromPretrained(config: config)
        try await assertModelCanGenerate(model)
    }
}
