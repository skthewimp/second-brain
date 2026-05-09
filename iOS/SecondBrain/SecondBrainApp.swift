import SwiftUI

@main
struct SecondBrainApp: App {
    @StateObject private var captureService = ThoughtCaptureService()
    @AppStorage("anthropicAPIKey") private var apiKey = ""

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(captureService)
                .task {
                    // Configure API key if saved
                    if !apiKey.isEmpty {
                        captureService.configure(apiKey: apiKey)
                    }

                    // Load Whisper model in background
                    await captureService.loadWhisperModel()

                    // Resume any notes stuck mid-pipeline from a prior session
                    await captureService.resumeStuckNotes()
                }
                .onOpenURL { url in
                    guard url.scheme == "pensieve", url.host == "record" else { return }
                    if !apiKey.isEmpty && !captureService.isConfigured {
                        captureService.configure(apiKey: apiKey)
                    }
                    Task { await captureService.toggleRecordingFromShortcut() }
                }
        }
    }
}
