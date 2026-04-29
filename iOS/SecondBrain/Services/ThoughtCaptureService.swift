import Foundation
import SwiftUI
import Combine

/// Orchestrates the full capture pipeline: record → transcribe → process → save.
/// This is the main service the UI talks to.
class ThoughtCaptureService: ObservableObject {
    @Published var notes: [ThoughtNote] = []
    @Published var currentNote: ThoughtNote?
    @Published var isProcessing = false

    // Forwarded from audioRecorder so SwiftUI can observe them directly
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0

    // Forwarded from storageService so SwiftUI can observe vault state
    @Published var isVaultLinked = false
    @Published var vaultURL: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    let audioRecorder = AudioRecorderService()
    let transcriptionService = TranscriptionService()
    let storageService = ObsidianStorageService()

    @Published private(set) var isConfigured = false
    private var claudeService: ClaudeProcessingService?
    private var currentAudioURL: URL?
    private var cancellables = Set<AnyCancellable>()

    private let metadataURL: URL

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.metadataURL = documents.appendingPathComponent("Recordings/notes.json")
        loadNotes()

        // Forward audioRecorder state changes to this object so SwiftUI sees them
        audioRecorder.$isRecording
            .receive(on: DispatchQueue.main)
            .assign(to: &$isRecording)
        audioRecorder.$recordingDuration
            .receive(on: DispatchQueue.main)
            .assign(to: &$recordingDuration)

