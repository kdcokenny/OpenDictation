import SwiftUI

/// Recovery window for short-term dictation history.
struct RecentDictationsView: View {
    @ObservedObject var history: DictationHistoryService

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            if history.entries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(history.entries) { entry in
                            RecentDictationRow(entry: entry, history: history)
                            if entry.id != history.entries.last?.id {
                                Divider()
                                    .padding(.leading, 16)
                            }
                        }
                    }
                }
            }
        }
        .frame(width: 520, height: 420)
        .onAppear {
            history.pruneExpiredEntries()
        }
    }

    private var header: some View {
        HStack {
            Text("Recent")
                .font(.title2)
                .fontWeight(.semibold)
            Spacer()
        }
        .padding(16)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("No Recent Dictations")
                .font(.headline)
            Text("Recent attempts from this app session will appear here.")
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

private struct RecentDictationRow: View {
    let entry: DictationHistoryEntry
    @ObservedObject var history: DictationHistoryService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: entry.context.category.sfSymbol)
                    .foregroundColor(.secondary)
                    .frame(width: 18)

                Text(entry.context.category.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(entry.createdAt, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                statusLabel
            }

            Text(summaryText)
                .font(.body)
                .lineLimit(3)
                .textSelection(.enabled)
                .foregroundColor(hasTranscript ? .primary : .secondary)

            HStack {
                Button {
                    history.copyTranscript(id: entry.id)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .disabled(!hasTranscript)

                Button {
                    Task {
                        await history.retryTranscription(id: entry.id)
                    }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .disabled(!entry.canRetry || isRetrying)

                Spacer()
            }
            .controlSize(.small)
        }
        .padding(16)
    }

    private var statusLabel: some View {
        Text(statusText)
            .font(.caption)
            .foregroundColor(statusColor)
    }

    private var hasTranscript: Bool {
        entry.transcript?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private var isRetrying: Bool {
        if case .retrying = entry.transcriptionStatus {
            return true
        }
        return false
    }

    private var summaryText: String {
        switch entry.transcriptionStatus {
        case .pending:
            return "Transcription is pending."
        case .retrying:
            return "Retrying transcription..."
        case .succeeded(let text):
            return text
        case .empty:
            return "No speech was transcribed."
        case .failed(let message):
            return message
        }
    }

    private var statusText: String {
        switch entry.transcriptionStatus {
        case .pending:
            return "Pending"
        case .retrying:
            return "Retrying"
        case .empty:
            return "Empty"
        case .failed:
            return "Failed"
        case .succeeded:
            return deliveryText
        }
    }

    private var deliveryText: String {
        switch entry.deliveryStatus {
        case .notAttempted:
            return "Ready"
        case .inserted:
            return "Inserted"
        case .copiedOnly:
            return "Copied"
        case .failed:
            return "Delivery Failed"
        }
    }

    private var statusColor: Color {
        switch entry.transcriptionStatus {
        case .failed:
            return .red
        case .empty:
            return .orange
        case .retrying:
            return .accentColor
        case .pending, .succeeded:
            if case .failed = entry.deliveryStatus {
                return .red
            }
            return .secondary
        }
    }
}

#Preview {
    RecentDictationsView(history: DictationHistoryService())
}
