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

    /// One line on what the module is for; the onboarding cards read the same key.
    static func purposeKey(_ module: String) -> L10nKey? {
        switch module {
        case "timer": return .purposeTimer
        case "awake": return .purposeAwake
        case "clipboard": return .purposeClipboard
        case "convert": return .purposeConvert
        case "windows": return .purposeWindows
        case "speedtest": return .purposeSpeedtest
        case "torrent": return .purposeTorrent
        case "color": return .purposeColor
        case "ocr": return .purposeOcr
        case "archive": return .purposeArchive
        case "keyboard": return .purposeKeyboard
        case "vpn": return .purposeVpn
        case "uninstall": return .purposeUninstall
        case "system": return .purposeSystem
        case "tracker": return .purposeTracker
        case "todos": return .purposeTodos
        default: return nil
        }
    }

    /// SPEC: docs/spec.md — "The module page (settings window)", the how-it-works line.
    static func howKey(_ module: String) -> L10nKey? {
        switch module {
        case "timer": return .howTimer
        case "awake": return .howAwake
        case "clipboard": return .howClipboard
        case "convert": return .howConvert
        case "windows": return .howWindows
        case "speedtest": return .howSpeedtest
        case "torrent": return .howTorrent
        case "color": return .howColor
        case "ocr": return .howOcr
        case "archive": return .howArchive
        case "keyboard": return .howKeyboard
        case "vpn": return .howVpn
        case "uninstall": return .howUninstall
        case "system": return .howSystem
        case "tracker": return .howTracker
        case "todos": return .howTodos
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
