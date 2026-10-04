import AppKit

/// Editor settings stored in UserDefaults. A Settings window will edit them in v0.4.
enum EditorDefaults {
    static let defaultFontSize: CGFloat = 13
    static let minimumFontSize: CGFloat = 8
    static let maximumFontSize: CGFloat = 48
    /// Width of a tab character, in spaces.
    static let tabWidth = 4

    private static let fontSizeKey = "EditorFontSize"

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
}
