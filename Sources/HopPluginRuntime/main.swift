import Foundation
import JavaScriptCore
import HopPluginAPI
import Darwin

final class RuntimeService: NSObject, PluginRuntimeXPC {
    struct Context { let js: JSContext; let digest: String; let generation: UUID }
    let javascript = DispatchQueue(label: "hop.plugin.javascript", autoreleaseFrequency: .workItem)
    let watchdog = DispatchQueue(label: "hop.plugin.watchdog", qos: .userInteractive)
    var contexts: [UUID: Context] = [:]
    private var memoryWatchdog: DispatchSourceTimer?
    private func watchMemory() {
        guard memoryWatchdog == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: watchdog)
        timer.schedule(deadline: .now() + .milliseconds(100), repeating: .milliseconds(100))
        timer.setEventHandler {
            var usage = rusage()
            if getrusage(RUSAGE_SELF, &usage) == 0, usage.ru_maxrss > 128 * 1_048_576 { _exit(125) }
        }
        timer.resume(); memoryWatchdog = timer
    }
    private func stopMemoryIfIdle() {
        if contexts.isEmpty { memoryWatchdog?.cancel(); memoryWatchdog = nil }
    }
    func unload(_ session: UUID) {
        contexts.removeValue(forKey: session)
        stopMemoryIfIdle()
    }

    func request(_ data: Data, reply: @escaping (Data) -> Void) {
        guard data.count <= 2_097_152, let envelope = try? JSONDecoder().decode(PluginRuntimeRequest.self, from: data) else { return }
        javascript.async { [self] in
            if envelope.operation == "hello" {
                reply((try? JSONEncoder().encode(PluginRuntimeReply(envelope))) ?? Data())
                return
            }
            if envelope.operation == "shutdown" {
                reply((try? JSONEncoder().encode(PluginRuntimeReply(envelope))) ?? Data())
                watchdog.asyncAfter(deadline: .now() + .milliseconds(50)) { _exit(0) }
                return
            }
            let deadline = DispatchSource.makeTimerSource(queue: watchdog)
            deadline.schedule(deadline: .now() + .milliseconds(envelope.operation == "activate" ? 500 : 100))
            deadline.setEventHandler { _exit(124) }
            deadline.resume()
            defer { deadline.cancel() }
            if envelope.operation == "unload" {
                unload(envelope.session)
                reply((try? JSONEncoder().encode(PluginRuntimeReply(envelope))) ?? Data())
                return
            }
            if envelope.operation == "activate" { watchMemory() }
            do {
                let output = try execute(envelope)
                reply(try JSONEncoder().encode(PluginRuntimeReply(envelope, result: output)))
            } catch {
                contexts.removeValue(forKey: envelope.session)
                stopMemoryIfIdle()
                reply((try? JSONEncoder().encode(PluginRuntimeReply(envelope, error: PluginError.javascriptError.rawValue))) ?? Data())
            }
        }
    }

    func execute(_ request: PluginRuntimeRequest) throws -> Data {
        if request.operation == "activate" {
            guard let code = request.code, code.utf8.count <= 262_144, contexts.count < 64,
                  request.sourceDigest == PluginPackage.digest(Data(code.utf8)) else { throw PluginError.invalidPackage }
            let js = JSContext()!
            js.evaluateScript("var __hop_plugin; Object.defineProperty(globalThis,'definePlugin',{value:function(p){if(__hop_plugin)throw Error('registered');__hop_plugin=p;}});")
            js.evaluateScript(code)
            guard js.exception == nil, js.objectForKeyedSubscript("__hop_plugin")?.isObject == true else { throw PluginError.javascriptError }
            contexts[request.session] = Context(js: js, digest: request.digest, generation: request.generation)
        }
        guard let context = contexts[request.session], context.digest == request.digest, context.generation == request.generation else { throw PluginError.staleSession }
        let js = context.js
        js.exception = nil
        let contextJSON = String(decoding: try JSONEncoder().encode(request.context), as: UTF8.self)
        let argument: String
        let method: String
        switch request.operation {
        case "activate": method = "activate"; argument = contextJSON
        case "event":
            method = "onEvent"
            argument = String(decoding: try JSONEncoder().encode(request.event ?? .null), as: UTF8.self) + "," + contextJSON
        case "action":
            method = "onAction"
            argument = String(decoding: try JSONEncoder().encode(request.action ?? ""), as: UTF8.self) + "," + contextJSON
        default: throw PluginError.invalidPackage
        }
        let script = "(function(){var f=__hop_plugin['\(method)'];var r=typeof f==='function'?f.call(__hop_plugin,\(argument)):undefined;return JSON.stringify(r===undefined?{}:r);})()"
        guard let output = js.evaluateScript(script)?.toString(), js.exception == nil, output.utf8.count <= 262_144 else { throw PluginError.javascriptError }
        return Data(output.utf8)
    }
}

final class RuntimeListener: NSObject, NSXPCListenerDelegate {
    let service = RuntimeService()
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard let parent = Bundle.main.object(forInfoDictionaryKey: "HopPluginParentIdentifier") as? String,
              let team = Bundle.main.object(forInfoDictionaryKey: "HopPluginSigningTeam") as? String else { return false }
        connection.setCodeSigningRequirement("identifier \"\(parent)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(team)\"")
        connection.exportedInterface = NSXPCInterface(with: PluginRuntimeXPC.self)
        connection.exportedObject = service
        connection.resume()
        return true
    }
}

autoreleasepool { _ = JSContext() }
let delegate = RuntimeListener()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
dispatchMain()
