import Foundation

/// A recorded macro (Edit › Macro): what the user typed and which editing commands they used,
/// to play back later, like Notepad++'s macros.
public struct Macro: Equatable, Sendable {

    public enum Step: Equatable, Sendable {
        /// Typed text.
        case insert(String)
        /// A key command of the text view, by its action name ("moveDown:", "deleteBackward:" …).
        case keyCommand(String)
        /// Cut, copy or paste ("cut:", "copy:", "paste:").
        case clipboard(String)
        /// A Text menu transformation (`TextTransform` raw value).
        case transform(String)
        /// A command on the caret's lines ("duplicate", "delete", "moveUp", "moveDown").
        case lineCommand(String)
    }

    public private(set) var steps: [Step] = []

    public init(steps: [Step] = []) {
        self.steps = steps
    }

    public var isEmpty: Bool { steps.isEmpty }

    /// Adds a step. Typing letter by letter is stored as one piece of text, which plays back
    /// faster and as one undoable insertion.
    public mutating func append(_ step: Step) {
        if case .insert(let text) = step, case .insert(let previous)? = steps.last {
            steps[steps.count - 1] = .insert(previous + text)
        } else {
            steps.append(step)
        }
    }
}
