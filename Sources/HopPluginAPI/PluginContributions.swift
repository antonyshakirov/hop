import Foundation

public enum PluginPatch<T: Equatable>: Equatable { case unchanged, clear, value(T) }

public struct PluginTheme: Codable, Equatable {
    public let dark: [String: String]?
    public let light: [String: String]?
    public let fontScale: Double?
}
public struct PluginNode: Codable, Equatable {
    public let type: String
    public let text: String?
    public let style: String?
    public let title: String?
    public let action: String?
    public let module: String?
    public let children: [PluginNode]?
}
public struct PluginPanel: Codable, Equatable {
    public let mode: String
    public let width: Double?
    public let nodes: [PluginNode]
}
public struct PluginCommand: Codable, Equatable {
    public let type: String
    public let seconds: Double?
}
public struct PluginContributions: Equatable {
    public let theme: PluginPatch<PluginTheme>
    public let panel: PluginPatch<PluginPanel>
    public let commands: [PluginCommand]
    public static func decode(_ data: Data, capabilities: Set<String>) throws -> Self {
        try PluginJSONBounds.check(data, maximumBytes: 262_144)
        guard data.count <= 262_144,
              let value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(value.keys).isSubset(of: ["theme", "panel", "commands"]) else { throw PluginError.invalidContribution }
        let theme: PluginPatch<PluginTheme> = try patch(value, "theme", capability: "ui.theme", grants: capabilities)
        if case .value(let tokens) = theme {
            let allowed: Set<String> = ["accent", "background", "foreground", "secondary", "surface", "line"]
            for colors in [tokens.dark, tokens.light].compactMap({ $0 }) {
                guard Set(colors.keys).isSubset(of: allowed), colors.values.allSatisfy({ $0.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil }) else { throw PluginError.invalidContribution }
            }
            guard tokens.fontScale.map({ $0.isFinite && (0.8...1.3).contains($0) }) ?? true else { throw PluginError.invalidContribution }
        }
        let panel: PluginPatch<PluginPanel> = try patch(value, "panel", capability: "ui.panel", grants: capabilities)
        if case .value(let layout) = panel {
            guard ["replace", "append"].contains(layout.mode), layout.width.map({ $0.isFinite && (300...800).contains($0) }) ?? true else { throw PluginError.invalidContribution }
            var count = 0, modules = Set<String>()
            try validate(layout.nodes, depth: 0, count: &count, modules: &modules)
        }
        let commands: [PluginCommand]
        if let raw = value["commands"] {
            guard let array = raw as? [[String: Any]] else { throw PluginError.invalidContribution }
            commands = try JSONDecoder().decode([PluginCommand].self, from: JSONSerialization.data(withJSONObject: array))
        } else { commands = [] }
        guard commands.count <= 8, commands.isEmpty || capabilities.contains("timer.control") else { throw PluginError.permissionDenied }
        for command in commands {
            guard command.type == "timer.stop" || (command.type == "timer.start" && command.seconds.map({ $0.isFinite && (1...28_800).contains($0) }) == true) else { throw PluginError.invalidContribution }
        }
        return Self(theme: theme, panel: panel, commands: commands)
    }
    private static func patch<T: Decodable & Equatable>(_ value: [String: Any], _ key: String, capability: String, grants: Set<String>) throws -> PluginPatch<T> {
        guard let raw = value[key] else { return .unchanged }
        guard grants.contains(capability) else { throw PluginError.permissionDenied }
        if raw is NSNull { return .clear }
        guard let object = raw as? [String: Any] else { throw PluginError.invalidContribution }
        return .value(try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: object)))
    }
    private static func validate(_ nodes: [PluginNode], depth: Int, count: inout Int, modules: inout Set<String>) throws {
        guard depth <= 8 else { throw PluginError.invalidContribution }
        for node in nodes {
            count += 1
            guard count <= 256 else { throw PluginError.invalidContribution }
            switch node.type {
            case "text":
                guard let text = node.text, text.count <= 4096, [nil, "title", "body", "caption"].contains(node.style) else { throw PluginError.invalidContribution }
            case "button":
                guard let title = node.title, !title.isEmpty, title.count <= 128, let action = node.action,
                      action.range(of: "^[A-Za-z0-9._-]{1,128}$", options: .regularExpression) != nil else { throw PluginError.invalidContribution }
            case "module":
                guard let id = node.module, ["timer", "system", "todos", "tracker", "clipboard", "sound"].contains(id), modules.insert(id).inserted else { throw PluginError.invalidContribution }
            case "row", "column": try validate(node.children ?? [], depth: depth + 1, count: &count, modules: &modules)
            case "divider", "spacer": break
            default: throw PluginError.invalidContribution
            }
            guard node.type == "row" || node.type == "column" || (node.children?.isEmpty ?? true) else { throw PluginError.invalidContribution }
        }
    }
}
