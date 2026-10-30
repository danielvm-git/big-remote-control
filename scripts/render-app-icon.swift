// Renders the 1024 px iOS app icon: a remote on a blue gradient.
// App Store icons must be opaque, so the context has no alpha channel.
// Usage: swift scripts/render-app-icon.swift <output.png>
import AppKit

let size = 1024
let output = CommandLine.arguments.dropFirst().first ?? "AppIcon-1024.png"
guard let context = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else { fatalError("no context") }
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
let rect = NSRect(x: 0, y: 0, width: size, height: size)
NSGradient(colors: [NSColor(red: 0.10, green: 0.32, blue: 0.85, alpha: 1), NSColor(red: 0.04, green: 0.10, blue: 0.35, alpha: 1)])!
    .draw(in: rect, angle: -90)
// Drawn from plain shapes: Apple's SF Symbols license forbids symbols in app icons.
NSColor.white.setFill()
NSBezierPath(roundedRect: NSRect(x: 382, y: 170, width: 260, height: 690), xRadius: 110, yRadius: 110).fill()
let ink = NSColor(red: 0.07, green: 0.20, blue: 0.62, alpha: 1)
ink.setFill()
NSBezierPath(ovalIn: NSRect(x: 422, y: 600, width: 180, height: 180)).fill()      // touch ring
NSColor.white.setFill()
NSBezierPath(ovalIn: NSRect(x: 482, y: 660, width: 60, height: 60)).fill()        // OK
ink.setFill()
for (x, y) in [(432.0, 470.0), (532.0, 470.0), (432.0, 370.0)] {
    NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 60, height: 60)).fill()
}
NSBezierPath(roundedRect: NSRect(x: 532, y: 250, width: 60, height: 180), xRadius: 30, yRadius: 30).fill() // volume
NSBezierPath(ovalIn: NSRect(x: 432, y: 270, width: 60, height: 60)).fill()
guard let image = context.makeImage(),
      let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
else { fatalError("no image") }
try png.write(to: URL(fileURLWithPath: output))
