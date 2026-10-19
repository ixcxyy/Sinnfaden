import AppKit
import Foundation

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Artifacts/Identity"
let identity = "Sources/KlarApp/Resources/Identity"
let fm = FileManager.default
try fm.createDirectory(atPath: output, withIntermediateDirectories: true)
try fm.createDirectory(atPath: identity, withIntermediateDirectories: true)
let main = CGMutablePath()
main.move(to: CGPoint(x:89,y:29))
main.addCurve(to: CGPoint(x:32,y:36), control1: CGPoint(x:74,y:14), control2: CGPoint(x:43,y:18))
main.addCurve(to: CGPoint(x:79,y:70), control1: CGPoint(x:13,y:63), control2: CGPoint(x:62,y:58))
main.addCurve(to: CGPoint(x:37,y:102), control1: CGPoint(x:107,y:90), control2: CGPoint(x:76,y:122))
let terminal = CGMutablePath(); terminal.move(to: CGPoint(x:25,y:94)); terminal.addLine(to: CGPoint(x:21,y:88))
func svgPath(_ path: CGPath) -> String {
    var out = ""
    func n(_ v: CGFloat) -> String { String(format: "%.3f", Double(v)) }
    path.applyWithBlock { ptr in
        let e = ptr.pointee; let p = e.points
        switch e.type {
        case .moveToPoint: out += "M\(n(p[0].x)) \(n(p[0].y)) "
        case .addLineToPoint: out += "L\(n(p[0].x)) \(n(p[0].y)) "
        case .addQuadCurveToPoint: out += "Q\(n(p[0].x)) \(n(p[0].y)) \(n(p[1].x)) \(n(p[1].y)) "
        case .addCurveToPoint: out += "C\(n(p[0].x)) \(n(p[0].y)) \(n(p[1].x)) \(n(p[1].y)) \(n(p[2].x)) \(n(p[2].y)) "
        case .closeSubpath: out += "Z "
        @unknown default: break
        }
    }
    return out
}
func outline(_ path: CGPath, width: CGFloat) -> String { svgPath(path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10)) }
let mainD = outline(main,width:11), endD = outline(terminal,width:11)
func svg(_ body: String, width: Int = 128, height: Int = 128) -> String {
    "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 \(width) \(height)\" role=\"img\" aria-label=\"sinnfaden\"><title>sinnfaden — ein Gedanke wird klar</title>\(body)</svg>\n"
}
for (name, ink, accent, bg) in [("master","#19191B","#19191B",""),("mono","currentColor","currentColor",""),("light","#19191B","#19191B","#FFFFFF"),("dark","#FFFFFF","#FFFFFF","#19191B")] {
    let backdrop = bg.isEmpty ? "" : "<rect width=\"128\" height=\"128\" rx=\"27\" fill=\"\(bg)\"/>"
    try svg(backdrop + "<path fill=\"\(ink)\" d=\"\(mainD)\"/><path fill=\"\(accent)\" d=\"\(endD)\"/>").write(toFile: "\(identity)/sinnfaden-\(name).svg",atomically:true,encoding:.utf8)
}
// Original monoline lowercase lettering: each glyph is drawn here, then expanded to outlines.
// No fonts, remote resources or bitmap data are used in the vector lockup.
func glyph(_ letter: Character) -> CGPath {
    let p = CGMutablePath()
    func move(_ x:Double,_ y:Double){p.move(to:CGPoint(x:x,y:y))}
    func line(_ x:Double,_ y:Double){p.addLine(to:CGPoint(x:x,y:y))}
    func curve(_ x:Double,_ y:Double,_ a:Double,_ b:Double,_ c:Double,_ d:Double){p.addCurve(to:CGPoint(x:x,y:y),control1:CGPoint(x:a,y:b),control2:CGPoint(x:c,y:d))}
    switch letter {
    case "s": move(25,25);curve(4,31,16,18,3,22);curve(24,43,3,40,24,35);curve(3,49,24,54,9,56)
    case "i": move(8,25);line(8,52);move(8,13);line(8,13.2)
    case "n": move(3,52);line(3,25);move(3,35);curve(27,34,5,18,27,20);line(27,52)
    case "f": move(10,52);line(10,19);curve(25,9,10,7,17,7);move(2,26);line(22,26)
    case "a": move(27,52);line(27,25);move(27,37);curve(3,39,27,17,3,20);curve(27,39,3,60,27,56)
    case "d": move(27,52);line(27,8);move(27,37);curve(3,39,27,17,3,20);curve(27,39,3,60,27,56)
    case "e": move(4,37);line(28,37);curve(3,38,28,17,3,20);curve(27,49,3,56,18,57)
    default: break
    }
    return p
}
var letters = ""; var x: CGFloat = 142
for c in "sinnfaden" {
    var transform = CGAffineTransform(translationX:x,y:28)
    let p = glyph(c).copy(using:&transform)!
    letters += "<path d=\"\(outline(p,width:4.4))\"/>"
    x += c == "i" ? 24 : 39
}
for (name,ink,accent) in [("wordmark","#19191B","#19191B"),("wordmark-dark","#FFFFFF","#FFFFFF")] {
    try svg("<path fill=\"\(ink)\" d=\"\(mainD)\"/><path fill=\"\(accent)\" d=\"\(endD)\"/><g fill=\"\(ink)\">\(letters)</g>",width:470).write(toFile:"\(identity)/sinnfaden-\(name).svg",atomically:true,encoding:.utf8)
}
func color(_ hex:UInt32)->CGColor { NSColor(srgbRed:CGFloat((hex>>16)&255)/255,green:CGFloat((hex>>8)&255)/255,blue:CGFloat(hex&255)/255,alpha:1).cgColor }
func render(_ size:Int, dark:Bool=false)->Data {
    let cs=CGColorSpace(name:CGColorSpace.sRGB)!
    let ctx=CGContext(data:nil,width:size,height:size,bitsPerComponent:8,bytesPerRow:0,space:cs,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x:0,y:CGFloat(size));ctx.scaleBy(x:CGFloat(size)/128,y:-CGFloat(size)/128)
    ctx.setFillColor(color(dark ? 0x19191B:0xFFFFFF))
    ctx.addPath(CGPath(roundedRect:CGRect(x:4,y:4,width:120,height:120),cornerWidth:27,cornerHeight:27,transform:nil));ctx.fillPath()
    ctx.setLineCap(.round);ctx.setLineJoin(.round);ctx.setLineWidth(size<=24 ? 12:11)
    ctx.setStrokeColor(color(dark ? 0xFFFFFF:0x19191B));ctx.addPath(main);ctx.strokePath()
    ctx.setStrokeColor(color(dark ? 0xFFFFFF:0x19191B));ctx.addPath(terminal);ctx.strokePath()
    return NSBitmapImageRep(cgImage:ctx.makeImage()!).representation(using:.png,properties:[:])!
}
let iconset="\(output)/SinnfadenIcon.iconset"
try fm.createDirectory(atPath:iconset,withIntermediateDirectories:true)
for size in [16,32,128,256,512] {
    try render(size).write(to:URL(fileURLWithPath:"\(iconset)/icon_\(size)x\(size).png"))
    try render(size*2).write(to:URL(fileURLWithPath:"\(iconset)/icon_\(size)x\(size)@2x.png"))
}
for size in [16,24,64,1024] {
    for dark in [false,true] {
        try render(size,dark:dark).write(to:URL(fileURLWithPath:"\(identity)/check-\(size)-\(dark ? "dark":"light").png"))
    }
}
let task=Process(); task.executableURL=URL(fileURLWithPath:"/usr/bin/iconutil");task.arguments=["-c","icns",iconset,"-o","\(output)/SinnfadenIcon.icns"];try task.run();task.waitUntilExit();guard task.terminationStatus==0 else {fatalError("iconutil failed")}
print("Sinnfaden SVG outlines and native icons generated.")
