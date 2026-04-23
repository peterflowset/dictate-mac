import SwiftUI
import UserNotifications

struct MenuBarView: View {
    @EnvironmentObject var manager: DictateManager
    @State private var page: MenuBarPage = .main
    @State private var showingVocabEditor = false
    @State private var showingApiKeyEditor = false
    @State private var newTerm = ""

    var body: some View {
        Group {
            switch page {
            case .main:
                MainMenuContent(
                    manager: manager,
                    showHistory: { page = .history },
                    showVocabulary: { page = .vocabulary },
                    showApiKeyEditor: { showingApiKeyEditor = true }
                )
            case .history:
                HistoryMenuPage(
                    manager: manager,
                    goBack: { page = .main },
                    copyEntry: copyHistoryEntry
                )
            case .vocabulary:
                VocabularyMenuPage(
                    manager: manager,
                    newTerm: $newTerm,
                    goBack: { page = .main },
                    showVocabEditor: { showingVocabEditor = true }
                )
            }
        }
        .frame(width: page == .main ? 280 : 360)
        .sheet(isPresented: $showingVocabEditor) {
            VocabularyEditorView(manager: manager)
        }
        .sheet(isPresented: $showingApiKeyEditor) {
            ApiKeyEditorView(manager: manager)
        }
    }

    private func copyHistoryEntry(_ entry: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry, forType: .string)
        showNotification(title: "Copied", body: String(entry.prefix(50)))
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

private enum MenuBarPage {
    case main
    case history
    case vocabulary
}

private struct MainMenuContent: View {
    @ObservedObject var manager: DictateManager
    let showHistory: () -> Void
    let showVocabulary: () -> Void
    let showApiKeyEditor: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
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

            MenuPageButton(
                title: "History",
                subtitle: manager.history.isEmpty ? "No transcriptions yet" : latestHistoryPreview,
                count: manager.history.count,
                systemImage: "clock.arrow.circlepath",
                action: showHistory
            )

            Divider()

            MenuPageButton(
                title: "Vocabulary",
                subtitle: manager.vocabulary.isEmpty ? "No terms added" : vocabularyPreview,
                count: manager.vocabulary.count,
                systemImage: "text.book.closed",
                action: showVocabulary
            )

            Divider()

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

            Picker("Hotkey", selection: $manager.hotkey) {
                ForEach(DictationHotkey.allCases, id: \.self) { hotkey in
                    Text(hotkey.label).tag(hotkey)
                }
            }
            .pickerStyle(.menu)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)

            Divider()

            HStack {
                Image(systemName: manager.hasApiKey ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(manager.hasApiKey ? .green : .orange)
                Text(manager.hasApiKey ? "API Key configured" : "GROQ_API_KEY missing")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button(manager.hasApiKey ? "Change" : "Set", action: showApiKeyEditor)
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
    }

    private var latestHistoryPreview: String {
        guard let latest = manager.history.first else { return "No transcriptions yet" }
        return String(latest.prefix(46)) + (latest.count > 46 ? "..." : "")
    }

    private var vocabularyPreview: String {
        let terms = manager.vocabulary.prefix(3).joined(separator: ", ")
        return terms + (manager.vocabulary.count > 3 ? "..." : "")
    }
}

private struct HistoryMenuPage: View {
    @ObservedObject var manager: DictateManager
    let goBack: () -> Void
    let copyEntry: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuPageHeader(title: "History", count: manager.history.count, goBack: goBack)

            Divider()

            if manager.history.isEmpty {
                EmptyStateView(systemImage: "clock", text: "No transcriptions yet")
                    .frame(height: 260)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(manager.history.indices, id: \.self) { index in
                            let entry = manager.history[index]
                            Button {
                                copyEntry(entry)
                            } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "doc.on.doc")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .frame(width: 16)

                                    Text(entry)
                                        .font(.callout)
                                        .lineLimit(4)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(8)
                                .background(Color.secondary.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .help("Copy transcription")
                        }
                    }
                    .padding(12)
                }
                .frame(height: 320)
            }
        }
    }
}

private struct VocabularyMenuPage: View {
    @ObservedObject var manager: DictateManager
    @Binding var newTerm: String
    let goBack: () -> Void
    let showVocabEditor: () -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 104), spacing: 8, alignment: .top)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuPageHeader(title: "Vocabulary", count: manager.vocabulary.count, goBack: goBack)

            Divider()

            HStack(spacing: 8) {
                TextField("Add term...", text: $newTerm)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTerm)

                Button(action: addTerm) {
                    Image(systemName: "plus.circle.fill")
                        .imageScale(.large)
                }
                .buttonStyle(.plain)
                .disabled(!canAddTerm)
                .help("Add term")
            }
            .padding(12)

            if manager.vocabulary.isEmpty {
                EmptyStateView(systemImage: "text.book.closed", text: "No terms added")
                    .frame(height: 220)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                        ForEach(manager.vocabulary, id: \.self) { term in
                            HStack(spacing: 6) {
                                Text(term)
                                    .font(.callout)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Button {
                                    manager.removeTerm(term)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Remove term")
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
                .frame(height: 300)
            }

            Divider()

            Button("Edit All...", action: showVocabEditor)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
    }

    private var canAddTerm: Bool {
        !newTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func addTerm() {
        guard canAddTerm else { return }
        manager.addTerm(newTerm)
        newTerm = ""
    }
}

private struct MenuPageButton: View {
    let title: String
    let subtitle: String
    let count: Int
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundColor(.secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                    Text(subtitle)
                        .foregroundColor(.secondary)
                        .font(.caption)
                        .lineLimit(1)
                }

                Spacer()

                Text("\(count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

private struct MenuPageHeader: View {
    let title: String
    let count: Int
    let goBack: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: goBack) {
                Image(systemName: "chevron.left")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help("Back")

            Text(title)
                .font(.headline)

            Spacer()

            Text("\(count)")
                .font(.caption)
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

private struct EmptyStateView: View {
    let systemImage: String
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundColor(.secondary)

            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
