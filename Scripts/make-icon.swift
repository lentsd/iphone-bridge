import AppKit

let image = NSImage(size: NSSize(width: 1024, height: 1024))
image.lockFocus()
let background = NSBezierPath(roundedRect: NSRect(x: 44, y: 44, width: 936, height: 936), xRadius: 215, yRadius: 215)
NSColor(calibratedRed: 0.91, green: 0.32, blue: 0.16, alpha: 1).setFill(); background.fill()
let ink = NSColor(calibratedRed: 0.15, green: 0.19, blue: 0.23, alpha: 1)
for (x, y) in [(CGFloat(233), CGFloat(296)), (CGFloat(586), CGFloat(332))] {
    NSColor.white.setFill()
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 205, height: 404), xRadius: 44, yRadius: 44).fill()
    ink.setFill()
    NSBezierPath(roundedRect: NSRect(x: x + 13, y: y + 13, width: 179, height: 378), xRadius: 33, yRadius: 33).fill()
    NSColor.white.setFill()
    NSBezierPath(roundedRect: NSRect(x: x + 73, y: y + 365, width: 60, height: 12), xRadius: 6, yRadius: 6).fill()
    NSBezierPath(roundedRect: NSRect(x: x + 70, y: y + 24, width: 65, height: 7), xRadius: 3.5, yRadius: 3.5).fill()
}
let arrow = NSBezierPath(); arrow.lineWidth = 30; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 405, y: 235)); arrow.curve(to: NSPoint(x: 727, y: 262), controlPoint1: NSPoint(x: 490, y: 143), controlPoint2: NSPoint(x: 658, y: 166))
arrow.move(to: NSPoint(x: 650, y: 246)); arrow.line(to: NSPoint(x: 731, y: 266)); arrow.line(to: NSPoint(x: 735, y: 184))
NSColor.white.setStroke(); arrow.stroke()
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
