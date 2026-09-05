import SwiftUI

/// Settings for vocabulary hints and transcript replacements.
struct DictionarySettingsView: View {
    @AppStorage(TranscriptionOutputFilter.removeFillerWordsKey)
    private var removeFillerWords = false

    @State private var vocabularyText = ""
    @State private var replacementRows: [ReplacementRow] = []
    @State private var validationMessage: String?
    @State private var savedMessage: String?
    @State private var draftIsValid = true
    @State private var isExpanded = false

    var body: some View {
        Section {
            DisclosureGroup("Personal Dictionary", isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    vocabularyEditor
                    Divider()
                    replacementsEditor
                    Divider()
                    Toggle("Remove filler words", isOn: $removeFillerWords)
                    Text("Removes words such as \"um\" and \"uh\" after transcription.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let validationMessage {
                        Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if let savedMessage {
                        Label(savedMessage, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }

                    HStack {
                        Spacer()
                        Button("Save Dictionary", action: save)
                            .disabled(!draftIsValid)
                    }
                }
                .padding(.top, 8)
            }
        }
        .onAppear(perform: load)
        .onChange(of: vocabularyText) { _, _ in validateDraft() }
        .onChange(of: replacementRows) { _, _ in validateDraft() }
    }

    private var vocabularyEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Vocabulary")
            TextEditor(text: $vocabularyText)
                .font(.body.monospaced())
                .frame(height: 72)
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.secondary.opacity(0.25))
                }
            Text("One name or term per line. Whisper-compatible services use the first 50 as recognition hints.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var replacementsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Literal replacements")
                Spacer()
                Button {
                    replacementRows.append(ReplacementRow())
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .disabled(replacementRows.count >= DictationDictionary.maximumReplacements)
            }

            if replacementRows.isEmpty {
                Text("Optional. Replace a spoken word or phrase after transcription.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach($replacementRows) { $row in
                HStack {
                    TextField("Spoken text", text: $row.source)
                        .textFieldStyle(.roundedBorder)
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                    TextField("Replacement", text: $row.replacement)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        replacementRows.removeAll { $0.id == row.id }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove replacement")
                }
            }
        }
    }

    private func load() {
        do {
            let dictionary = try DictationDictionary.load()
            vocabularyText = dictionary.vocabulary.joined(separator: "\n")
            replacementRows = dictionary.replacements.map {
                ReplacementRow(source: $0.source, replacement: $0.replacement)
            }
            validationMessage = nil
            draftIsValid = true
        } catch {
            validationMessage = error.localizedDescription
            draftIsValid = true
            isExpanded = true
        }
    }

    private func save() {
        do {
            let dictionary = try makeDictionary()
            try dictionary.save()
            validationMessage = nil
            savedMessage = "Dictionary saved."
            draftIsValid = true
        } catch {
            validationMessage = error.localizedDescription
            savedMessage = nil
            draftIsValid = false
        }
    }

    private func validateDraft() {
        savedMessage = nil
        do {
            _ = try makeDictionary()
            validationMessage = nil
            draftIsValid = true
        } catch {
            validationMessage = error.localizedDescription
            draftIsValid = false
        }
    }

    private func makeDictionary() throws -> DictationDictionary {
        let vocabulary = vocabularyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? []
            : vocabularyText.components(separatedBy: .newlines)
        let replacements = replacementRows.map {
            DictationDictionary.Replacement(
                source: $0.source,
                replacement: $0.replacement
            )
        }
        return try DictationDictionary(
            vocabulary: vocabulary,
            replacements: replacements
        )
    }
}

private struct ReplacementRow: Identifiable, Equatable {
    let id: UUID
    var source: String
    var replacement: String

    init(id: UUID = UUID(), source: String = "", replacement: String = "") {
        self.id = id
        self.source = source
        self.replacement = replacement
    }
}
