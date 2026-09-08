import AppKit
import HopCore
import ScreenCaptureKit
import SwiftUI

/// Takes the picture: an area framed by hand, the window under the pointer, a
/// whole display, or the last rectangle again.
///
/// The frame is ours rather than the system's `screencapture -i`, which never
/// says WHICH rectangle was chosen — without that "repeat the last area" cannot
/// exist. SPEC: .claude/specs/2026-09-07-markup-modules-design.md
@MainActor
final class CaptureController: ObservableObject {
    enum Mode {
        case area
        case window
        case screen
        case repeatLast
    }

    enum State: Equatable {
        case idle
        case framing
        case counting(Int)
        case denied
        case failed
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastRect: CaptureRect?

    /// Handed the picture and the rectangle it came from.
    var onCaptured: ((NSImage, CaptureRect) -> Void)?

    private let overlay = MarkupOverlayController()
    private var delaySeconds: Int { UserDefaults.standard.integer(forKey: "shotDelay") }
    private var showsPointer: Bool { UserDefaults.standard.bool(forKey: "shotPointer") }

    func capture(_ mode: Mode) {
        guard state == .idle, !Snapshot.active else { return }
        guard CGPreflightScreenCaptureAccess() else {
            PermissionRepair.askAgain(.screenCapture, force: true)
            state = .denied
            return
        }

        switch mode {
        case .area:
            frameAnArea()
        case .window:
            takeWindowUnderPointer()
        case .screen:
            takeWholeScreen()
        case .repeatLast:
            guard let rect = lastRect else {
                frameAnArea()
                return
            }
            shoot(rect)
        }
    }

    private func frameAnArea() {
        state = .framing
        overlay.show { [weak self] screen in
            let host = FirstMouseHostingView(rootView: CaptureSelectionView(
                screenSize: screen.frame.size,
                scale: screen.backingScaleFactor,
                lang: L10n.current,
                onPick: { [weak self] rect in
                    guard let self else { return }
                    var picked = rect
                    picked.displayID = Self.displayID(of: screen)
                    self.overlay.hide()
                    self.state = .idle
                    self.shoot(picked)
                },
                onWindowMode: { [weak self] in
                    self?.overlay.hide()
                    self?.state = .idle
                    self?.takeWindowUnderPointer()
                },
                onRepeat: { [weak self] in
                    guard let self, let rect = self.lastRect else { return }
                    self.overlay.hide()
                    self.state = .idle
                    self.shoot(rect)
                },
                onCancel: { [weak self] in
                    self?.overlay.hide()
                    self?.state = .idle
                }
            ))
            return host
        }
    }

    private func takeWholeScreen() {
        guard let screen = Self.screenUnderPointer() else { return }
        shoot(CaptureRect(x: 0, y: 0,
                          width: screen.frame.width, height: screen.frame.height,
                          scale: screen.backingScaleFactor,
                          displayID: Self.displayID(of: screen)))
    }

    private func takeWindowUnderPointer() {
        guard let screen = Self.screenUnderPointer(),
              let frame = WindowUnderPointer.frame(at: NSEvent.mouseLocation) else {
            takeWholeScreen()
            return
        }
        let local = CaptureRect(x: frame.minX - screen.frame.minX,
                                y: screen.frame.maxY - frame.maxY,
                                width: frame.width, height: frame.height,
                                scale: screen.backingScaleFactor,
                                displayID: Self.displayID(of: screen))
        let bounds = CaptureRect(x: 0, y: 0, width: screen.frame.width, height: screen.frame.height,
                                 scale: screen.backingScaleFactor, displayID: local.displayID)
        shoot(local.clamped(to: bounds))
    }

    private func shoot(_ rect: CaptureRect) {
        lastRect = rect
        let delay = delaySeconds
        guard delay > 0 else {
            grab(rect)
            return
        }
        state = .counting(delay)
        countdown(from: delay, rect: rect)
    }

    private func countdown(from seconds: Int, rect: CaptureRect) {
        guard seconds > 0 else {
            state = .idle
            grab(rect)
            return
        }
        state = .counting(seconds)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.countdown(from: seconds - 1, rect: rect)
        }
    }

    private func grab(_ rect: CaptureRect) {
        Task { [weak self] in
            guard let self else { return }
            guard let image = await Self.picture(of: rect, showsPointer: self.showsPointer) else {
                self.state = .failed
                return
            }
            self.state = .idle
            self.onCaptured?(image, rect)
        }
    }

    /// The whole display in its own pixels, cropped to the rectangle. Hop's own
    /// windows are left out, so the panel never lands in the shot.
    private static func picture(of rect: CaptureRect, showsPointer: Bool) async -> NSImage? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )
            guard let display = content.displays.first(where: { $0.displayID == rect.displayID })
                    ?? content.displays.first else { return nil }

            let ours = content.windows.filter {
                $0.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
            }
            let filter = SCContentFilter(display: display, excludingWindows: ours)

            let configuration = SCStreamConfiguration()
            configuration.width = Int(Double(display.width) * rect.scale)
            configuration.height = Int(Double(display.height) * rect.scale)
            configuration.showsCursor = showsPointer
            configuration.captureResolution = .best

            let full = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: configuration
            )

            let crop = CGRect(x: rect.x * rect.scale, y: rect.y * rect.scale,
                              width: Double(rect.pixelWidth), height: Double(rect.pixelHeight))
            guard let cut = full.cropping(to: crop) else { return nil }
            return NSImage(cgImage: cut, size: NSSize(width: rect.width, height: rect.height))
        } catch {
            return nil
        }
    }

    static func screenUnderPointer() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }

    static func displayID(of screen: NSScreen) -> UInt32 {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

/// The frame of the window under the pointer, in AppKit's global coordinates.
enum WindowUnderPointer {
    static func frame(at point: NSPoint) -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }

        let flipped = flip(point)
        for window in list {
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let owner = window[kCGWindowOwnerPID as String] as? Int,
                  owner != Int(ProcessInfo.processInfo.processIdentifier),
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"],
                  let width = bounds["Width"], let height = bounds["Height"] else { continue }

            let rect = CGRect(x: x, y: y, width: width, height: height)
            if rect.contains(flipped) {
                return CGRect(x: rect.minX, y: unflip(rect.maxY), width: rect.width, height: rect.height)
            }
        }
        return nil
    }

    /// CoreGraphics counts down from the top of the main display; AppKit counts
    /// up from its bottom.
    private static func flip(_ point: NSPoint) -> CGPoint {
        guard let main = NSScreen.screens.first else { return point }
        return CGPoint(x: point.x, y: main.frame.maxY - point.y)
    }

    private static func unflip(_ y: CGFloat) -> CGFloat {
        guard let main = NSScreen.screens.first else { return y }
        return main.frame.maxY - y
    }
}
