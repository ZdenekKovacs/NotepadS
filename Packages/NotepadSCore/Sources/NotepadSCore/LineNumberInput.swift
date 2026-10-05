import Foundation

/// Reads what the user typed into "Go to Line".
public enum LineNumberInput {

    /// The 0-based line for a 1-based line number typed by the user, or nil if the input isn't a
    /// whole number between 1 and `lineCount`. Surrounding spaces are ignored.
    public static func line(from input: String, lineCount: Int) -> Int? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        // Only ASCII digits: `Int("+5")` would accept a sign, which nobody means here.
        guard !trimmed.isEmpty, trimmed.utf8.allSatisfy({ (0x30...0x39).contains($0) }),
              let number = Int(trimmed), (1...max(lineCount, 1)).contains(number) else { return nil }
        return number - 1
    }
}
