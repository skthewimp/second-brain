import SwiftUI

struct ContentView: View {
    @EnvironmentObject var captureService: ThoughtCaptureService
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Recording interface - takes what it needs
                RecordingView()
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                // Notes list fills remaining space
                NotesListView()
                    .frame(maxHeight: .infinity)
            }
            .navigationTitle("Pensieve")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gear")
                    }
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    StatusBadge()
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }
}

struct StatusBadge: View {
    @EnvironmentObject var captureService: ThoughtCaptureService

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.caption)
        }
    }

    var statusColor: Color {
        if !captureService.isConfigured { return .orange }
        if !captureService.transcriptionService.isModelLoaded { return .yellow }
        return .green
    }

    var statusText: String {
        if !captureService.isConfigured { return "No API Key" }
        if !captureService.transcriptionService.isModelLoaded {
            return captureService.transcriptionService.loadingProgress
        }
        return "Ready"
    }
}
