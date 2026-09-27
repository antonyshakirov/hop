import AppKit
import SwiftUI
import XCTest
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
        let controller = IntegralSizeHostingController(rootView: AnyView(
            ResizingContent(content: content)
        ))
        controller.sizingOptions = .preferredContentSize
        controller.enableFirstMouse()
        controller.view.layoutSubtreeIfNeeded()
        let short = controller.view.fittingSize.height
        let shortPreferred = controller.preferredContentSize.height
        content.tall = true
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        controller.view.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(controller.view.fittingSize.height, short + 50)
        XCTAssertGreaterThan(controller.preferredContentSize.height, shortPreferred + 50)
        Self.retainedFixtures.append(contentsOf: [content as AnyObject, controller])
    }
}
