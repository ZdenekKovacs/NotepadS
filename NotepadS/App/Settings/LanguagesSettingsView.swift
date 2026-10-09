import AppKit
import NotepadSCore
import SwiftUI
import UniformTypeIdentifiers

/// Settings › Languages: the user's own languages (like Notepad++'s User Defined Language).
/// A list on the left, the selected language's definition on the right. Every change is saved
/// at once and open documents are recolored.
struct LanguagesSettingsView: View {
    @ObservedObject private var store = UserLanguageStore.shared
    @State private var selection: UUID?
    @State private var languageToDelete: UserLanguage?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(store.languages) { language in
                        Text(language.name.isEmpty ? String(localized: "Untitled", comment: "Languages: language without a name") : language.name)
                            .tag(language.id)
                    }
                }
                .listStyle(.bordered(alternatesRowBackgrounds: false))
                HStack(spacing: 4) {
                    Button { addLanguage() } label: { Image(systemName: "plus") }
                        .help(String(localized: "Add a language", comment: "Languages button tooltip"))
                    Button { languageToDelete = selectedLanguage } label: { Image(systemName: "minus") }
                        .disabled(selectedLanguage == nil)
                        .help(String(localized: "Delete the selected language", comment: "Languages button tooltip"))
                    Spacer()
                    Menu {
                        Button(String(localized: "Import…", comment: "Languages: import from a file")) { importLanguages() }
                        Button(String(localized: "Export All…", comment: "Languages: export to a file")) { exportLanguages() }
                            .disabled(store.languages.isEmpty)
                    } label: {
                        Image(systemName: "square.and.arrow.up.on.square")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help(String(localized: "Import or export languages", comment: "Languages button tooltip"))
                }
                .buttonStyle(.borderless)
                .padding(6)
            }
            .frame(width: 180)

            Divider()

            if let index = store.languages.firstIndex(where: { $0.id == selection }) {
                UserLanguageEditor(language: $store.languages[index])
                    .id(store.languages[index].id)   // fresh text fields for another language
            } else {
                Text(String(localized: "Add a language with +, then describe its keywords, comments and strings. Files with its extensions are colored with it, also when a built-in language uses the same extension.",
                            comment: "Languages: shown when no language is selected"))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 720, height: 560)
        .onAppear {
            if selection == nil { selection = store.languages.first?.id }
        }
        .alert(String(localized: "Delete “\(languageToDelete?.name ?? "")”?", comment: "Languages: delete dialog title"),
               isPresented: Binding(get: { languageToDelete != nil }, set: { if !$0 { languageToDelete = nil } })) {
            Button(String(localized: "Delete", comment: "Languages: delete dialog button"), role: .destructive) {
                if let language = languageToDelete {
                    store.languages.removeAll { $0.id == language.id }
                    selection = store.languages.first?.id
                }
            }
            Button(String(localized: "Cancel", comment: "Dialog button"), role: .cancel) {}
        } message: {
            Text(String(localized: "Documents in this language will be colored as their extension says again.",
                        comment: "Languages: delete dialog"))
        }
    }

    private var selectedLanguage: UserLanguage? {
        store.languages.first { $0.id == selection }
    }

    private func addLanguage() {
        let language = UserLanguage(name: String(localized: "New Language", comment: "Languages: name of a new language"))
        store.languages.append(language)
        selection = language.id
    }

    // MARK: - Import and export

    /// Adds the languages in a file made with Export All; a language that is already here
    /// (same ID, e.g. exported from this Mac) is replaced by the imported version.
    private func importLanguages() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try UserLanguage.decode(Data(contentsOf: url))
            var languages = store.languages
            for language in imported {
                if let index = languages.firstIndex(where: { $0.id == language.id }) {
                    languages[index] = language
                } else {
                    languages.append(language)
                }
            }
            store.languages = languages
            selection = imported.first?.id ?? selection
        } catch {
            NSApp.presentError(error)
        }
    }

    private func exportLanguages() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = String(localized: "NotepadS Languages.json", comment: "Languages: suggested export file name")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try UserLanguage.encode(store.languages).write(to: url, options: .atomic)
        } catch {
            NSApp.presentError(error)
        }
    }
}

