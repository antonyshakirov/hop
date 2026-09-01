import Foundation
import HopCore

/// The view layer of the module registry: an identifier becomes an icon and a
/// name. HopCore carries neither SF Symbols nor translations, so the mapping
/// lives here.
/// SPEC: hop-private/specs/2026-09-01-settings-window-design.md
enum ModulePresentation {
    static func titleKey(_ module: String) -> L10nKey? {
        switch module {
        case "timer": return .aboutTabTimer
        case "awake": return .awakeOff
        case "clipboard": return .tabClipboard
        case "convert": return .convertLabel
        case "windows": return .windowsLabel
        case "speedtest": return .speedtestLabel
        case "torrent": return .torrentLabel
        case "color": return .colorLabel
        case "ocr": return .ocrLabel
        case "archive": return .archiveLabel
        case "keyboard": return .keylockLabel
        case "vpn": return .vpnLabel
        case "uninstall": return .uninstallLabel
        case "system": return .tabSystem
        case "tracker": return .trackerLabel
        case "todos": return .todosLabel
        default: return nil
        }
    }

    static func icon(_ module: String) -> String {
        switch module {
        case "timer": return "timer"
        case "awake": return "moon"
        case "clipboard": return "doc.on.clipboard"
        case "convert": return "arrow.2.squarepath"
        case "windows": return "macwindow"
        case "speedtest": return "speedometer"
        case "torrent": return "arrow.down.circle"
        case "color": return "paintpalette"
        case "ocr": return "text.viewfinder"
        case "archive": return "archivebox"
        case "keyboard": return "keyboard"
        case "vpn": return "lock.shield"
        case "uninstall": return "trash"
        case "system": return "cpu"
        case "tracker": return "stopwatch"
        case "todos": return "checklist"
        default: return "square.grid.2x2"
        }
    }
}
