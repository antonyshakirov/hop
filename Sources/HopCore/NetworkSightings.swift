import Foundation

/// SPEC: docs/spec.md — "Network access". One program reaching one destination.
public struct NetworkSighting: Codable, Hashable, Sendable {
    public var app: String
    /// The program's executable, for its name and icon.
    public var path: String?
    public var host: String?
    public var address: String
    public var port: String
    public var verdict: NetworkRule.Action
    public var count: Int
    public var last: Date

    public init(app: String, path: String?, host: String?, address: String, port: String,
                verdict: NetworkRule.Action, count: Int = 1, last: Date) {
        self.app = app
        self.path = path
        self.host = host
        self.address = address
        self.port = port
        self.verdict = verdict
        self.count = count
        self.last = last
    }

    /// The name a rule would use: the host when the connection came with one.
    public var destination: String { host ?? address }
}

/// What the filter has seen, capped so it cannot grow for ever.
public struct NetworkSightings: Sendable {
    public static let capacity = 3000
    public private(set) var byKey: [String: NetworkSighting] = [:]

    public init() {}

    public mutating func record(app: String, path: String?, host: String?, address: String, port: String,
                                verdict: NetworkRule.Action, at date: Date) {
        let key = app + "\u{1F}" + (host ?? address)
        if var known = byKey[key] {
            known.count += 1
            known.last = date
            known.verdict = verdict
            known.address = address
            known.port = port
            if known.path == nil { known.path = path }
            byKey[key] = known
        } else {
            byKey[key] = NetworkSighting(app: app, path: path, host: host, address: address, port: port,
                                         verdict: verdict, last: date)
        }
        guard byKey.count > Self.capacity else { return }
        let oldest = byKey.values.sorted { $0.last < $1.last }.prefix(byKey.count - Self.capacity * 9 / 10)
        for sighting in oldest { byKey.removeValue(forKey: sighting.app + "\u{1F}" + sighting.destination) }
    }

    public var all: [NetworkSighting] { byKey.values.sorted { $0.last > $1.last } }

    public static func encode(_ sightings: [NetworkSighting]) -> Data {
        (try? JSONEncoder().encode(sightings)) ?? Data("[]".utf8)
    }

    public static func decode(_ data: Data?) -> [NetworkSighting] {
        guard let data, let list = try? JSONDecoder().decode([NetworkSighting].self, from: data) else { return [] }
        return list
    }
}

/// One program in the window: its destinations and whether it may connect at all.
public struct NetworkProgram: Equatable, Sendable {
    public var app: String
    public var path: String?
    public var destinations: [NetworkSighting]
    public var last: Date?
    public var blocked: Bool

    /// Programs seen, plus those that only have rules so far, newest first.
    public static func group(_ sightings: [NetworkSighting], rules: [NetworkRule]) -> [NetworkProgram] {
        var programs: [String: NetworkProgram] = [:]
        for sighting in sightings {
            var program = programs[sighting.app]
                ?? NetworkProgram(app: sighting.app, path: sighting.path, destinations: [], last: nil, blocked: false)
            program.destinations.append(sighting)
            program.last = max(program.last ?? sighting.last, sighting.last)
            if program.path == nil { program.path = sighting.path }
            programs[sighting.app] = program
        }
        for rule in rules where programs[rule.app] == nil {
            programs[rule.app] = NetworkProgram(app: rule.app, path: nil, destinations: [], last: nil, blocked: false)
        }
        for key in programs.keys {
            programs[key]?.blocked = rules.contains { $0.app == key && $0.host == nil && $0.action == .deny }
            programs[key]?.destinations.sort { $0.last > $1.last }
        }
        return programs.values.sorted {
            switch ($0.last, $1.last) {
            case let (a?, b?): return a > b
            case (nil, _?): return false
            case (_?, nil): return true
            default: return $0.app < $1.app
            }
        }
    }
}

/// SPEC: docs/spec.md — "Network access", the window's order.
public enum NetworkSort: String, CaseIterable, Sendable {
    case appearance, name, recent
}

/// SPEC: docs/spec.md — "Network access", a list that stays put.
public enum NetworkProgramOrder {
    /// Keeps every program where it already stands and adds the ones that went
    /// online since at the bottom, in the order they did.
    public static func update(_ order: [String], with programs: [NetworkProgram]) -> [String] {
        let known = Set(order)
        let fresh = online(programs).filter { !known.contains($0.app) }
            .sorted { ($0.last ?? .distantPast, $0.app) < ($1.last ?? .distantPast, $1.app) }
            .map(\.app)
        return order + fresh
    }

    /// Newest first, taken once and then kept like any other order.
    public static func recent(_ programs: [NetworkProgram]) -> [String] {
        online(programs).sorted { ($0.last ?? .distantPast) > ($1.last ?? .distantPast) }.map(\.app)
    }

    /// Went online: the programs the filter has seen, never the rule for every program.
    public static func online(_ programs: [NetworkProgram]) -> [NetworkProgram] {
        programs.filter { !$0.destinations.isEmpty && $0.app != NetworkRule.anyProgram }
    }

    /// Not online yet: installed programs and programs that only have rules, by
    /// name, so a rule made for one leaves it where it was.
    public static func waiting(_ programs: [NetworkProgram], installed: [(id: String, name: String)],
                               name: (String) -> String) -> [String] {
        let seen = Set(online(programs).map(\.app))
        var ids = installed.map(\.id).filter { !seen.contains($0) }
        let listed = Set(ids)
        ids += programs.map(\.app).filter {
            !seen.contains($0) && !listed.contains($0) && $0 != NetworkRule.anyProgram
        }
        return ids.map { ($0, name($0)) }
            .sorted { $0.1.localizedStandardCompare($1.1) == .orderedAscending }
            .map(\.0)
    }

    /// Merges what the filter reports into what was seen before, so a restarted
    /// filter, whose log starts empty, does not empty the list.
    public static func merge(_ known: [String: NetworkSighting], _ fetched: [NetworkSighting])
        -> [String: NetworkSighting] {
        var result = known
        for sighting in fetched {
            let key = sighting.app + "\u{1F}" + sighting.destination
            if var old = result[key] {
                old.count = max(old.count, sighting.count)
                if sighting.last >= old.last {
                    old.last = sighting.last
                    old.verdict = sighting.verdict
                    old.address = sighting.address
                    old.port = sighting.port
                }
                if old.path == nil { old.path = sighting.path }
                result[key] = old
            } else {
                result[key] = sighting
            }
        }
        return result
    }
}