/// The definition of one language. Lists of words and extensions are edited as text and parsed
/// on every change; the text itself stays as typed (otherwise a space typed at the end of the
/// field would vanish at once).
private struct UserLanguageEditor: View {
    @Binding var language: UserLanguage
    @State private var extensionsText = ""
    @State private var keywordTexts: [String] = []

    var body: some View {
        Form {
            Section {
                TextField(String(localized: "Name", comment: "Languages: field"), text: $language.name)
                TextField(String(localized: "File extensions", comment: "Languages: field"), text: $extensionsText,
                          prompt: Text(verbatim: "cfg mylog"))
                    .onChange(of: extensionsText) { _, text in
                        language.fileExtensions = UserLanguage.fileExtensions(from: text)
                    }
                Toggle(String(localized: "Upper and lower case are the same (IF = if)", comment: "Languages: option"),
                       isOn: $language.ignoresCase)
                Toggle(String(localized: "Color numbers", comment: "Languages: option"), isOn: $language.highlightsNumbers)
            }
            Section(String(localized: "Comments and Strings", comment: "Languages: section")) {
                TextField(String(localized: "Line comment", comment: "Languages: field"), text: $language.lineComment,
                          prompt: Text(verbatim: "#"))
                TextField(String(localized: "Block comment start", comment: "Languages: field"), text: $language.blockCommentStart,
                          prompt: Text(verbatim: "/*"))
                TextField(String(localized: "Block comment end", comment: "Languages: field"), text: $language.blockCommentEnd,
                          prompt: Text(verbatim: "*/"))
                TextField(String(localized: "String quotes", comment: "Languages: field"), text: $language.stringDelimiters,
                          prompt: Text(verbatim: "\" '"))
                TextField(String(localized: "Escape character", comment: "Languages: field"), text: $language.escapeCharacter,
                          prompt: Text(verbatim: "\\"))
            }
            Section(String(localized: "Keywords", comment: "Languages: section")) {
                ForEach(keywordTexts.indices, id: \.self) { index in
                    keywordGroup(index)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loadTexts)
    }

    @ViewBuilder
    private func keywordGroup(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker(selection: $language.keywordGroups[index].scope) {
                ForEach(UserLanguage.keywordScopes, id: \.self) { scope in
                    Text(Self.name(of: scope)).tag(scope)
                }
            } label: {
                // The color itself, next to the group: menus show their items without colors.
                HStack(spacing: 6) {
                    Text(String(localized: "Group \(index + 1)", comment: "Languages: keyword group, followed by its color"))
                    Circle()
                        .fill(Color(nsColor: SyntaxTheme.color(for: language.keywordGroups[index].scope)))
                        .frame(width: 10, height: 10)
                }
            }
            TextEditor(text: $keywordTexts[index])
                .font(.system(.body, design: .monospaced))
                .frame(height: 54)
                .onChange(of: keywordTexts[index]) { _, text in
                    language.keywordGroups[index].words = UserLanguage.words(from: text)
                }
        }
    }

    private func loadTexts() {
        extensionsText = language.fileExtensions.joined(separator: " ")
        // Always the full number of groups, also for a file from an older version with fewer.
        while language.keywordGroups.count < UserLanguage.keywordGroupCount {
            language.keywordGroups.append(.init(scope: UserLanguage.keywordScopes[language.keywordGroups.count]))
        }
        keywordTexts = language.keywordGroups.map { $0.words.joined(separator: " ") }
    }

    private static func name(of scope: SyntaxScope) -> String {
        switch scope {
        // Named like the built-in languages use the colors; the last two only by their color.
        case .keyword: return String(localized: "Purple, like keywords", comment: "Languages: color of a keyword group")
        case .constant: return String(localized: "Indigo, like constants", comment: "Languages: color of a keyword group")
        case .function: return String(localized: "Teal, like functions", comment: "Languages: color of a keyword group")
        case .strong: return String(localized: "Orange", comment: "Languages: color of a keyword group")
        case .variable: return String(localized: "Cyan, like variables", comment: "Languages: color of a keyword group")
        case .emphasis: return String(localized: "Pink", comment: "Languages: color of a keyword group")
        default: return scope.rawValue
        }
    }
}
