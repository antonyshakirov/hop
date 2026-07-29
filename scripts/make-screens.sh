#!/usr/bin/env bash
# Renders every product screenshot, for every language that has its own folder.
#
# These recipes used to live nowhere: each shot was taken by hand with whatever
# flags the moment called for, so nobody could reproduce one a month later and
# the set drifted out of date module by module (Anton, 2026-07-28). Everything
# the README and the product page show is now made by this script.
#
#   ./scripts/make-screens.sh [out-dir] [lang ...]
#
# Default out-dir is the website repo's public folder, so a run lands where the
# pages already look for the files. Pass languages to render a subset.
set -euo pipefail

cd "$(dirname "$0")/.."

OUT=${1:-"../antonshakirov-com/development/public/products/hop/screens"}
shift || true
LANGS=("$@")
if [ ${#LANGS[@]} -eq 0 ]; then
    # only the languages with their own folder; every other README points at en
    LANGS=(en ru de es fr pt ja zh)
fi

BIN=.build/debug/Hop
echo "building…"
swift build >/dev/null

# Sample files for the converter window: real images and a real PDF, so the
# rows carry genuine thumbnails and size estimates rather than placeholders.
SAMPLES=$(mktemp -d)
trap 'rm -rf "$SAMPLES"' EXIT
swift - "$SAMPLES" <<'SWIFT' >/dev/null
import AppKit
import CoreGraphics

let dir = CommandLine.arguments[1]

/// A plausible photograph: a soft gradient with grain, so JPEG has something to
/// compress and the estimated size is not a rounding artifact.
func picture(_ size: NSSize, seed: Int) -> NSImage {
    let image = NSImage(size: size)
    image.lockFocus()
    NSGradient(colors: [
        NSColor(calibratedHue: CGFloat(seed % 7) / 7, saturation: 0.45, brightness: 0.75, alpha: 1),
        NSColor(calibratedHue: CGFloat((seed + 3) % 7) / 7, saturation: 0.35, brightness: 0.35, alpha: 1),
    ])?.draw(in: NSRect(origin: .zero, size: size), angle: 35)
    var value = UInt64(seed &* 2_654_435_761)
    for _ in 0..<24_000 {
        value = value &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        let x = CGFloat(value >> 33 % UInt64(size.width))
        let y = CGFloat(value >> 11 % UInt64(size.height))
        NSColor(calibratedWhite: CGFloat(value % 100) / 100, alpha: 0.16).setFill()
        NSRect(x: x, y: y, width: 2, height: 2).fill()
    }
    image.unlockFocus()
    return image
}

func write(_ image: NSImage, to name: String, as type: NSBitmapImageRep.FileType) {
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: type,
                                        properties: [.compressionFactor: 0.9]) else { return }
    try? data.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
}

// Sizes are chosen so the rows read like files someone would really have:
// a phone photo of a few hundred KB and a screenshot a little larger. An
// implausible figure in the estimate column undoes the point of the shot.
write(picture(NSSize(width: 1100, height: 733), seed: 2), to: "photo-4231.jpg", as: .jpeg)
write(picture(NSSize(width: 760, height: 500), seed: 5), to: "screenshot.png", as: .png)

// The deck carries a picture on every page: a PDF of pure vector blocks weighs
// a few KB, and the row then reads "5 KB → ~366 KB", which looks like a bug.
let pdfURL = URL(fileURLWithPath: dir).appendingPathComponent("brand-deck.pdf")
var box = CGRect(x: 0, y: 0, width: 595, height: 842)
if let ctx = CGContext(pdfURL as CFURL, mediaBox: &box, nil) {
    for page in 0..<5 {
        ctx.beginPage(mediaBox: &box)
        ctx.setFillColor(CGColor(gray: 0.96, alpha: 1))
        ctx.fill(box)
        let art = picture(NSSize(width: 900, height: 560), seed: page &+ 11)
        if let tiff = art.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let cg = rep.cgImage {
            ctx.draw(cg, in: CGRect(x: 48, y: 430, width: 499, height: 310))
        }
        for row in 0..<7 {
            ctx.setFillColor(CGColor(gray: 0.55 - Double(row % 4) * 0.08, alpha: 1))
            ctx.fill(CGRect(x: 48, y: 360 - CGFloat(row) * 46,
                            width: 380 - CGFloat((row &+ page) % 5) * 45, height: 16))
        }
        ctx.endPage()
    }
    ctx.closePDF()
}
SWIFT

shot() {  # shot <lang> <name> <flags…>
    local lang=$1 name=$2
    shift 2
    "$BIN" --snapshot "$OUT/$lang/$name.png" --lang "$lang" --theme dark "$@"
}

for lang in "${LANGS[@]}"; do
    mkdir -p "$OUT/$lang"
    echo "→ $lang"

    # The one shot that answers "what is this app": every module at once, the
    # opt-in ones included, each with content in it.
    shot "$lang" overview --overview --demo --running

    # The panel as it ships, without the opt-in modules — the product page's
    # hero stands it in the middle of the composition.
    shot "$lang" panel --demo --running

    # One module per shot for the sections that describe one module. A section
    # about the timer next to a picture of the whole panel shows the reader nine
    # other things instead of the one being described.
    shot "$lang" timer --only timer --demo --running
    shot "$lang" awake --only awake --demo --awake
    shot "$lang" clipboard --only clipboard --demo
    shot "$lang" windows --only windows --demo
    shot "$lang" speed --only speed --demo
    shot "$lang" tracker --tasks
    shot "$lang" system --stats --charts
    shot "$lang" torrents --torrents --demo
    shot "$lang" colors --colors --demo
    shot "$lang" keyboard --keyboard --demo
    shot "$lang" vpn --only vpn --demo
    shot "$lang" apps --only apps --demo

    # Windows of their own.
    shot "$lang" converter --window-converter \
        --convert-files "$SAMPLES/photo-4231.jpg,$SAMPLES/screenshot.png,$SAMPLES/brand-deck.pdf"
    shot "$lang" archives --window-archive --demo
    shot "$lang" recognition --window-ocr --demo
    shot "$lang" settings --window-settings
done

echo
echo "done → $OUT"
echo "remember to bump SCREENS_VER in the site's src/views/hop/config.ts"
