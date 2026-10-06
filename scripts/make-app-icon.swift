// Draws the app icon and writes the AppIcon asset catalog images.
//   swift scripts/make-app-icon.swift
// The design: a blue rounded square (macOS icon grid: 824 of 1024 points) with a white sheet
// of paper, a folded corner, a few "code" lines and a pair of braces.
import AppKit

let outputFolder = "NotepadS/Resources/Assets.xcassets/AppIcon.appiconset"

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let pixels = Int(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = size / 1024
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()

    // Background: rounded square with a vertical blue gradient and a soft shadow.
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.shadowBlurRadius = 24
    shadow.set()
    NSColor(calibratedRed: 0.10, green: 0.38, blue: 0.86, alpha: 1).setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(calibratedRed: 0.24, green: 0.60, blue: 1.00, alpha: 1),
               ending: NSColor(calibratedRed: 0.08, green: 0.30, blue: 0.78, alpha: 1))!
        .draw(in: tilePath, angle: -90)

    // Sheet of paper with a folded top-right corner.
    let sheet = NSBezierPath()
    sheet.move(to: NSPoint(x: 290, y: 220))
    sheet.line(to: NSPoint(x: 734, y: 220))
    sheet.line(to: NSPoint(x: 734, y: 690))
    sheet.line(to: NSPoint(x: 624, y: 800))
    sheet.line(to: NSPoint(x: 290, y: 800))
    sheet.close()
    NSColor.white.setFill()
    sheet.fill()
    let fold = NSBezierPath()
    fold.move(to: NSPoint(x: 624, y: 800))
    fold.line(to: NSPoint(x: 624, y: 690))
    fold.line(to: NSPoint(x: 734, y: 690))
    fold.close()
    NSColor(calibratedWhite: 0.82, alpha: 1).setFill()
    fold.fill()

    // Code lines in different colors and lengths, indented like source code.
    let lines: [(x: CGFloat, width: CGFloat, color: NSColor)] = [
        (350, 200, .systemPurple), (350, 300, .systemGray), (400, 230, .systemRed),
        (400, 160, .systemBlue), (350, 120, .systemGray),
    ]
    for (index, line) in lines.enumerated() {
        let y = 640 - CGFloat(index) * 72
        line.color.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: NSRect(x: line.x, y: y, width: line.width, height: 30), xRadius: 15, yRadius: 15).fill()
    }

    // Braces in the bottom-right corner of the sheet.
    let braces = NSAttributedString(string: "{ }", attributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 150, weight: .bold),
        .foregroundColor: NSColor(calibratedRed: 0.10, green: 0.38, blue: 0.86, alpha: 1),
    ])
    braces.draw(at: NSPoint(x: 470, y: 225))

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let sizes: [(points: Int, scale: Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
                                          (256, 1), (256, 2), (512, 1), (512, 2)]
try FileManager.default.createDirectory(atPath: outputFolder, withIntermediateDirectories: true)
var images: [[String: String]] = []
for (points, scale) in sizes {
    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
    let png = drawIcon(size: CGFloat(points * scale)).representation(using: .png, properties: [:])!
    try png.write(to: URL(fileURLWithPath: "\(outputFolder)/\(name)"))
    images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: URL(fileURLWithPath: "\(outputFolder)/Contents.json"))
let catalog = ["info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: catalog, options: [.prettyPrinted, .sortedKeys])
    .write(to: URL(fileURLWithPath: "NotepadS/Resources/Assets.xcassets/Contents.json"))
print("Wrote \(sizes.count) icon images to \(outputFolder)")
