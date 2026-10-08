import Foundation
import NotepadSCore

/// Keeps a character count (`TextStatistics`) of the start of a text that keeps changing, for
/// the status bar: the whole document for "Characters", the text before the caret for "Pos".
///
/// Counting is O(n). Short texts are counted right away, so the number follows every keystroke.
/// Long ones are counted on a background copy so typing never waits; while the text keeps
/// changing, a new count starts as soon as the previous one finishes, so the number follows
/// with a short delay. Main thread only.
final class LiveCharacterCounter {

    /// The last count; `nil` until the first one is done.
    private(set) var count: Int?

    /// Returns the text and how many UTF-16 units from its start to count. Called on the main thread.
    private let source: () -> (text: NSString, length: Int)
    /// Called when a background count has finished, so the status bar can show the new `count`.
    private let didCountInBackground: () -> Void

    /// Up to this length (UTF-16 units) the count is done right away: 50 000 mostly-ASCII
    /// characters take well under a millisecond.
    private let immediateLimit = 50_000
    /// Increases with every count started; a background count for an older text is thrown away.
    private var generation = 0
    /// True while a background count runs.
    private var isCountingInBackground = false
    /// The text changed while the background count was running: count again when it is done.
    private var isOutdated = false

    init(source: @escaping () -> (text: NSString, length: Int), didCountInBackground: @escaping () -> Void) {
        self.source = source
        self.didCountInBackground = didCountInBackground
    }

    /// Counts again. When this returns, `count` is up to date for short texts; for long ones it
    /// still holds the previous value until `didCountInBackground` is called.
    func recount() {
        let (text, length) = source()
        let range = NSRange(location: 0, length: min(length, text.length))
        if range.length <= immediateLimit {
            generation += 1   // a background count still running is outdated now
            isOutdated = false
            count = TextStatistics.characterCount(of: text, in: range)
            return
        }
        guard !isCountingInBackground else {
            isOutdated = true   // counted again when the running count finishes
            return
        }
        isCountingInBackground = true
        isOutdated = false
        generation += 1
        let generation = self.generation
        // The text storage may only be touched on the main thread and keeps changing while
        // the user types, so count an immutable copy. Copying is a fast memory copy.
        let snapshot = text.substring(with: range) as NSString
        DispatchQueue.global(qos: .userInitiated).async {
            let count = TextStatistics.characterCount(of: snapshot, in: NSRange(location: 0, length: snapshot.length))
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isCountingInBackground = false
                if generation == self.generation {
                    self.count = count
                }
                if self.isOutdated {
                    self.recount()
                }
                self.didCountInBackground()
            }
        }
    }
}
