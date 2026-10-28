import AppKit
// 앱 아이콘에서 곰(흰 부분)만 뽑아 메뉴 막대용 흑백 템플릿을 만든다. 사각 판 바깥(밝은 배경)은 버린다.
let src = NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))!
let crop = CGRect(x: 190, y: 185, width: 670, height: 670)
let plate = CGPath(roundedRect: CGRect(x: 158, y: 140, width: 712, height: 745), cornerWidth: 125, cornerHeight: 125, transform: nil)   // 검은 판 안쪽(이미지 좌표, 위에서부터)
func make(_ size: Int, _ out: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    for y in 0..<size { for x in 0..<size {
        var on = 0.0
        for sy in 0..<3 { for sx in 0..<3 {   // 3×3 표본 평균으로 가장자리를 부드럽게
            let px = Int(crop.minX + (Double(x) + (Double(sx) + 0.5) / 3) / Double(size) * crop.width)
            let py = Int(crop.minY + (Double(y) + (Double(sy) + 0.5) / 3) / Double(size) * crop.height)
            if plate.contains(CGPoint(x: px, y: py)), let c = src.colorAt(x: px, y: py), (c.usingColorSpace(.deviceRGB)?.brightnessComponent ?? 0) > 0.6 { on += 1 }
        } }
        rep.setColor(NSColor(deviceRed: 0, green: 0, blue: 0, alpha: on / 9), atX: x, y: y)
    } }
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
}
make(18, CommandLine.arguments[2] + "/MenuBarIcon.png")
make(36, CommandLine.arguments[2] + "/MenuBarIcon@2x.png")
