import AppKit

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
var dark = true
var russian = true
var canvas = NSSize.zero
var currentFile = ""
var findings: [String] = []
var textLines: [[String: Any]] = []
var exports: [[String: Any]] = []

func copy(_ ru: String, _ en: String) -> String { russian ? ru : en }
func ink(_ darkValue: CGFloat, _ lightValue: CGFloat) -> NSColor {
    NSColor(white: dark ? darkValue : lightValue, alpha: 1)
}
func background() -> NSColor {
    dark ? NSColor(white: 0.045, alpha: 1) : NSColor(srgbRed: 0.973, green: 0.968, blue: 0.955, alpha: 1)
}
func blended(_ alpha: CGFloat) -> NSColor {
    let base = background().usingColorSpace(.deviceRGB)!
    let target: CGFloat = dark ? 1 : 0
    return NSColor(deviceRed: base.redComponent * (1-alpha) + target * alpha,
                   green: base.greenComponent * (1-alpha) + target * alpha,
                   blue: base.blueComponent * (1-alpha) + target * alpha, alpha: 1)
}
func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
    NSRect(x: x, y: canvas.height-y-h, width: w, height: h)
}
func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: NSColor,
         radius: CGFloat = 0, border: NSColor? = nil) {
    let path = NSBezierPath(roundedRect: rect(x,y,w,h), xRadius: radius, yRadius: radius)
    color.setFill(); path.fill()
    if let border { border.setStroke(); path.lineWidth = 1; path.stroke() }
}
func rule(_ y: CGFloat, inset: CGFloat = 20) {
    box(inset, y, canvas.width-inset*2, 1, blended(dark ? 0.08 : 0.10))
}
func text(_ value: String, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat,
          size: CGFloat = 11, color: NSColor? = nil, bold: Bool = false,
          height: CGFloat = 18, alignment: NSTextAlignment = .left) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byWordWrapping; paragraph.alignment = alignment
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: size, weight: bold ? .semibold : .medium),
        .foregroundColor: color ?? ink(0.92,0.12), .paragraphStyle: paragraph
    ]
    let storage = NSTextStorage(string: value, attributes: attributes)
    let manager = NSLayoutManager()
    let container = NSTextContainer(size: NSSize(width: width, height: 1000))
    container.lineFragmentPadding = 0
    manager.addTextContainer(container); storage.addLayoutManager(manager)
    manager.ensureLayout(for: container)
    var lines: [String] = []
    manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: container)) { _, _, _, range, _ in
        let range = manager.characterRange(forGlyphRange: range, actualGlyphRange: nil)
        lines.append((value as NSString).substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines))
    }
    if manager.usedRect(for: container).height > height+1 || lines.count != 1 {
        findings.append("\(currentFile): unexpected text wrap/overflow: \(value)")
    }
    if x < 0 || x+width > canvas.width || y+height > canvas.height {
        findings.append("\(currentFile): text outside frame: \(value)")
    }
    textLines.append(["file": currentFile, "text": value, "lines": lines,
                      "frame": [x,y,width,height]])
    (value as NSString).draw(in: rect(x,y,width,height), withAttributes: attributes)
}
func symbol(_ name: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat = 13, color: NSColor? = nil) {
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: size, weight: .regular)) else {
        findings.append("Missing SF Symbol: \(name)"); return
    }
    let image = NSImage(size: base.size)
    image.lockFocus()
    base.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
    (color ?? ink(0.66,0.32)).set()
    NSRect(origin: .zero, size: base.size).fill(using: .sourceAtop)
    image.unlockFocus()
    let factor = min(size/base.size.width,size/base.size.height)
    let w = base.size.width*factor, h = base.size.height*factor
    image.draw(in: rect(x+(size-w)/2,y+(size-h)/2,w,h))
}
func chip(_ label: String, _ icon: String, x: CGFloat, y: CGFloat, width: CGFloat, active: Bool = false) {
    box(x,y,width,28,active ? blended(dark ? 0.09 : 0.11) : background(),
        radius: 5, border: blended(active ? 0.20 : 0.10))
    symbol(icon,x+9,y+8,size:12,color:active ? ink(0.92,0.12) : ink(0.44,0.48))
    text(label,x+28,y+7,width-36,size:10,color:active ? ink(0.92,0.12) : ink(0.44,0.48))
}
func slider(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ gain: CGFloat, disabled: Bool = false) {
    box(x,y+5,width,3,disabled ? ink(0.10,0.90) : blended(dark ? 0.14 : 0.15),radius:1.5)
    box(x,y+5,width*gain,3,disabled ? ink(0.20,0.77) : blended(dark ? 0.66 : 0.68),radius:1.5)
    box(x+(width-11)*gain,y+1,11,11,disabled ? ink(0.28,0.66) : ink(0.96,0.20),radius:5.5)
}
func source(_ name: String, detail: String? = nil, y: CGFloat, selected: Bool = false,
            pinned: Bool = false, gain: CGFloat = 1, included: Bool = false, menu: Bool = true) {
    let labelWidth: CGFloat = 162
    let labelY = y + (detail == nil ? 12 : 4)
    let foreground = included ? ink(0.28,0.66) : ink(0.92,0.12)
    symbol(selected ? "checkmark.square.fill" : "square",22,y+13,size:12,
           color:selected ? foreground : ink(included ? 0.28 : 0.44,included ? 0.66 : 0.48))
    text(name,45,labelY,labelWidth-(pinned ? 12 : 0),color:foreground)
    if pinned {
        let nameWidth = (name as NSString).size(withAttributes:[.font:NSFont.monospacedSystemFont(ofSize:11,weight:.medium)]).width
        symbol("pin.fill",45+nameWidth+4,labelY+3,size:8,color:ink(0.66,0.32))
    }
    if let detail { text(detail,45,y+24,labelWidth,size:9,color:ink(included ? 0.28 : 0.44,included ? 0.66 : 0.48)) }
    let trackX: CGFloat = 215, trackWidth = canvas.width-trackX-130
    let disabled = !selected || included
    slider(trackX,y+14,trackWidth,gain,disabled:disabled)
    text("\(Int(gain*100))%",canvas.width-118,y+12,40,color:disabled ? ink(0.28,0.66) : ink(0.66,0.32),alignment:.right)
    box(canvas.width-70,y+6,30,28,disabled ? ink(0.07,0.94) : blended(dark ? 0.09 : 0.11),radius:6)
    symbol("speaker.wave.2",canvas.width-62,y+14,size:13,color:disabled ? ink(0.28,0.66) : ink(0.66,0.32))
    if menu { symbol("ellipsis",canvas.width-30,y+14,size:12) }
}

