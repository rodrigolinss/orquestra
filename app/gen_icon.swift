// gen_icon.swift — gera o icone do Orquestra: hexagono (SF Symbol) no verde
// Nevoa (#CCFF00) sobre fundo escuro da marca (#09090B), squircle padrao macOS.
// Uso: swift gen_icon.swift <saida.png> [--flat]
//   --flat: sem squircle/margem (logo para README)
import AppKit

let args = CommandLine.arguments
guard args.count >= 2 else { fputs("uso: swift gen_icon.swift <saida.png> [--flat]\n", stderr); exit(1) }
let outPath = args[1]
let flat = args.contains("--flat")

let size = 1024
let lime = NSColor(red: 0.8, green: 1.0, blue: 0.0, alpha: 1)
let dark = NSColor(red: 0.035, green: 0.035, blue: 0.043, alpha: 1)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                           isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

if !flat {
    // squircle padrao de icone macOS: ~824pt centrado em canvas 1024
    let box = NSRect(x: 100, y: 100, width: 824, height: 824)
    let path = NSBezierPath(roundedRect: box, xRadius: 185, yRadius: 185)
    dark.setFill()
    path.fill()
}

let config = NSImage.SymbolConfiguration(pointSize: flat ? 700 : 460, weight: .medium)
    .applying(NSImage.SymbolConfiguration(paletteColors: [lime]))
if let symbol = NSImage(systemSymbolName: "circle.hexagongrid.fill",
                        accessibilityDescription: nil)?.withSymbolConfiguration(config) {
    let s = symbol.size
    let scale = (flat ? 900.0 : 500.0) / max(s.width, s.height)
    let w = s.width * scale, h = s.height * scale
    symbol.draw(in: NSRect(x: (1024 - w) / 2, y: (1024 - h) / 2, width: w, height: h),
                from: .zero, operation: .sourceOver, fraction: 1.0)
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))
print("ok: \(outPath)")
