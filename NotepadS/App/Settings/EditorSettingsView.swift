import AppKit
import SwiftUI

/// Settings › Editor. Every control writes straight to UserDefaults (`@AppStorage`); open
/// editors follow font and tab-width changes immediately.
struct EditorSettingsView: View {
    @AppStorage(EditorDefaults.Key.fontName) private var fontName = ""
    @AppStorage(EditorDefaults.Key.fontSize) private var fontSize = Double(EditorDefaults.defaultFontSize)
    @AppStorage(EditorDefaults.Key.tabWidth) private var tabWidth = 4
    @AppStorage(EditorDefaults.Key.insertsSpacesForTab) private var insertsSpacesForTab = false
    @AppStorage(EditorDefaults.Key.autoIndents) private var autoIndents = true
    @AppStorage(EditorDefaults.Key.wrapsLines) private var wrapsLines = true

    @State private var isConfirmingRestore = false

    /// Installed fixed-width fonts (PostScript name and display name), read once.
    private let monospacedFonts: [(name: String, displayName: String)] = EditorSettingsView.loadMonospacedFonts()

    var body: some View {
        Form {
            Section(String(localized: "Font", comment: "Settings section")) {
                Picker(String(localized: "Font", comment: "Settings: font picker"), selection: $fontName) {
                    Text(String(localized: "System Monospaced", comment: "Settings: the default font (SF Mono)")).tag("")
                    ForEach(monospacedFonts, id: \.name) { font in
                        Text(font.displayName).tag(font.name)
                    }
                }
                Stepper(value: $fontSize, in: Double(EditorDefaults.minimumFontSize)...Double(EditorDefaults.maximumFontSize),
                        step: 1) {
                    Text(String(localized: "Size: \(Int(fontSize)) pt", comment: "Settings: font size"))
                }
            }
            Section(String(localized: "Indentation", comment: "Settings section")) {
                Stepper(value: $tabWidth, in: EditorDefaults.tabWidthRange) {
                    Text(String(localized: "Tab width: \(tabWidth) spaces", comment: "Settings"))
                }
                Toggle(String(localized: "Insert spaces when pressing Tab", comment: "Settings"), isOn: $insertsSpacesForTab)
                Toggle(String(localized: "Keep indentation on new lines", comment: "Settings: auto-indent"), isOn: $autoIndents)
            }
            Section(String(localized: "New Windows", comment: "Settings section")) {
                Toggle(String(localized: "Wrap lines", comment: "Settings: word wrap default"), isOn: $wrapsLines)
            }
            Section {
                HStack {
                    Spacer()
                    Button(String(localized: "Restore Defaults…", comment: "Settings button")) {
                        isConfirmingRestore = true
                    }
                }
            }
        }
        .alert(String(localized: "Restore all settings to their defaults?", comment: "Restore Defaults dialog title"),
               isPresented: $isConfirmingRestore) {
            Button(String(localized: "Restore Defaults", comment: "Restore Defaults dialog button"), role: .destructive) {
                EditorDefaults.restoreAll()
            }
            Button(String(localized: "Cancel", comment: "Dialog button"), role: .cancel) {}
        } message: {
            Text(String(localized: "Font, indentation, wrapping, the minimap, invisible characters, the tab bar, panel options and window positions go back to how they were when NotepadS was new. Your documents and your own languages stay.",
                        comment: "Restore Defaults dialog"))
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
    }

    private static func loadMonospacedFonts() -> [(name: String, displayName: String)] {
        let manager = NSFontManager.shared
        return (manager.availableFontNames(with: .fixedPitchFontMask) ?? [])
            .compactMap { name -> (String, String)? in
                // Only the regular style of each family: bold and italic make poor editor fonts.
                guard let font = NSFont(name: name, size: 13) else { return nil }
                let traits = manager.traits(of: font)
                guard !traits.contains(.boldFontMask), !traits.contains(.italicFontMask) else { return nil }
                return (name, font.displayName ?? name)
            }
            .sorted { $0.1.localizedStandardCompare($1.1) == .orderedAscending }
    }
}
