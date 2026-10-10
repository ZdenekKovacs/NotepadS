import AppKit

/// Editor settings stored in UserDefaults, edited in the Settings window.
enum EditorDefaults {
    static let defaultFontSize: CGFloat = 13
    static let minimumFontSize: CGFloat = 8
    static let maximumFontSize: CGFloat = 48
    static let tabWidthRange = 1...16

    /// UserDefaults keys; the Settings window binds to the same keys with `@AppStorage`.
    enum Key {
        static let fontSize = "EditorFontSize"
        /// PostScript name of a monospaced font; empty means the system's monospaced font.
        static let fontName = "EditorFontName"
        static let tabWidth = "EditorTabWidth"
        static let insertsSpacesForTab = "EditorInsertsSpacesForTab"
        static let autoIndents = "EditorAutoIndents"
        static let wrapsLines = "EditorWrapsLines"
        static let showsInvisibles = "EditorShowsInvisibles"
        static let showsMinimap = "EditorShowsMinimap"
        static let showsFunctionList = "EditorShowsFunctionList"
    }

    private static var defaults: UserDefaults { .standard }

    /// Font size for new windows: the size the user chose last.
    static var fontSize: CGFloat {
        get {
            let stored = defaults.double(forKey: Key.fontSize)
            return stored > 0 ? CGFloat(stored) : defaultFontSize
        }
        set {
            defaults.set(Double(newValue), forKey: Key.fontSize)
        }
    }

    static var fontName: String {
        defaults.string(forKey: Key.fontName) ?? ""
    }

    /// The editor font at `size`: the chosen font, or the system's monospaced font (SF Mono).
    static func font(ofSize size: CGFloat) -> NSFont {
        if !fontName.isEmpty, let font = NSFont(name: fontName, size: size) {
            return font
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// Width of a tab character, in spaces.
    static var tabWidth: Int {
        let stored = defaults.integer(forKey: Key.tabWidth)
        return tabWidthRange.contains(stored) ? stored : 4
    }

    /// Tab key inserts spaces up to the next tab stop instead of a tab character.
    static var insertsSpacesForTab: Bool {
        defaults.bool(forKey: Key.insertsSpacesForTab)
    }

    /// Enter keeps the indentation of the current line.
    static var autoIndents: Bool {
        defaults.object(forKey: Key.autoIndents) as? Bool ?? true
    }

    /// Word wrap for new windows: the user's last choice, on by default.
    static var wrapsLines: Bool {
        get { defaults.object(forKey: Key.wrapsLines) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.wrapsLines) }
    }

    /// Invisible-character marks for new windows: the user's last choice, off by default.
    static var showsInvisibles: Bool {
        get { defaults.bool(forKey: Key.showsInvisibles) }
        set { defaults.set(newValue, forKey: Key.showsInvisibles) }
    }

    /// Minimap beside the text for new windows: the user's last choice, on by default.
    static var showsMinimap: Bool {
        get { defaults.object(forKey: Key.showsMinimap) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.showsMinimap) }
    }

    /// Function list beside the text for new windows: the user's last choice, off by default.
    static var showsFunctionList: Bool {
        get { defaults.bool(forKey: Key.showsFunctionList) }
        set { defaults.set(newValue, forKey: Key.showsFunctionList) }
    }

    /// Settings › Restore Defaults: forgets every setting and everything the app remembered
    /// (font, tab width, toggles, the Open panel filter, the Find panel options, window and
    /// panel positions). Open documents and user-defined languages are not settings and stay;
    /// open windows keep their current wrap, minimap and invisibles until closed, while the
    /// font changes at once (editors follow UserDefaults).
    static func restoreAll() {
        // All of the app's settings live in its own defaults domain (inside the sandbox container).
        guard let domain = Bundle.main.bundleIdentifier else { return }
        defaults.removePersistentDomain(forName: domain)
        AppDelegate.setFixedDefaults()
    }
}
