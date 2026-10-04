import AppKit

// NotepadS has no storyboard or XIB: the application, its delegate and the menu bar
// are created in code, so everything is visible and reviewable in Swift files.
//
// NSApplication.delegate is a weak reference, so the delegate is kept alive by this global.
let appDelegate = AppDelegate()
NSApplication.shared.delegate = appDelegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