        // Forward storageService state changes
        storageService.$isVaultLinked
            .receive(on: DispatchQueue.main)
            .assign(to: &$isVaultLinked)
        storageService.$vaultURL
            .receive(on: DispatchQueue.main)
            .assign(to: &$vaultURL)
    }

    /// Set the API key (called from settings)
    func configure(apiKey: String) {
        self.claudeService = ClaudeProcessingService(apiKey: apiKey)
        self.isConfigured = true
    }

    /// Load the Whisper model at startup
    func loadWhisperModel() async {
        await transcriptionService.loadModel()
    }

    // MARK: - Recording

    func startRecording() {
        currentAudioURL = audioRecorder.startRecording()
    }

    func stopRecording() {
        let duration = audioRecorder.stopRecording()

        guard let audioURL = currentAudioURL else { return }

        let note = ThoughtNote(
            filename: audioURL.lastPathComponent,
            audioURL: audioURL,
            duration: duration,
            source: .voice
        )

        notes.insert(note, at: 0)
        currentNote = note
        saveNotes()

        // Automatically start processing
        Task {
            await processNote(id: note.id)
        }
    }

    // MARK: - Text / URL capture

    /// Submit a free-form text capture. Detects URLs and routes through Claude.
    func submitText(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let urls = Self.extractURLs(from: trimmed)
        let source: Source = urls.isEmpty ? .text : .url

        let note = ThoughtNote(
            filename: "text-\(UUID().uuidString.prefix(8)).md",
            audioURL: nil,
            duration: 0,
            source: source,
            urls: urls,
            rawText: trimmed
        )

        notes.insert(note, at: 0)
        currentNote = note
        saveNotes()

        Task {
            await processNote(id: note.id)
        }
    }

    private static func extractURLs(from text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        let matches = detector.matches(in: text, options: [], range: range)
        var seen = Set<String>()
        var urls: [URL] = []
        for m in matches {
            if let url = m.url {
                let s = url.absoluteString
                if !seen.contains(s) {
                    seen.insert(s)
                    urls.append(url)
                }
            }
        }
        return urls
    }

    // MARK: - Processing Pipeline

    /// Run the full pipeline on a note: transcribe (voice only) → Claude → save to wiki
    func processNote(id: String) async {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }

        await MainActor.run { isProcessing = true }
        await clearError(id: id)

        let noteSource = notes[index].source

        // Step 1: Transcribe (voice only). Text/URL notes skip straight to Claude.
        if noteSource == .voice {
            guard let audioURL = notes[index].audioURL else {
                await fail(id: id, stage: "Audio", error: "Voice note missing audioURL")
                return
            }
            if !FileManager.default.fileExists(atPath: audioURL.path) {
                await fail(id: id, stage: "Audio", error: "File missing at \(audioURL.lastPathComponent)")
                return
            }

            await updateStatus(id: id, status: .transcribing)
            do {
                let transcription = try await transcriptionService.transcribe(audioURL: audioURL)
                await MainActor.run {
                    if let i = notes.firstIndex(where: { $0.id == id }) {
                        notes[i].transcription = transcription
                    }
                }
            } catch {
                await fail(id: id, stage: "Transcribe", error: error.localizedDescription)
                return
            }
            await updateStatus(id: id, status: .transcribed)
        }

        // Step 2: Process with Claude
        guard let claudeService = claudeService else {
            await fail(id: id, stage: "Claude", error: "API key not configured in Settings")
            return
        }

        await updateStatus(id: id, status: .processing)
        let processed: ClaudeProcessedNote
        do {
            let snapshot = await MainActor.run { notes.first(where: { $0.id == id }) }
            guard let snap = snapshot else { return }

            switch snap.source {
            case .voice:
                let transcription = snap.transcription ?? ""
                processed = try await claudeService.process(transcription: transcription)
            case .text:
                let result = try await claudeService.processInput(text: snap.rawText ?? "", urls: [], kind: .text)
                processed = result.note
            case .url:
                let result = try await claudeService.processInput(text: snap.rawText ?? "", urls: snap.urls, kind: .url)
                processed = result.note
                await MainActor.run {
                    if let i = notes.firstIndex(where: { $0.id == id }) {
                        notes[i].articleFetched = result.articleFetched
                    }
                }
            }

            await MainActor.run {
                if let i = notes.firstIndex(where: { $0.id == id }) {
                    notes[i].summary = processed.summary.joined(separator: "\n")
                    notes[i].themes = processed.themes
                    notes[i].emotionalTone = processed.emotionalTone
                }
            }
        } catch {
            await fail(id: id, stage: "Claude", error: error.localizedDescription)
            return
        }

        await updateStatus(id: id, status: .processed)

        // Step 3: Save to Obsidian vault
        await updateStatus(id: id, status: .saving)
        do {
            let note = await MainActor.run { notes.first(where: { $0.id == id })! }
            _ = try storageService.save(note: note, processed: processed)
            await MainActor.run {
                if let i = notes.firstIndex(where: { $0.id == id }) {
                    notes[i].savedToWiki = true
                }
            }
        } catch {
            await fail(id: id, stage: "Save", error: error.localizedDescription)
            return
        }

        await updateStatus(id: id, status: .completed)
        await MainActor.run { isProcessing = false }
        saveNotes()
    }

    private func fail(id: String, stage: String, error: String) async {
        print("\(stage) failed: \(error)")
        await MainActor.run {
            if let i = notes.firstIndex(where: { $0.id == id }) {
                notes[i].lastError = "\(stage): \(error)"
                notes[i].status = .failed
            }
            isProcessing = false
        }
        saveNotes()
    }

    private func clearError(id: String) async {
        await MainActor.run {
            if let i = notes.firstIndex(where: { $0.id == id }) {
                notes[i].lastError = nil
            }
        }
    }

    /// Retry processing a failed note
    func retryNote(id: String) async {
        await processNote(id: id)
    }

    /// Resume any notes left in a non-terminal state (e.g. app was killed mid-pipeline).
    /// Each pipeline step is idempotent, so restarting from the top is safe.
    func resumeStuckNotes() async {
        let stuckIDs = notes
            .filter { $0.status != .completed && $0.status != .failed }
            .map { $0.id }

        for id in stuckIDs {
            await processNote(id: id)
        }
    }

    /// Reprocess and save all notes that have transcriptions but weren't saved to the wiki
    func resaveAllToVault() async {
        guard let claudeService = claudeService else {
            print("Claude API not configured")
            return
        }

        await MainActor.run { isProcessing = true }

        for note in notes {
            guard !note.savedToWiki, let transcription = note.transcription, !transcription.isEmpty else { continue }

            // Re-process through Claude to get full structured output
            do {
                let processed = try await claudeService.process(transcription: transcription)

                await MainActor.run {
                    if let i = notes.firstIndex(where: { $0.id == note.id }) {
                        notes[i].summary = processed.summary.joined(separator: "\n")
                        notes[i].themes = processed.themes
                        notes[i].emotionalTone = processed.emotionalTone
                    }
                }

                let currentNote = await MainActor.run { notes.first(where: { $0.id == note.id })! }
                _ = try storageService.save(note: currentNote, processed: processed)

                await MainActor.run {
                    if let i = notes.firstIndex(where: { $0.id == note.id }) {
                        notes[i].savedToWiki = true
                        notes[i].status = .completed
                    }
                }
                print("Resaved note: \(note.wikiFilename)")
            } catch {
                print("Failed to resave note \(note.id): \(error)")
            }
        }

        await MainActor.run { isProcessing = false }
        saveNotes()
    }

    /// Delete a note
    func deleteNote(id: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        let note = notes[index]
        if let audioURL = note.audioURL {
            try? FileManager.default.removeItem(at: audioURL)
        }
        notes.remove(at: index)
        saveNotes()
    }

    // MARK: - Persistence

    private func updateStatus(id: String, status: ProcessingStatus) async {
        await MainActor.run {
            if let i = notes.firstIndex(where: { $0.id == id }) {
                notes[i].status = status
            }
        }
    }

    private func loadNotes() {
        guard let data = try? Data(contentsOf: metadataURL),
              let loaded = try? JSONDecoder().decode([ThoughtNote].self, from: data) else { return }
        notes = loaded
    }

    private func saveNotes() {
        if let data = try? JSONEncoder().encode(notes) {
            try? data.write(to: metadataURL)
        }
    }
}
