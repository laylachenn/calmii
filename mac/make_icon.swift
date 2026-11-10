import Cocoa
// Draws the aura app icon: soft blue squircle with a magenta → orange → cyan glow.
// Pass "full" as a 2nd arg for a full-bleed square (iOS rounds the corners itself).
let out = CommandLine.arguments[1]
let full = CommandLine.arguments.count > 2 && CommandLine.arguments[2] == "full"
let s: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(s), pixelsHigh: Int(s), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
let inset: CGFloat = full ? 0 : 100, rect = CGRect(x: inset, y: inset, width: s - 2*inset, height: s - 2*inset)
let path = CGPath(roundedRect: rect, cornerWidth: full ? 0 : 185, cornerHeight: full ? 0 : 185, transform: nil)
ctx.addPath(path); ctx.clip()
ctx.setFillColor(CGColor(srgbRed: 0.435, green: 0.682, blue: 0.86, alpha: 1)); ctx.fill(rect)
func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: a) }
let colors = [c(207,77,190), c(211,90,178), c(238,154,85), c(243,174,71), c(201,231,166), c(127,245,236), c(127,245,236,0.5), c(111,174,219,0)] as CFArray
let locs: [CGFloat] = [0, 0.17, 0.33, 0.41, 0.52, 0.6, 0.67, 0.76]
let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: locs)!
let ctr = CGPoint(x: s/2, y: s/2)
ctx.drawRadialGradient(grad, startCenter: ctr, startRadius: 0, endCenter: ctr, endRadius: full ? 480 : 400, options: [])
NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
