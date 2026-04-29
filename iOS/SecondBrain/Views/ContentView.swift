import SwiftUI

struct ContentView: View {
    @EnvironmentObject var captureService: ThoughtCaptureService
    @State private var showSettings = false
    @State private var draftText: String = ""
    @FocusState private var draftFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                RecordingView()
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                TextCaptureView(draft: $draftText, isFocused: $draftFocused)
                    .frame(maxHeight: .infinity)
            }
            .navigationTitle("Pensieve")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gear")
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: NotesListView()) {
                        Image(systemName: "list.bullet.rectangle")
                    }
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    StatusBadge()
                }

                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button("Done") { draftFocused = false }
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
    }
}

struct TextCaptureView: View {
    @EnvironmentObject var captureService: ThoughtCaptureService
    @Binding var draft: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                if draft.isEmpty {
                    Text("Type a thought, paste a link, or both…")
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $draft)
                    .focused(isFocused)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .scrollContentBackground(.hidden)
            }
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)

            HStack {
                if !draft.isEmpty {
                    let urlCount = countURLs(in: draft)
                    if urlCount > 0 {
                        Label("\(urlCount) link\(urlCount == 1 ? "" : "s") detected", systemImage: "link")
                            .font(.caption)
                            .foregroundColor(.indigo)
                    }
                }
                Spacer()
                Button(action: submit) {
                    HStack(spacing: 6) {
                        Image(systemName: "paperplane.fill")
                        Text("Submit")
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(canSubmit ? Color.indigo : Color.gray.opacity(0.4))
                    .foregroundColor(.white)
                    .cornerRadius(20)
                }
                .disabled(!canSubmit)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    private var canSubmit: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && captureService.isConfigured
    }

    private func submit() {
        let text = draft
        draft = ""
        isFocused.wrappedValue = false
        captureService.submitText(text)
    }

    private func countURLs(in text: String) -> Int {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return 0 }
        let range = NSRange(text.startIndex..., in: text)
        return detector.numberOfMatches(in: text, options: [], range: range)
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