enum Mode: String, CaseIterable { case compact, expanded, restore, menu }
func screen(_ mode: Mode) {
    let expanded = mode != .compact
    box(0,0,canvas.width,canvas.height,background(),radius:13,border:blended(0.16))
    box(1,1,canvas.width-2,27,blended(dark ? 0.035 : 0.025),radius:12)
    for (index,color) in [NSColor.systemRed,.systemYellow,.systemGreen].enumerated() {
        box(14+CGFloat(index)*20,10,11,11,color,radius:5.5)
    }
    text(copy("звук","sound"),20,46,canvas.width-40,size:13,bold:true)
    box(20,69,canvas.width-40,34,background(),radius:7,border:blended(0.08))
    let tabWidth = (canvas.width-44)/2
    box(22+tabWidth,71,tabWidth,30,blended(dark ? 0.09 : 0.11),radius:6)
    symbol("speaker.wave.2",20+tabWidth/2-30,79,size:15)
    text(copy("выход","output"),20+tabWidth/2-6,79,65,size:10,color:ink(0.66,0.32))
    symbol("mic",22+tabWidth+tabWidth/2-25,79,size:15,color:ink(0.92,0.12))
    text(copy("вход","input"),22+tabWidth+tabWidth/2,79,65,size:10)
    rule(115,inset:0)
    symbol("mic",21,138,size:13)
    text(copy("вход","input"),43,137,65,bold:true)
    let deviceWidth = canvas.width-145
    box(125,130,deviceWidth,28,background(),radius:5,border:blended(0.10))
    text(copy("по умолчанию · AirPods 4","system default · AirPods 4"),134,137,deviceWidth-36,size:10,color:ink(0.44,0.48))
    symbol("chevron.down",canvas.width-42,139,size:9,color:ink(0.44,0.48))
    text(copy("громкость","volume"),20,178,75,color:ink(0.44,0.48))
    slider(107,179,canvas.width-245,0.70)
    text("70%",canvas.width-118,178,40,color:ink(0.66,0.32),alignment:.right)
    symbol("speaker.wave.2",canvas.width-58,181,size:13)
    chip(copy("проверить микрофон","check microphone"),"waveform",x:20,y:214,width:178)
    text(copy("запись до 10 секунд; удалится при закрытии окна.",
              "records up to 10 seconds; deleted when this window closes."),
         20,245,canvas.width-40,size:9,color:ink(0.44,0.48),height:13)
    rule(260)
    text(copy("микшер · включён","mixer · enabled"),20,285,canvas.width-175,bold:true)
    chip(copy("выключить","disable"),"power",x:canvas.width-128,y:278,width:108,active:true)
    text(copy("выберите Hop Mix как микрофон в приложении.","choose Hop Mix as the microphone in your app."),
         20,320,canvas.width-40,size:10,color:ink(0.44,0.48))
    source(copy("по умолчанию","system default"),detail:"AirPods 4",y:355,selected:true,menu:false)
    source("MacBook Air Microphone",y:405,pinned:true)
    source("Spotify",y:455,selected:true,gain:0.25)
    let otherY: CGFloat = 515
    symbol(expanded ? "chevron.down" : "chevron.right",22,otherY+3,size:9,color:ink(0.44,0.48))
    text(copy("другие источники","other sources"),40,otherY,canvas.width-95,size:10,color:ink(0.66,0.32))
    text("3",canvas.width-(expanded ? 78 : 52),otherY,30,size:10,color:ink(0.44,0.48),alignment:.right)
    if expanded {
        symbol("ellipsis",canvas.width-30,otherY+2,size:12)
        source("AirPods 4",detail:copy("уже добавлен","already included"),y:546,included:true)
        source("ZoomAudioDevice",detail:copy("виртуальный","virtual"),y:596)
        source("VLC",y:646)
    }
    if mode == .restore {
        let x = canvas.width-330, y: CGFloat = 532, w: CGFloat = 310
        box(x,y,w,106,background(),radius:8,border:blended(0.20))
        text(copy("скрытые источники","hidden sources"),x+14,y+13,w-28,size:11,bold:true)
        box(x+12,y+43,w-24,1,blended(0.10))
        text("iPhone Microphone",x+14,y+60,w-142,size:11)
        chip(copy("вернуть","show"),"eye",x:x+w-103,y:y+53,width:89)
    }
    if mode == .menu {
        let x = canvas.width-207, y: CGFloat = 546, w: CGFloat = 185
        box(x,y,w,91,background(),radius:7,border:blended(0.20))
        symbol("pin",x+12,y+14,size:12)
        text(copy("закрепить","pin source"),x+36,y+12,w-48,size:10)
        box(x+8,y+43,w-16,1,blended(0.10))
        symbol("eye.slash",x+12,y+60,size:12)
        text(copy("скрыть","hide source"),x+36,y+58,w-48,size:10)
    }
}

