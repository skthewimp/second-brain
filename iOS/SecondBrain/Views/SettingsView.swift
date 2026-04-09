import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var captureService: ThoughtCaptureService
    @Environment(\.dismiss) var dismiss

    @AppStorage("anthropicAPIKey") private var apiKey = ""
    @State private var tempAPIKey = ""
    @State private var showAPIKey = false
    @State private var showFolderPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        if showAPIKey {
                            TextField("sk-ant-...", text: $tempAPIKey)
                                .textContentType(.password)
                                .textInputAutocapitalization(.never)
                                .font(.system(.body, design: .monospaced))
                        } else {
                            SecureField("sk-ant-...", text: $tempAPIKey)
                                .textContentType(.password)
                                .textInputAutocapitalization(.never)
                        }

                        Button(action: { showAPIKey.toggle() }) {
                            Image(systemName: showAPIKey ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                    }

                    Button("Save API Key") {
                        apiKey = tempAPIKey
                        captureService.configure(apiKey: apiKey)
                    }
                    .disabled(tempAPIKey.isEmpty)

                    HStack {
                        Text("Status")
                        Spacer()
                        Text(captureService.isConfigured ? "Configured" : "Not Set")
                            .foregroundColor(captureService.isConfigured ? .green : .orange)
                    }
                } header: {
                    Text("Anthropic API Key")
                } footer: {
                    Text("Stored locally on this device. Get one from console.anthropic.com.")
                }

                Section {
                    if captureService.isVaultLinked {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Linked")
                                .foregroundColor(.green)
                        }

                        Text(captureService.vaultURL.lastPathComponent)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button("Change Vault") {
                            showFolderPicker = true
                        }

                        Button("Unlink Vault", role: .destructive) {
                            captureService.storageService.unlinkVault()
                        }
                    } else {
                        HStack {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundColor(.orange)
                            Text("Not linked — notes saved locally only")
                                .font(.subheadline)
                        }

                        Button("Select Obsidian Vault") {
                            showFolderPicker = true
                        }
                    }
                } header: {
                    Text("Obsidian Vault")
                } footer: {
                    Text("Pick your Obsidian vault folder. Notes will be saved directly into it and sync via iCloud automatically.")
                }

                Section("Whisper Model") {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(captureService.transcriptionService.loadingProgress)
                            .foregroundColor(captureService.transcriptionService.isModelLoaded ? .green : .orange)
                    }

                    if !captureService.transcriptionService.isModelLoaded {
                        Button("Load Model") {
                            Task { await captureService.loadWhisperModel() }
                        }
                    }
                }

                Section {
                    let unsavedCount = captureService.notes.filter { !$0.savedToWiki && $0.transcription != nil && !$0.transcription!.isEmpty }.count
                    if unsavedCount > 0 {
                        Button("Push \(unsavedCount) Old Note\(unsavedCount == 1 ? "" : "s") to Vault") {
                            Task { await captureService.resaveAllToVault() }
                        }
                        .disabled(captureService.isProcessing || !captureService.isConfigured)
                    } else {
                        Text("All notes are saved to vault")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Vault Sync")
                } footer: {
                    Text("Re-processes and saves any notes that were recorded before the vault was linked.")
                }

                Section("Stats") {
                    HStack {
                        Text("Total Thoughts")
                        Spacer()
                        Text("\(captureService.notes.count)")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Saved to Wiki")
                        Spacer()
                        Text("\(captureService.notes.filter { $0.savedToWiki }.count)")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Wiki Notes")
                        Spacer()
                        Text("\(captureService.storageService.rawNoteCount())")
                            .foregroundColor(.secondary)
                    }
                }

                Section {
                    Text("Audio stays on your phone. Transcription runs on-device. Only the transcription text is sent to Claude API for analysis.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Privacy")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                tempAPIKey = apiKey
                if !apiKey.isEmpty {
                    captureService.configure(apiKey: apiKey)
                }
            }
            .sheet(isPresented: $showFolderPicker) {
                FolderPicker { url in
                    if let url = url {
                        captureService.storageService.linkVault(url: url)
                    }
                }
            }
        }
    }
}

/// Wraps UIDocumentPickerViewController to let the user select a folder
struct FolderPicker: UIViewControllerRepresentable {
    let onPick: (URL?) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL?) -> Void

        init(onPick: @escaping (URL?) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls.first)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onPick(nil)
        }
    }
}
