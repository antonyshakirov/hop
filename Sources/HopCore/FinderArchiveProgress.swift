import Foundation

public enum ArchiveInvocation: Equatable, Sendable {
    case manual
    case finder

    public var recordsManualJob: Bool {
        self == .manual
    }
}

/// Failure reasons shared by archive jobs and the transient Finder progress
/// window. Keeping these in HopCore makes the window lifecycle testable without
/// AppKit.
public enum ArchiveFailureKind: Error, Equatable, Sendable {
    case helper
    case tool
    case empty
    case denied
}

/// Events emitted by a Finder-triggered extraction.
public enum FinderArchiveProgressEvent: Equatable, Sendable {
    case waitingForHelper
    case extracting
    case succeeded
    case failed(ArchiveFailureKind)
}

/// Pure state for the small window shown after an archive is opened from Finder.
/// Success is the only terminal state that dismisses it; a failure remains
/// visible so the user can understand what happened.
public struct FinderArchiveProgressState: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case waitingForHelper
        case extracting
        case succeeded
        case failed(ArchiveFailureKind)
    }

    public let fileName: String
    public private(set) var phase: Phase

    public init(fileName: String) {
        self.fileName = fileName
        phase = .extracting
    }

    public var shouldKeepWindowOpen: Bool {
        phase != .succeeded
    }

    public mutating func receive(_ event: FinderArchiveProgressEvent) {
        switch phase {
        case .succeeded, .failed:
            return
        case .waitingForHelper, .extracting:
            break
        }
        switch event {
        case .waitingForHelper:
            phase = .waitingForHelper
        case .extracting:
            phase = .extracting
        case .succeeded:
            phase = .succeeded
        case .failed(let failure):
            phase = .failed(failure)
        }
    }
}

/// One Finder open event can contain several selected archives. They share one
/// window: it closes only when every item succeeds, and any failure turns the
/// window into a persistent error surface.
public struct FinderArchiveBatchState: Equatable, Sendable {
    public enum Presentation: Equatable, Sendable {
        case progress
        case failure
        case close
    }

    public struct Item: Identifiable, Equatable, Sendable {
        public let id: UUID
        public var progress: FinderArchiveProgressState
    }

    public private(set) var items: [Item]

    public init(files: [(id: UUID, fileName: String)]) {
        items = files.map {
            Item(
                id: $0.id,
                progress: FinderArchiveProgressState(fileName: $0.fileName))
        }
    }

    public var presentation: Presentation {
        if items.contains(where: {
            if case .failed = $0.progress.phase { return true }
            return false
        }) {
            return .failure
        }
        if !items.isEmpty,
           items.allSatisfy({ $0.progress.phase == .succeeded }) {
            return .close
        }
        return .progress
    }

    public mutating func receive(
        _ event: FinderArchiveProgressEvent,
        for id: UUID
    ) {
        guard let index = items.firstIndex(where: { $0.id == id }) else {
            return
        }
        items[index].progress.receive(event)
    }
}
