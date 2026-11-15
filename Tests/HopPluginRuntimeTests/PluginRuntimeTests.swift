import XCTest
import HopPluginAPI
@testable import HopPluginRuntime

final class PluginRuntimeTests: XCTestCase {
    func testExactPublishedExamplesUseBareJSAndOwnBreakDoesNotLoop() throws {
        let service = RuntimeService(), generation = UUID(), session = UUID()
        let root = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        let package = try PluginPackage.decode(Data(contentsOf: root.appendingPathComponent("auto-break-1.0.0.hopplugin")))
        let context: PluginValue = .object(["settings": .object(["breakMinutes": .number(7)])])
        let activate = PluginRuntimeRequest(operation: "activate", session: session, generation: generation, request: UUID(), digest: "digest", code: package.code, context: context)
        _ = try service.execute(activate)
        func finish(own: Bool) throws -> PluginContributions {
            let request = PluginRuntimeRequest(operation: "event", session: session, generation: generation, request: UUID(), digest: "digest", context: context,
                                               event: .object(["type": .string("timer.finished"), "startedByPlugin": .bool(own)]))
            return try PluginContributions.decode(service.execute(request), capabilities: Set(package.manifest.capabilities))
        }
        XCTAssertEqual(try finish(own: false).commands.first?.seconds, 420)
        XCTAssertTrue(try finish(own: true).commands.isEmpty)
        let desk = try PluginPackage.decode(Data(contentsOf: root.appendingPathComponent("desk-panel-1.0.0.hopplugin")))
        let defaults = Dictionary(uniqueKeysWithValues: desk.manifest.settings.map { ($0.key, $0.default) })
        let result = try service.execute(PluginRuntimeRequest(operation: "activate", session: UUID(), generation: UUID(), request: UUID(), digest: "desk", code: desk.code, context: .object(["settings": .object(defaults)])))
        let contribution = try PluginContributions.decode(result, capabilities: Set(desk.manifest.capabilities))
        guard case .value(let panel) = contribution.panel else { return XCTFail("missing native panel") }
        XCTAssertEqual(panel.width, 420)
        XCTAssertEqual(panel.nodes.compactMap(\.module), ["timer", "system"])
    }
    func testContextAndGenerationCannotCrossSessionsAndNativeGlobalsAreAbsent() throws {
        let service = RuntimeService(), session = UUID(), generation = UUID()
        let code = "definePlugin({activate(){return {panel:{mode:'replace',nodes:[{type:'text',text:[typeof require,typeof process,typeof ObjC,typeof NSFileManager].join(',')}]}}}})"
        let output = try service.execute(PluginRuntimeRequest(operation: "activate", session: session, generation: generation, request: UUID(), digest: "a", code: code))
        XCTAssertTrue(String(decoding: output, as: UTF8.self).contains("undefined,undefined,undefined,undefined"))
        XCTAssertThrowsError(try service.execute(PluginRuntimeRequest(operation: "action", session: session, generation: UUID(), request: UUID(), digest: "a", action: "x")))
        XCTAssertThrowsError(try service.execute(PluginRuntimeRequest(operation: "action", session: session, generation: generation, request: UUID(), digest: "b", action: "x")))
        service.unload(session)
        XCTAssertTrue(service.contexts.isEmpty)
        XCTAssertThrowsError(try service.execute(PluginRuntimeRequest(operation: "action", session: session, generation: generation, request: UUID(), digest: "a", action: "x")))
    }
}
