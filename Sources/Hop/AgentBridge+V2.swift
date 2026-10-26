import Foundation
import HopCore

extension AgentBridge {
    func performConfirmed(_ request: AgentRequestV2, on model: AppModel) -> AgentResultV2 {
        switch request.command {
        case .completeTodo(let id):
            guard let item = model.todos.list.items.first(where: { $0.id == id }) else { return .rejected("todo_not_found") }
            if item.done { return .noChange() }
            model.todos.toggle(id)
            return .applied(ids: [id])
        case .deleteTodo(let id):
            guard model.todos.list.items.contains(where: { $0.id == id }) else { return .rejected("todo_not_found") }
            model.todos.delete(id)
            return .applied(ids: [id])
        case .legacy(let command):
            switch command {
            case .todoAdd:
                let before = Set(model.todos.list.items.map(\.id))
                perform(command, on: model)
                let added = model.todos.list.items.filter { !before.contains($0.id) }.map(\.id)
                return added.count == 1 ? .applied(ids: added) : .indeterminate()
            case .trackerStart(let name):
                let matches = model.tracker.engine.data.tasks.filter {
                    $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                }
                guard matches.count < 2 else { return .rejected("ambiguous_tracking_task") }
                if let task = matches.first, model.tracker.engine.activeTaskIDs.contains(task.id) { return .noChange() }
                perform(command, on: model)
                let ids = model.tracker.engine.data.tasks.filter {
                    $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                }.map(\.id)
                return .applied(ids: ids)
            case .trackerStop:
                let ids = Array(model.tracker.engine.activeTaskIDs)
                if ids.isEmpty { return .noChange() }
                perform(command, on: model)
                return .applied(ids: ids)
            case .timerPause, .timerReset, .timerStart, .stopwatchStart, .stopwatchStop:
                perform(command, on: model)
                return .applied()
            default: return .rejected("unsupported_command")
            }
        }
    }
}
