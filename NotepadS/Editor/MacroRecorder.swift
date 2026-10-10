import AppKit
import NotepadSCore

extension Notification.Name {
    /// Posted when macro recording starts or stops (status bars show "Recording").
    static let macroRecordingDidChange = Notification.Name("NotepadSMacroRecordingDidChange")
}

/// Edit › Macro: records what the user types and which editing commands they use, in any
/// document, and keeps the last recording for playing back (like Notepad++, one macro at a
/// time, for this run of the app).
///
/// The text view and the editor report each step with `record`; playing back is done by
/// EditorViewController, which sets `isPlaying` so the played steps aren't recorded again.
final class MacroRecorder {

    static let shared = MacroRecorder()

    private(set) var isRecording = false
    /// The last finished recording.
    private(set) var macro = Macro()
    private var recording = Macro()
    var isPlaying = false

    func startRecording() {
        recording = Macro()
        isRecording = true
        NotificationCenter.default.post(name: .macroRecordingDidChange, object: self)
    }

    func stopRecording() {
        isRecording = false
        if !recording.isEmpty {
            macro = recording   // an empty recording keeps the previous macro
        }
        NotificationCenter.default.post(name: .macroRecordingDidChange, object: self)
    }

    func record(_ step: Macro.Step) {
        guard isRecording, !isPlaying else { return }
        recording.append(step)
    }
}
