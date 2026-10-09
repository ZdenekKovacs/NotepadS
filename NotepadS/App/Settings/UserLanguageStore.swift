import AppKit
import Combine
import NotepadSCore

extension Notification.Name {
    /// Posted by `UserLanguageStore` after the user added, changed or removed a language.
    static let userLanguagesDidChange = Notification.Name("NotepadSUserLanguagesDidChange")
}

/// The user-defined languages (Settings › Languages), saved as JSON in the app's Application
/// Support folder (inside the sandbox container). Not in UserDefaults: they are the user's
/// work, so Restore Defaults keeps them, and the same file format is used for Export/Import.
final class UserLanguageStore: ObservableObject {

    static let shared = UserLanguageStore()

    /// Every change is saved at once and announced with `.userLanguagesDidChange`, so open
    /// editors, the status bar menus and the Open/Save panels follow.
    @Published var languages: [UserLanguage] {
        didSet {
            guard languages != oldValue else { return }
            save()
            NotificationCenter.default.post(name: .userLanguagesDidChange, object: self)
        }
    }

    private init() {
        languages = (try? Data(contentsOf: Self.fileURL)).flatMap { try? UserLanguage.decode($0) } ?? []
    }

    /// ~/Library/Containers/<bundle id>/Data/Library/Application Support/NotepadS/UserLanguages.json
    private static var fileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("NotepadS", isDirectory: true)
            .appendingPathComponent("UserLanguages.json")
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: Self.fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try UserLanguage.encode(languages).write(to: Self.fileURL, options: .atomic)
        } catch {
            NSApp.presentError(error)
        }
    }
}
