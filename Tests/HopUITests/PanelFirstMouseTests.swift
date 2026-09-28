import AppKit
import SwiftUI
import XCTest
import HopCore
@testable import Hop

@MainActor
final class PanelFirstMouseTests: XCTestCase {
    private static var retainedFixtures: [AnyObject] = []

    private final class Content: ObservableObject {
        @Published var tall = false
    }

    private struct ResizingContent: View {
        @ObservedObject var content: Content

        var body: some View {
            Rectangle().frame(width: 120, height: content.tall ? 100 : 20)
        }
    }

    private struct PopoverResizingContent: View {
        @ObservedObject var content: Content

        var body: some View {
            Rectangle().frame(width: 368, height: content.tall ? 700 : 200)
        }
    }

    func testGestureRowAcceptsFirstClickInInactivePanel() {
        _ = NSApplication.shared
        let controller = IntegralSizeHostingController(rootView: AnyView(
            Text("Open task")
                .frame(width: 120, height: 40)
                .contentShape(Rectangle())
                .onTapGesture {}
        ))
        controller.enableFirstMouse()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 120, height: 40),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = controller
        controller.view.layoutSubtreeIfNeeded()
        let event = NSEvent.mouseEvent(with: .leftMouseDown,
                                      location: NSPoint(x: 60, y: 20),
                                      modifierFlags: [], timestamp: 0,
                                      windowNumber: window.windowNumber, context: nil,
                                      eventNumber: 1, clickCount: 1, pressure: 1)!
        XCTAssertTrue(controller.view.acceptsFirstMouse(for: event))
        Self.retainedFixtures.append(contentsOf: [controller, window, event])
    }

    func testCustomHostingViewStillTracksPanelHeight() {
        let content = Content()
        content.tall = true
        let controller = IntegralSizeHostingController(rootView: AnyView(
            ResizingContent(content: content)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        ))
        controller.sizingOptions = .preferredContentSize
        controller.enableFirstMouse()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 120, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentViewController = controller
        controller.view.layoutSubtreeIfNeeded()
        let tall = controller.view.fittingSize.height
        let tallPreferred = controller.preferredContentSize.height
        content.tall = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertLessThan(controller.view.fittingSize.height, tall - 50)
        XCTAssertLessThan(controller.preferredContentSize.height, tallPreferred - 50)
        Self.retainedFixtures.append(contentsOf: [content as AnyObject, controller, window])
    }

    func testExplicitPopoverSizeSurvivesHostingLayout() {
        let content = Content()
        content.tall = true
        let controller = IntegralSizeHostingController(rootView: AnyView(
            PopoverResizingContent(content: content)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        ))
        controller.enableExplicitPopoverSizing()
        controller.enableFirstMouse()
        let anchorWindow = NSWindow(contentRect: NSRect(x: 600, y: 500, width: 368, height: 50),
                                    styleMask: [.titled], backing: .buffered, defer: false)
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 368, height: 50))
        anchorWindow.contentView = anchor
        anchorWindow.orderFront(nil)
        let popover = NSPopover()
        popover.animates = false
        popover.contentViewController = controller
        popover.contentSize = NSSize(width: 368, height: 700)
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        NSApp.deactivate()

        content.tall = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        popover.contentSize = NSSize(width: 368, height: 200)
        controller.view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(popover.contentSize.height, 200, accuracy: 1)
        XCTAssertLessThan(controller.view.window?.frame.height ?? 0, 250)
        popover.close()
        anchorWindow.orderOut(nil)
        Self.retainedFixtures.append(contentsOf: [content as AnyObject, controller, anchorWindow, popover])
    }

    func testTabOverlayUsesWindowCoordinatesWithoutAddingContentInsetAgain() {
        let windowFrame = NSRect(x: 833, y: 82, width: 394, height: 849)
        let measuredTabRect = CGRect(x: 27, y: 32, width: 234, height: 32)
        let overlayFrame = StatusItemController.tabPanelFrame(
            in: windowFrame, for: measuredTabRect)

        XCTAssertEqual(overlayFrame, NSRect(x: 860, y: 867, width: 234, height: 32))
    }

    func testPanelPrefersShorterHeightAfterSwitchingFromLongSpace() {
        let defaults = UserDefaults.standard
        let keys = [SettingsKey.panelTabs, "activeSpaceID", "debugPanelFrameLog",
                    SettingsKey.trackerTabSeeded, SettingsKey.todosSeeded,
                    SettingsKey.moduleVisibilityMigrated, SettingsKey.canonicalLayoutSeeded,
                    SettingsKey.optInModulesSeeded, SettingsKey.optInModulesSeeded170]
        let saved = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
        defer {
            for (key, value) in saved {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        for key in keys.dropFirst(2) { defaults.set(true, forKey: key) }
        let tallTab = PanelTab(icon: "house", moduleKeys: [
            "timer", "awake", "clipboard", "vpn", "keyboard", "ocr", "convert", "shot",
            "annotate", "windows",
        ])
        let monitorTab = PanelTab(icon: "display", moduleKeys: ["system", "speedtest", "torrent"])
        let shortTab = PanelTab(icon: "clock", moduleKeys: ["tracker", "todos"])
        let toolsTab = PanelTab(icon: "tray", moduleKeys: ["archive", "uninstall", "color"])
        defaults.set(PanelTabsModel(tabs: [tallTab, monitorTab, shortTab, toolsTab]).encoded(),
                     forKey: SettingsKey.panelTabs)
        defaults.set(tallTab.id.uuidString, forKey: "activeSpaceID")

        let model = AppModel(preview: true)
        var measuredSizes: [CGSize] = []
        let controller = IntegralSizeHostingController(rootView: AnyView(
            PanelView(initial: .firstSpace).environmentObject(model)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        ))
        controller.enableExplicitPopoverSizing()
        controller.enableFirstMouse()
        let window = NSWindow(contentRect: NSRect(x: 600, y: 500, width: 368, height: 50),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 368, height: 50))
        window.contentView = anchor
        window.orderFront(nil)
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = controller
        model.panelContentSizeChanged = { [weak popover] size in
            measuredSizes.append(size)
            DispatchQueue.main.async { popover?.contentSize = size }
        }
        controller.view.layoutSubtreeIfNeeded()
        popover.contentSize = controller.view.fittingSize
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let tallHeight = popover.contentSize.height
        let tallWindowHeight = controller.view.window?.frame.height ?? 0
        NSApp.deactivate()
        measuredSizes.removeAll()

        model.isPanelOpen = { true }
        var immediateHeight: CGFloat?
        model.panelContentSizeWillChange = { [weak popover] size in
            // a space measured before is resized from its cached height at once,
            // and then no later measurement differs: either report counts
            measuredSizes.append(size)
            popover?.contentSize = size
            immediateHeight = popover?.contentSize.height
        }

        model.openTab = .spaceContaining("tracker")
        let resizeDeadline = Date().addingTimeInterval(4)
        while popover.contentSize.height >= tallHeight - 100 && Date() < resizeDeadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        controller.view.layoutSubtreeIfNeeded()
        let shortHeight = popover.contentSize.height
        print("PANEL TEST tall=\(tallHeight) short=\(shortHeight) shown=\(popover.isShown) "
              + "window=\(controller.view.window?.frame.height ?? -1) view=\(controller.view.frame.height) "
              + "reported=\(measuredSizes.map(\.height)) immediate=\(immediateHeight ?? -1)")
        XCTAssertLessThan(shortHeight, tallHeight - 100,
                          "panel should not leave an empty background below a shorter tab")
        XCTAssertLessThan(measuredSizes.last?.height ?? .infinity, tallHeight - 100,
                          "the panel must report its measured height instead of the stale host fitting size")
        XCTAssertEqual(measuredSizes.last?.height ?? 0, shortHeight, accuracy: 2,
                       "the reported height must match the panel's visible content height")
        model.openTab = .spaceContaining("timer")
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        immediateHeight = nil
        model.openTab = .spaceContaining("tracker")
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        XCTAssertEqual(immediateHeight ?? 0, shortHeight, accuracy: 2,
                       "a previously measured tab must resize in its click handler")
        XCTAssertLessThan(controller.view.window?.frame.height ?? 0, tallWindowHeight - 100,
                          "the visible popover window must shrink even while Hop is inactive")
        popover.close()
        window.orderOut(nil)
        Self.retainedFixtures.append(contentsOf: [model as AnyObject, controller, window, popover])
    }
}
