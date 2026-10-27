import AppKit
import SwiftUI
import XCTest
@testable import Hop

@MainActor
final class SoundMixerSourceTransitionTests: XCTestCase {
    private final class State: ObservableObject {
        @Published var enabled = false
        @Published var hovering = false
    }
    private struct Sample {
        let row: Int
        let enabled: Bool
        let animated: Bool
        let animationsDisabled: Bool
    }
    private final class Samples {
        var values: [Sample] = []
    }
    private struct Harness: View {
        @ObservedObject var state: State
        let samples: Samples
        var body: some View {
            SoundMixerSourceControls(enabled: state.enabled) {
                VStack {
                    ForEach(0..<5) { row in
                        Text(state.enabled ? "Ready" : "Stopped")
                            .foregroundStyle(state.hovering ? Color.white : Color.gray)
                            .transaction { transaction in
                                samples.values.append(Sample(row: row, enabled: state.enabled,
                                    animated: transaction.animation != nil,
                                    animationsDisabled: transaction.disablesAnimations))
                            }
                    }
                }
            }
        }
    }

    func testEverySourceChangesWithoutAnimationEvenInsideAnimatedParent() {
        let state = State(), samples = Samples()
        let host = NSHostingView(rootView: Harness(state: state, samples: samples))
        host.frame.size = NSSize(width: 400, height: 250)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        for enabled in [true, false, true] {
            samples.values.removeAll()
            withAnimation(.linear(duration: 1)) { state.enabled = enabled }
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.04))
            let changed = samples.values.filter { $0.enabled == enabled }
            XCTAssertEqual(Set(changed.map(\.row)), Set(0..<5))
            for sample in changed {
                XCTAssertFalse(sample.animated, "Source \(sample.row), enabled=\(enabled)")
                XCTAssertTrue(sample.animationsDisabled, "Source \(sample.row), enabled=\(enabled)")
            }
        }
    }

    func testHoverStillAnimatesWhenAvailabilityDoesNotChange() {
        let state = State(), samples = Samples()
        state.enabled = true
        let host = NSHostingView(rootView: Harness(state: state, samples: samples))
        host.frame.size = NSSize(width: 400, height: 250)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        samples.values.removeAll()
        withAnimation(.easeOut(duration: 0.12)) { state.hovering = true }
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        XCTAssertEqual(Set(samples.values.map(\.row)), Set(0..<5))
        for sample in samples.values {
            XCTAssertTrue(sample.animated)
            XCTAssertFalse(sample.animationsDisabled)
        }
    }
}
