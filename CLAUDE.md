# NotepadS — instructions for AI-assisted development

Read this file before every task. Reasoning and full specs: `docs/DESIGN.md`.

## Purpose

A fast, native macOS plain-text editor: a lighter Notepad++ with developer utilities.
Opens and saves any file, detects encodings, preserves line endings byte for byte, never loses text.
For English-speaking users: English UI, every user-facing string localizable (`String(localized:)`, String Catalog,
English only for now); legacy encodings are Western (Windows-1252, ISO 8859-1).
The developer is new to Swift/AppKit: code must be readable and explain *why* where AppKit is non-obvious.

## Current state

The phase 1 code is a **draft that has never been compiled**, and it predates four decisions
(line breaks preserved as on disk, encodability dialog, menu bar from a XIB without private API,
local signing). **Start with Phase 0** — `docs/DESIGN.md` §4 (tasks) and §5 (per-file change list).
Where the code and `docs/DESIGN.md` disagree, the document wins.

## Build, run, test

```sh
swift test --package-path Packages/NotepadSCore          # Core logic — run first, fastest feedback
xcodegen generate                                        # after adding/removing/renaming files
xcodebuild -project NotepadS.xcodeproj -scheme NotepadS -configuration Debug \
           -destination 'platform=macOS' -derivedDataPath ~/Library/Developer/Xcode/DerivedData/NotepadS build
open ~/Library/Developer/Xcode/DerivedData/NotepadS/Build/Products/Debug/NotepadS.app
log stream --predicate 'process == "NotepadS"' --level error   # runtime errors while testing
```

- `NotepadS.xcodeproj` is generated and git-ignored. Never edit it; change `project.yml`.
- Build products go to `~/Library/Developer/Xcode/DerivedData/NotepadS`, not into the project folder:
  the folder is on the iCloud-synced Desktop, which adds Finder metadata to the `.app` and makes code signing fail
  ("resource fork, Finder information, or similar detritus not allowed").
- No paid Apple Developer account yet: builds are signed locally (ad-hoc, no team). The sandbox stays on.
- You can't see the app's window. After UI-related changes, list the manual checks from
  `docs/DESIGN.md` §4 the developer should click through.

## Architecture (summary)

- **AppKit, `NSDocument`-based.** Views and logic in code. The menu bar comes from `App/MainMenu.xib`
  (Xcode template) and is adjusted in `App/MainMenu.swift`.
- **`TextDocument`** (NSDocument) owns the `NSTextStorage`, `encoding` and `lineEnding`
  (the style for newly inserted line breaks). Autosave in place is on.
- **`EditorViewController`** builds the TextKit 1 stack (storage → `NSLayoutManager` → `NSTextContainer`
  → `EditorTextView`), the gutter (`LineNumberRulerView`) and `StatusBarView`, keeps `LineIndex` current,
  and is the **edit gatekeeper** (line-break style of inserted text, encodability dialog).
- **`NotepadSCore`** (local Swift package): encodings, detection, line endings, `LineIndex`;
  later grammars, highlighter, text transformations. Foundation only, fully unit-tested, reusable on iOS.

## Invariants — never break these

1. **Line breaks are stored exactly as in the file** (`\n`, `\r\n`, `\r`, possibly mixed), and saving
   writes them unchanged. Breaks the editor *inserts* (Enter, paste, drop, transformations) use
   `document.lineEnding`. Only the explicit Convert Line Endings command rewrites existing breaks —
   as one undoable edit. Never split text with `components(separatedBy: "\n")`; use `LineIndex` or a
   Core helper that understands all three styles. Check for `\r` on bytes (`utf8`), not `Character`s:
   in Swift `"\r\n"` is one `Character`.
2. **Every character in the document can be represented in its encoding.** Unencodable input opens
   the dialog *"[Convert to UTF-8 and Insert] / [Cancel]"*; nothing is inserted before the user decides.
   Encoding conversion is checked first. Therefore saving/autosaving never fails or replaces characters.
3. **TextKit 1 only.** Never create a text view with `NSTextView(frame:)`, `NSTextView()` or
   `scrollableTextView()` (TextKit 2). Never use `textLayoutManager` / `NSTextLayoutManager`.
4. **No AppKit/UIKit/SwiftUI in `NotepadSCore`.** Foundation (and CryptoKit for hashes) only.
5. **Every user-visible change is undoable as one step**: `breakUndoCoalescing()`, then
   `shouldChangeText(in:replacementString:)` → change → `didChangeText()`, plus an undo action name.
   Changes touching document state *and* text go in one undo group.
6. **Programmatic loads are not edits**: change the storage directly (no undo, no "edited" state),
   as `TextDocument.read` does.
7. **Hot paths don't copy the whole text**: use `textStorage.mutableString`, not `textStorage.string`,
   in per-keystroke code.
