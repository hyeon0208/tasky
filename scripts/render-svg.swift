import AppKit
let args = CommandLine.arguments
for i in stride(from: 1, to: args.count, by: 2) {
    let src = URL(fileURLWithPath: args[i]), dst = URL(fileURLWithPath: args[i+1])
    guard let img = NSImage(contentsOf: src) else { print("fail", src.path); continue }
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.clear.set(); NSRect(x: 0, y: 0, width: 1024, height: 1024).fill()
    img.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: dst)
}
