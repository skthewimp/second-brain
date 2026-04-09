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
            duration: duration
        )

        notes.insert(note, at: 0)
        currentNote = note
        saveNotes()

        // Automatically start processing
        Task {
            await processNote(id: note.id)
        }
    }

    // MARK: - Processing Pipeline

    /// Run the full pipeline on a note: transcribe → Claude → save to wiki
    func processNote(id: String) async {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }

        await MainActor.run { isProcessing = true }

        // Step 1: Transcribe
        await updateStatus(id: id, status: .transcribing)
        do {
            let transcription = try await transcriptionService.transcribe(audioURL: notes[index].audioURL)
            await MainActor.run {
                if let i = notes.firstIndex(where: { $0.id == id }) {
                    notes[i].transcription = transcription
                }
            }
        } catch {
            print("Transcription failed: \(error)")
            await updateStatus(id: id, status: .failed)
            await MainActor.run { isProcessing = false }
            return
        }

        await updateStatus(id: id, status: .transcribed)

        // Step 2: Process with Claude
        guard let claudeService = claudeService else {
            print("Claude API not configured")
            await updateStatus(id: id, status: .failed)
            await MainActor.run { isProcessing = false }
            return
        }

        await updateStatus(id: id, status: .processing)
        let processed: ClaudeProcessedNote
        do {
            let transcription = await MainActor.run { notes.first(where: { $0.id == id })?.transcription ?? "" }
            processed = try await claudeService.process(transcription: transcription)
            await MainActor.run {
                if let i = notes.firstIndex(where: { $0.id == id }) {
                    notes[i].summary = processed.summary.joined(separator: "\n")
                    notes[i].themes = processed.themes
                    notes[i].emotionalTone = processed.emotionalTone
                }
            }
        } catch {
            print("Claude processing failed: \(error)")
            await updateStatus(id: id, status: .failed)
            await MainActor.run { isProcessing = false }
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
            print("Save failed: \(error)")
            await updateStatus(id: id, status: .failed)
            await MainActor.run { isProcessing = false }
            return
        }

        await updateStatus(id: id, status: .completed)
        await MainActor.run { isProcessing = false }
        saveNotes()
    }

    /// Retry processing a failed note
    func retryNote(id: String) async {
        await processNote(id: id)
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
        try? FileManager.default.removeItem(at: note.audioURL)
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
