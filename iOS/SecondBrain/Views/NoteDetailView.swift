import SwiftUI

struct NoteDetailView: View {
    let note: ThoughtNote

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(note.formattedDate)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        if note.source == .voice {
                            Text(note.formattedDuration)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else {
                            Text(note.source == .url ? "URL" : "Text")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }

                    if !note.urls.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(note.urls, id: \.self) { url in
                                Link(destination: url) {
                                    Text(url.absoluteString)
                                        .font(.caption)
                                        .foregroundColor(.indigo)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                            if let af = note.articleFetched, !af {
                                Label("Article fetch failed — themes from your text only", systemImage: "exclamationmark.triangle")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                        }
                    }

                    if let raw = note.rawText, note.source != .voice {
                        Text(raw)
                            .font(.body)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(8)
                    }

                    if let tone = note.emotionalTone {
                        Label(tone, systemImage: toneIcon(tone))
                            .font(.subheadline)
                            .foregroundColor(.indigo)
                    }
                }

                // Themes
                if let themes = note.themes, !themes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Themes")
                            .font(.headline)

                        FlowLayout(spacing: 6) {
                            ForEach(themes, id: \.self) { theme in
                                Text(theme)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.indigo.opacity(0.1))
                                    .foregroundColor(.indigo)
                                    .cornerRadius(8)
                            }
                        }
                    }
                }

                // Summary
                if let summary = note.summary {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Summary")
                            .font(.headline)

                        Text(summary)
                            .font(.body)
                            .foregroundColor(.primary)
                    }
                }

                Divider()

                // Full transcription
                if let transcription = note.transcription {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Full Transcription")
                            .font(.headline)

                        Text(transcription)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }

                // Error (if failed)
                if note.status == .failed, let err = note.lastError {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Error", systemImage: "exclamationmark.triangle.fill")
                            .font(.headline)
                            .foregroundColor(.red)
                        Text(err)
                            .font(.callout)
                            .foregroundColor(.red)
                            .textSelection(.enabled)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.08))
                            .cornerRadius(8)
                    }
                }

                // Status
                HStack {
                    Spacer()
                    Label(note.status.displayText, systemImage: note.savedToWiki ? "checkmark.icloud" : "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.top, 20)
            }
            .padding()
        }
        .navigationTitle("Thought")
        .navigationBarTitleDisplayMode(.inline)
    }

    func toneIcon(_ tone: String) -> String {
        switch tone.lowercased() {
        case "anxious": return "exclamationmark.triangle"
        case "excited": return "star"
        case "frustrated": return "flame"
        case "hopeful": return "sun.max"
        case "confused": return "questionmark.circle"
        case "determined": return "bolt"
        case "sad": return "cloud.rain"
        case "angry": return "bolt.circle"
        case "grateful": return "heart"
        case "reflective": return "sparkles"
        default: return "circle"
        }
    }
}

/// Simple flow layout for theme tags
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            totalHeight = currentY + lineHeight
        }

        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}