for language in ["ru","en"] {
    russian = language == "ru"
    for theme in ["dark","light"] {
        dark = theme == "dark"
        for width: CGFloat in [480,520,720] {
            for mode in Mode.allCases {
                let expanded = mode != .compact
                canvas = NSSize(width:width,height:expanded ? 706 : 555)
                currentFile = "\(language)-\(theme)-\(Int(width))-\(mode.rawValue).png"
                let image = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(width*2),pixelsHigh:Int(canvas.height*2),
                    bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
                image.size = canvas
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:image)
                screen(mode)
                NSGraphicsContext.current?.flushGraphics()
                NSGraphicsContext.restoreGraphicsState()
                if width == 520 {
                    try image.representation(using:.png,properties:[:])!.write(to:destination.appendingPathComponent(currentFile))
                    exports.append(["file":currentFile,"points":[width,canvas.height]])
                }
            }
        }
    }
}
let report: [String: Any] = ["renderer":"Native AppKit drawing proposal based on Hop Theme and control metrics",
    "screenshotsOfImplementedFeature":false,"audioUsed":false,"appSourceChanged":false,
    "matrixCases":48,"exports":exports,"findings":findings,"textLines":textLines]
try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys])
    .write(to:destination.appendingPathComponent("layout-checks.json"))
print("Native input-source proposal: 48 renders, \(exports.count) exports, \(findings.count) layout findings")
if !findings.isEmpty { for finding in findings { print(finding) }; exit(1) }