8. **No private API**, ever (App Review guideline 2.5.1). No `NSSelectorFromString("_…")`, no
   undocumented keys or classes.

## Coding conventions

- Swift 5 language mode, minimal concurrency checking (for now). AppKit code runs on the main thread.
- Small types, one main type per file, `final class` by default, `private` unless needed elsewhere.
- Clear names over abbreviations. No force unwraps unless AppKit guarantees the value (comment why).
- Comments explain *why*, especially AppKit behaviour. `///` doc comments on non-trivial types and functions.
- **Every user-facing string is localizable**: `String(localized: "…", comment: "…")` (in `NotepadSCore` add
  `bundle: .module`). Use interpolation inside the localized string; never concatenate translated pieces.
  Strings live in String Catalogs (`NotepadS/Resources/Localizable.xcstrings`, and `Resources/` in the package),
  English only for now. After adding strings and building from the command line, run `scripts/sync-strings.sh`.
- User-facing errors conform to `LocalizedError` (`errorDescription`, `recoverySuggestion`), so
  `NSAlert(error:)` shows them.
- Semantic system colors only (`.textColor`, `.textBackgroundColor`, …) so Light/Dark mode works.
- Our own menu actions are `@objc` methods on the responder that owns the state.

## Rules for AI-assisted changes

- **Small diffs.** One task at a time; after each change the app builds and the Core tests pass.
  Commit after each green step.
- **Fix compiler errors at their cause**, not by deleting functionality or adding force casts.
  If an API doesn't exist in the SDK, find the documented replacement and say what changed.
- **Pure logic goes into `NotepadSCore` with unit tests in the same change.** Text utilities: tests first,
  including invalid input, CRLF/CR/mixed line breaks and non-ASCII text (accented letters, emoji).
- **No new dependencies** (packages, frameworks, tools) without explicit approval.
- **Don't touch unrelated code**; no drive-by refactors or reformatting.
- **Explain non-obvious AppKit behaviour** in a short comment and in the reply.
- If a requirement conflicts with an invariant or `docs/DESIGN.md`, stop and ask instead of choosing.
- New files: put them in the right folder and re-run `xcodegen generate`.
- XIB files are created or edited by the developer in Xcode, not hand-written.
- Before finishing: build, run the Core tests, and list the manual acceptance checks the change affects.

## Phase checklist

### Phase 0 — build and align (first task)
- [x] 0.1 Core compiles, `swift test` green
- [x] 0.2 App compiles with local ad-hoc signing and launches
- [x] 0.3 Line breaks preserved as on disk (Core + app), Convert Line Endings, tests
- [x] 0.4 Encodability dialog ("Convert to UTF-8 and Insert" / "Cancel")
- [x] 0.5 Menu bar from `MainMenu.xib`, private API removed

### Phase 1 — MVP acceptance (manual checks in DESIGN.md §4)
- [x] 1.1 Skeleton and menu bar
- [x] 1.2 Plain-text view, smart features off
- [x] 1.3 Core tests
- [x] 1.4 Open/save any extension, hidden files, binary/size guard, byte-exact saves
- [x] 1.5 Edit gatekeeper
- [x] 1.6 Autosave + restore (⌘Q, crash, restart, "close windows" setting on)
- [x] 1.7 Font, ⌘+ / ⌘− / ⌘0
- [x] 1.8 Line-number gutter
- [x] 1.9 Status bar: Ln/Col, selection, encoding (reopen/convert), line endings (mixed, convert)
- [x] 1.10 Find bar, native tabs, external-change handling

### Phase 2 — v0.2
- [ ] Grammar model + highlighter with per-line state (Core, tested)
- [ ] Temporary-attribute highlighting, debounced, size/long-line thresholds
- [ ] JSON, Python, Shell, Markdown; detection by extension + shebang; status-bar override
- [ ] Light/dark syntax themes
- [ ] Word wrap toggle, invisible characters, Go to Line (⌘L), caret restore

### Phase 3 — v0.3
- [ ] Transformation framework (selection or document, one undo step, errors with line)
- [ ] JSON prettify/minify (token-based, order-preserving)
- [ ] Base64, URL encode/decode
- [ ] SHA-256 / SHA-1 / MD5 (replace or copy)
- [ ] Case conversions
- [ ] Sort, dedupe, trim trailing whitespace

### Phase 4 — v0.4
- [ ] YAML, JS/TS, C/C++, HTML/XML grammars
- [ ] Regex find/replace panel
- [ ] SwiftUI Settings (font, tab width, tabs vs spaces, wrap default), auto-indent
- [ ] Printing, app icon

### Later
- [ ] iOS app on `NotepadSCore`
- [ ] `.editorconfig`, Swift 6 language mode
- [ ] Distribution (after buying the Apple Developer account)
