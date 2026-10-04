import AppKit

// The application delegate is created in code. NSApplicationMain then loads the menu bar from
// MainMenu.xib (NSMainNibFile in Info.plist); MainMenu.swift adjusts it.
//
// NSApplication.delegate is a weak reference, so the delegate is kept alive by this global.
let appDelegate = AppDelegate()
NSApplication.shared.delegate = appDelegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
