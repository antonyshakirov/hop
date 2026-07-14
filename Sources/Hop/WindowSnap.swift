import AppKit
import ApplicationServices

/// Window manager: window layout of the active window into screen zones via
/// the Accessibility API. Acts on the last active "regular" application
/// (our status bar popup is excluded from the count).
@MainActor
final class WindowSnapController {
    static let shared = WindowSnapController()

    enum Position: String, CaseIterable {
        case leftHalf, rightHalf, topHalf, bottomHalf, topLeft, topRight, bottomLeft, bottomRight, center, maximize
        case leftThird, centerThird, rightThird, leftTwoThirds, rightTwoThirds
        case centerHalf, topThird, bottomThird

        /// Fractions of the screen's visible area; origin at bottom-left (Cocoa coordinates).
        var unit: CGRect {
            switch self {
            case .leftHalf: return CGRect(x: 0, y: 0, width: 0.5, height: 1)
            case .rightHalf: return CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
            case .topHalf: return CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
            case .bottomHalf: return CGRect(x: 0, y: 0, width: 1, height: 0.5)
            case .topLeft: return CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)
            case .topRight: return CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)
            case .bottomLeft: return CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
            case .bottomRight: return CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
            case .center: return CGRect(x: 0.125, y: 0.1, width: 0.75, height: 0.8)
            case .maximize: return CGRect(x: 0, y: 0, width: 1, height: 1)
            case .leftThird: return CGRect(x: 0, y: 0, width: 1.0 / 3, height: 1)
            case .centerThird: return CGRect(x: 1.0 / 3, y: 0, width: 1.0 / 3, height: 1)
            case .rightThird: return CGRect(x: 2.0 / 3, y: 0, width: 1.0 / 3, height: 1)
            case .leftTwoThirds: return CGRect(x: 0, y: 0, width: 2.0 / 3, height: 1)
            case .rightTwoThirds: return CGRect(x: 1.0 / 3, y: 0, width: 2.0 / 3, height: 1)
            case .centerHalf: return CGRect(x: 0.25, y: 0, width: 0.5, height: 1)
            case .topThird: return CGRect(x: 0, y: 2.0 / 3, width: 1, height: 1.0 / 3)
            case .bottomThird: return CGRect(x: 0, y: 0, width: 1, height: 1.0 / 3)
            }
        }
    }

    private var lastExternalPID: pid_t?

    func startTracking() {
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            lastExternalPID = front.processIdentifier
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.activationPolicy == .regular,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier
            else { return }
            let pid = app.processIdentifier
            Task { @MainActor in
                WindowSnapController.shared.lastExternalPID = pid
            }
        }
    }

    func apply(_ position: Position) {
        let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(prompt) else { return }
        guard let pid = lastExternalPID else { return }
        let appElement = AXUIElementCreateApplication(pid)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement, kAXFocusedWindowAttribute as CFString, &windowRef
        ) == .success,
            let windowRef, CFGetTypeID(windowRef) == AXUIElementGetTypeID()
        else { return }
        let window = windowRef as! AXUIElement

        guard let screen = screenContaining(window) ?? NSScreen.main,
              let primary = NSScreen.screens.first?.frame
        else { return }
        let visible = screen.visibleFrame

        let u = position.unit
        let target = CGRect(
            x: visible.minX + u.minX * visible.width,
            y: visible.minY + u.minY * visible.height,
            width: u.width * visible.width,
            height: u.height * visible.height
        )
        // AX coordinates: origin at the top-left of the primary screen
        var axPoint = CGPoint(x: target.minX, y: primary.maxY - target.maxY)
        var axSize = CGSize(width: target.width, height: target.height)
        guard let pointValue = AXValueCreate(.cgPoint, &axPoint),
              let sizeValue = AXValueCreate(.cgSize, &axSize)
        else { return }

        // "enhanced user interface" (enabled by Raycast/VoiceOver and others)
        // breaks setting the frame — on the first click the window lands in the
        // wrong place or at the wrong size; disable it during layout and restore
        let enhancedKey = "AXEnhancedUserInterface" as CFString
        var enhancedRef: CFTypeRef?
        let hadEnhanced = AXUIElementCopyAttributeValue(appElement, enhancedKey, &enhancedRef) == .success
            && ((enhancedRef as? NSNumber)?.boolValue ?? false)
        if hadEnhanced {
            AXUIElementSetAttributeValue(appElement, enhancedKey, kCFBooleanFalse)
        }
        defer {
            if hadEnhanced {
                AXUIElementSetAttributeValue(appElement, enhancedKey, kCFBooleanTrue)
            }
        }

        // size-position-size: some windows accept the frame only in this
        // order; plus a verification read — some apply asynchronously or
        // clamp, so we converge with retries (otherwise "press it several times")
        for _ in 0..<3 {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, pointValue)
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
            if frameMatches(window, point: axPoint, size: axSize) { break }
        }
    }

    /// Did the window frame match the target (1pt tolerance for rounding)?
    private func frameMatches(_ window: AXUIElement, point: CGPoint, size: CGSize) -> Bool {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef, let sizeRef,
              CFGetTypeID(posRef) == AXValueGetTypeID(),
              CFGetTypeID(sizeRef) == AXValueGetTypeID()
        else { return true } // frame is unreadable — retries will not help
        var p = CGPoint.zero
        var s = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &p)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &s)
        return abs(p.x - point.x) <= 1 && abs(p.y - point.y) <= 1
            && abs(s.width - size.width) <= 1 && abs(s.height - size.height) <= 1
    }

    private func screenContaining(_ window: AXUIElement) -> NSScreen? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posRef, let sizeRef,
              CFGetTypeID(posRef) == AXValueGetTypeID(),
              CFGetTypeID(sizeRef) == AXValueGetTypeID()
        else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &point)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        guard let primary = NSScreen.screens.first?.frame else { return nil }
        let center = CGPoint(
            x: point.x + size.width / 2,
            y: primary.maxY - point.y - size.height / 2
        )
        return NSScreen.screens.first { $0.frame.contains(center) }
    }
}
