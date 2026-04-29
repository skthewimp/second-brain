import SwiftUI

struct NotesListView: View {
    @EnvironmentObject var captureService: ThoughtCaptureService

    var body: some View {
        List {
            if captureService.notes.isEmpty {
                ContentUnavailableView(
                    "No Thoughts Yet",
                    systemImage: "brain",
                    description: Text("Record your first thought to get started")
                )
            } else {
                ForEach(captureService.notes) { note in
                    NavigationLink(destination: NoteDetailView(note: note)) {
                        NoteRow(note: note)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            captureService.deleteNote(id: note.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        if note.status == .failed {
                            Button {
                                Task { await captureService.retryNote(id: note.id) }
                            } label: {
                                Label("Retry", systemImage: "arrow.clockwise")
                            }
                            .tint(.blue)
                        }
                    }
                }
            }
        }
    }
}

struct NoteRow: View {
    let note: ThoughtNote

    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            statusIcon
                .font(.title2)

            VStack(alignment: .leading, spacing: 4) {
                // Title or filename
                Text(noteTitle)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(note.formattedDate)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("·")
                        .foregroundColor(.secondary)

                    Image(systemName: sourceIcon)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if note.source == .voice {
                        Text(note.formattedDuration)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if note.source == .url {
                        Text("\(note.urls.count) link\(note.urls.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let tone = note.emotionalTone {
                        Text("·")
                            .foregroundColor(.secondary)
                        Text(tone)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }

                // Theme tags
                if let themes = note.themes, !themes.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(themes.prefix(3), id: \.self) { theme in
                            Text(theme)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.indigo.opacity(0.1))
                                .foregroundColor(.indigo)
                                .cornerRadius(4)
                        }
                        if themes.count > 3 {
                            Text("+\(themes.count - 3)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Spacer()

            if note.status.isInProgress {
                ProgressView()
            }
        }
        .padding(.vertical, 4)
    }

    var noteTitle: String {
        if let summary = note.summary {
            return String(summary.prefix(60))
        }
        return note.status.displayText
    }

    var sourceIcon: String {
        switch note.source {
        case .voice: return "mic.fill"
        case .text: return "text.bubble"
        case .url: return "link"
        }
    }

    var statusIcon: some View {
        Group {
            switch note.status {
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            case .failed:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.red)
            case .recorded, .transcribed, .processed:
                Image(systemName: "circle.fill")
                    .foregroundColor(.gray)
            default:
                Image(systemName: "circle.dotted")
                    .foregroundColor(.blue)
            }
        }
    }
}
