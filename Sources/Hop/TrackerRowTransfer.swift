import AppKit
import SwiftUI

enum TrackerRowTransfer {
    static let typeIdentifier = "com.antonshakirov.hop.tracker-row"

    static func provider(row: UUID, session: UUID) -> NSItemProvider {
        let data = Data((session.uuidString + ":" + row.uuidString).utf8)
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: typeIdentifier, visibility: .ownProcess) {
            completion in
            completion(data, nil)
            return nil
        }
        return provider
    }

    static func read(_ providers: [NSItemProvider], session: UUID,
                     completion: @escaping (UUID?) -> Void) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(typeIdentifier) })
        else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
            let row = data.flatMap { data -> UUID? in
                guard data.count == 73, let text = String(data: data, encoding: .utf8),
                      text.hasPrefix(session.uuidString + ":") else { return nil }
                return UUID(uuidString: String(text.suffix(36)))
            }
            DispatchQueue.main.async { completion(row) }
        }
        return true
    }
}

struct TrackerTransferSource: ViewModifier {
    let enabled: Bool
    let row: UUID
    let session: UUID
    let onBegin: () -> Void

    @ViewBuilder func body(content: Content) -> some View {
        if enabled {
            content.onDrag {
                onBegin()
                return TrackerRowTransfer.provider(row: row, session: session)
            }
        } else {
            content
        }
    }
}

struct TrackerTransferTarget: ViewModifier {
    let enabled: Bool
    let session: UUID
    let onDrop: (UUID, CGPoint) -> Void

    @ViewBuilder func body(content: Content) -> some View {
        if enabled {
            content.onDrop(of: [TrackerRowTransfer.typeIdentifier],
                           delegate: Receiver(session: session, onDrop: onDrop))
        } else {
            content
        }
    }

    private struct Receiver: DropDelegate {
        let session: UUID
        let onDrop: (UUID, CGPoint) -> Void

        func validateDrop(info: DropInfo) -> Bool {
            info.hasItemsConforming(to: [TrackerRowTransfer.typeIdentifier])
        }

        func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

        func performDrop(info: DropInfo) -> Bool {
            let point = info.location
            PanelFrameLog.write("trackerNativeDrop", "point=\(point)")
            return TrackerRowTransfer.read(
                info.itemProviders(for: [TrackerRowTransfer.typeIdentifier]), session: session
            ) { row in
                PanelFrameLog.write("trackerNativeRead", "accepted=\(row != nil)")
                if let row { onDrop(row, point) }
            }
        }
    }
}
