import SwiftUI
import UserNotifications

struct MenuBarView: View {
    @EnvironmentObject var manager: DictateManager
    @State private var showingVocabEditor = false
    @State private var showingApiKeyEditor = false
    @State private var newTerm = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Status
            HStack {
                Image(systemName: manager.statusIcon)
                    .foregroundColor(manager.isRecording ? .red : .secondary)
                Text(manager.statusText)
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // History Section
            DisclosureGroup("History (\(manager.history.count))") {
                if manager.history.isEmpty {
                    Text("No transcriptions yet")
                        .foregroundColor(.secondary)
                        .font(.caption)
                        .padding(.leading, 8)
                } else {
                    ForEach(manager.history, id: \.self) { entry in
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(entry, forType: .string)
                            showNotification(title: "Copied", body: String(entry.prefix(50)))
                        } label: {
                            Text(entry.prefix(40) + (entry.count > 40 ? "…" : ""))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 2)
                        .padding(.leading, 8)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            // Vocabulary Section
            DisclosureGroup("Vocabulary (\(manager.vocabulary.count))") {
                if manager.vocabulary.isEmpty {
                    Text("No terms added")
                        .foregroundColor(.secondary)
                        .font(.caption)
                        .padding(.leading, 8)
                } else {
                    ForEach(manager.vocabulary, id: \.self) { term in
                        HStack {
                            Text(term)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button {
                                manager.removeTerm(term)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 2)
                        .padding(.leading, 8)
                    }
                }

                Divider().padding(.vertical, 4)

                HStack {
                    TextField("Add term…", text: $newTerm)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            if !newTerm.isEmpty {
                                manager.addTerm(newTerm)
                                newTerm = ""
                            }
                        }
                    Button("Add") {
                        if !newTerm.isEmpty {
                            manager.addTerm(newTerm)
                            newTerm = ""
                        }
                    }
                    .disabled(newTerm.isEmpty)
                }
                .padding(.leading, 8)

                Button("Edit All…") {
                    showingVocabEditor = true
                }
                .padding(.leading, 8)
                .padding(.top, 4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            // Settings
            Toggle("Auto-Correct", isOn: $manager.autoCorrect)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)

            Toggle("Save to Clipboard", isOn: $manager.saveToClipboard)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)

            Picker("Language", selection: $manager.language) {
                Text("Auto").tag(Language.auto)
                Text("Deutsch").tag(Language.de)
                Text("English").tag(Language.en)
            }
            .pickerStyle(.menu)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            Divider()

            // API Key Status
            HStack {
                Image(systemName: manager.hasApiKey ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(manager.hasApiKey ? .green : .orange)
                Text(manager.hasApiKey ? "API Key configured" : "GROQ_API_KEY missing")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button(manager.hasApiKey ? "Change" : "Set") {
                    showingApiKeyEditor = true
                }
                .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            Divider()

            Button("Quit Dictate") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 280)
        .sheet(isPresented: $showingVocabEditor) {
            VocabularyEditorView(manager: manager)
        }
        .sheet(isPresented: $showingApiKeyEditor) {
            ApiKeyEditorView(manager: manager)
        }
    }

    private func showNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}

struct VocabularyEditorView: View {
    @ObservedObject var manager: DictateManager
    @Environment(\.dismiss) var dismiss
    @State private var text: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Vocabulary")
                .font(.headline)

            Text("Enter comma-separated terms. Used for Whisper context and Auto-Correct.")
                .font(.caption)
                .foregroundColor(.secondary)

            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 100)
                .border(Color.gray.opacity(0.3))

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    let terms = text
                        .replacingOccurrences(of: "\n", with: ",")
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                    manager.setVocabulary(terms)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 400, height: 250)
        .onAppear {
            text = manager.vocabulary.joined(separator: ", ")
        }
    }
}

struct ApiKeyEditorView: View {
    @ObservedObject var manager: DictateManager
    @Environment(\.dismiss) var dismiss
    @State private var apiKey: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Groq API Key")
                .font(.headline)

            Text("Get a free key at console.groq.com/keys")
                .font(.caption)
                .foregroundColor(.secondary)

            SecureField("API Key", text: $apiKey)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    manager.setApiKey(apiKey)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(apiKey.isEmpty)
            }
        }
        .padding()
        .frame(width: 350, height: 150)
    }
}

#Preview {
    MenuBarView()
        .environmentObject(DictateManager())
}
