import AppKit

/// Editor settings stored in UserDefaults. A Settings window will edit them in v0.4.
enum EditorDefaults {
    static let defaultFontSize: CGFloat = 13
    static let minimumFontSize: CGFloat = 8
    static let maximumFontSize: CGFloat = 48
    /// Width of a tab character, in spaces.
    static let tabWidth = 4

    private static let fontSizeKey = "EditorFontSize"
    private static let wrapsLinesKey = "EditorWrapsLines"
    private static let showsInvisiblesKey = "EditorShowsInvisibles"

    /// Font size for new windows: the size the user chose last.
    static var fontSize: CGFloat {
        get {
            let stored = UserDefaults.standard.double(forKey: fontSizeKey)
            return stored > 0 ? CGFloat(stored) : defaultFontSize
        }
        set {
            UserDefaults.standard.set(Double(newValue), forKey: fontSizeKey)
        }
    }

    /// Word wrap for new windows: the user's last choice, on by default.
    static var wrapsLines: Bool {
        get { UserDefaults.standard.object(forKey: wrapsLinesKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: wrapsLinesKey) }
    }

    /// Invisible-character marks for new windows: the user's last choice, off by default.
    static var showsInvisibles: Bool {
        get { UserDefaults.standard.bool(forKey: showsInvisiblesKey) }
        set { UserDefaults.standard.set(newValue, forKey: showsInvisiblesKey) }
    }
}
