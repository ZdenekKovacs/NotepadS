import AppKit
import NotepadSCore

/// Colors for syntax highlighting.
///
/// Only system colors: each one has a light and a dark variant and AppKit picks the right one
/// every time it draws, so the colors follow Light/Dark mode live, without any code here.
/// Keywords and strings get clearly different hues (purple and red), as they often sit side by side.
enum SyntaxTheme {
    static func color(for scope: SyntaxScope) -> NSColor {
        switch scope {
        case .comment: return .systemGray
        case .string: return .systemRed
        case .stringEscape: return .systemOrange
        case .number: return .systemBlue
        case .keyword: return .systemPurple
        case .constant: return .systemIndigo
        case .property: return .systemTeal
        case .variable: return .systemCyan
        case .function: return .systemTeal
        case .operator: return .secondaryLabelColor
        case .heading: return .systemBlue
        case .emphasis: return .systemPink
        case .strong: return .systemOrange
        case .code: return .systemBrown
        case .link: return .linkColor
        }
    }
}
