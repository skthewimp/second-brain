import Foundation
import WhisperKit

/// On-device transcription using WhisperKit.
/// Runs entirely on the iPhone's Neural Engine — no network needed.
class TranscriptionService: ObservableObject {
    private var whisperKit: WhisperKit?
    @Published var isModelLoaded = false
    @Published var loadingProgress: String = "Not loaded"

    /// Load the Whisper model. Call once at app startup.
    /// Uses "base" model for balance of speed and accuracy on iPhone.
    private static let modelName = "openai_whisper-base"

    /// Check if the model is already downloaded
    private func modelFolder() -> String? {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let huggingface = documents.appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml")
        // Look for the model folder
        guard let contents = try? FileManager.default.contentsOfDirectory(at: huggingface, includingPropertiesForKeys: nil) else {
            return nil
        }
        // Find a folder matching our model name
        for item in contents {
            if item.lastPathComponent.contains(Self.modelName) {
                // Verify it has actual model files inside
                if let files = try? FileManager.default.contentsOfDirectory(at: item, includingPropertiesForKeys: nil),
                   files.contains(where: { $0.pathExtension == "mlmodelc" }) {
                    print("Found cached model at: \(item.path)")
                    return item.path
                }
            }
        }
        return nil
    }

    func loadModel() async {
        // Check if model is already downloaded
        if let existingFolder = modelFolder() {
            await MainActor.run { loadingProgress = "Loading model..." }
            do {
                whisperKit = try await WhisperKit(
                    WhisperKitConfig(modelFolder: existingFolder, verbose: true, logLevel: .debug, load: true, download: false)
                )
                await MainActor.run {
                    isModelLoaded = true
                    loadingProgress = "Ready"
                }
                print("WhisperKit loaded from cache")
                return
            } catch {
                print("Failed to load cached model, will re-download: \(error)")
            }
        }

        // Download model
        do {
            await MainActor.run { loadingProgress = "Downloading model..." }
            whisperKit = try await WhisperKit(
                WhisperKitConfig(model: Self.modelName, verbose: true, logLevel: .debug, load: true, download: true)
            )
            await MainActor.run {
                isModelLoaded = true
                loadingProgress = "Ready"
            }
            print("WhisperKit model downloaded and loaded")
        } catch {
            await MainActor.run { loadingProgress = "Failed: \(error.localizedDescription)" }
            print("Failed to load WhisperKit: \(error)")
        }
    }

    /// Transcribe an audio file. Returns the full text.
    func transcribe(audioURL: URL) async throws -> String {
        guard let whisperKit = whisperKit else {
            throw TranscriptionError.modelNotLoaded
        }

        let results = try await whisperKit.transcribe(audioPath: audioURL.path)

        guard let result = results.first, !result.text.isEmpty else {
            throw TranscriptionError.emptyResult
        }

        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum TranscriptionError: LocalizedError {
    case modelNotLoaded
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return "Whisper model not loaded yet"
        case .emptyResult: return "Transcription returned empty result"
        }
    }
}
