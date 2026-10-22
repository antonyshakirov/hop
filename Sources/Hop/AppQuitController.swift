import AppKit
import Combine
import HopCore

@MainActor
protocol AppQuitBackend: AnyObject {
    var applications: [AppQuitApplication] { get }
    func requestQuit(_ application: AppQuitApplication) -> Bool
    func observeChanges(_ changed: @escaping @MainActor () -> Void)
    func icon(for application: AppQuitApplication) -> NSImage?
}

enum AppQuitRequestState: Equatable {
    case requested
    case refused
}

@MainActor
final class AppQuitController: ObservableObject {
    static let pinnedDefaultsKey = "appQuitPinnedBundleIdentifiers"

    @Published private(set) var applications: [AppQuitApplication] = []
    @Published private(set) var pinnedBundleIdentifiers: Set<String>
    @Published private(set) var requestStates: [AppQuitApplication.ID: AppQuitRequestState] = [:]

    private let backend: AppQuitBackend
    private let defaults: UserDefaults
    private let ownProcessIdentifier: Int32
    private let ownBundleIdentifier: String?
    private let preview: Bool

    var unpinnedCount: Int { applications.filter { !isPinned($0) }.count }

    init(backend: AppQuitBackend? = nil, defaults: UserDefaults = .standard,
         ownProcessIdentifier: Int32 = ProcessInfo.processInfo.processIdentifier,
         ownBundleIdentifier: String? = Bundle.main.bundleIdentifier, preview: Bool? = nil) {
        self.backend = backend ?? NativeAppQuitBackend()
        self.defaults = defaults
        self.ownProcessIdentifier = ownProcessIdentifier
        self.ownBundleIdentifier = ownBundleIdentifier
        self.preview = preview ?? Snapshot.active
        pinnedBundleIdentifiers = Set((defaults.stringArray(forKey: Self.pinnedDefaultsKey) ?? [])
            .compactMap { AppQuitPolicy.pinIdentifier($0) })
        self.backend.observeChanges { [weak self] in self?.refresh() }
        refresh()
    }

    func refresh() {
        applications = AppQuitPolicy.visibleApplications(backend.applications, ownProcessIdentifier: ownProcessIdentifier,
                                                         ownBundleIdentifier: ownBundleIdentifier)
        let running = Set(applications.map(\.id))
        requestStates = requestStates.filter { running.contains($0.key) }
    }

    func isPinned(_ application: AppQuitApplication) -> Bool {
        guard let identifier = application.pinIdentifier else { return false }
        return pinnedBundleIdentifiers.contains(identifier)
    }

    func setPinned(_ pinned: Bool, for id: AppQuitApplication.ID) {
        guard !preview else { return }
        refresh()
        guard let application = applications.first(where: { $0.id == id }),
              let identifier = application.pinIdentifier else { return }
        if pinned { pinnedBundleIdentifiers.insert(identifier) }
        else { pinnedBundleIdentifiers.remove(identifier) }
        defaults.set(pinnedBundleIdentifiers.sorted(), forKey: Self.pinnedDefaultsKey)
    }

    func quit(_ id: AppQuitApplication.ID) {
        guard !preview else { return }
        refresh()
        guard let application = applications.first(where: { $0.id == id }), !isPinned(application) else { return }
        let sent = backend.requestQuit(application)
        requestStates[id] = sent ? .requested : .refused
        refresh()
    }

    func quitAllUnpinned() {
        guard !preview else { return }
        refresh()
        let candidates = AppQuitPolicy.quitCandidates(applications, pinnedBundleIdentifiers: pinnedBundleIdentifiers,
                                                      ownProcessIdentifier: ownProcessIdentifier,
                                                      ownBundleIdentifier: ownBundleIdentifier)
        for application in candidates { quit(application.id) }
    }

    func icon(for application: AppQuitApplication) -> NSImage? { backend.icon(for: application) }
}

@MainActor
final class NativeAppQuitBackend: AppQuitBackend {
    private let workspace: NSWorkspace
    private let notifications: NotificationCenter
    private var observers: [NSObjectProtocol] = []

    init(workspace: NSWorkspace? = nil) {
        let resolved = workspace ?? .shared
        self.workspace = resolved
        notifications = resolved.notificationCenter
    }

    deinit {
        for observer in observers { notifications.removeObserver(observer) }
    }

    var applications: [AppQuitApplication] { workspace.runningApplications.map(descriptor) }

    func observeChanges(_ changed: @escaping @MainActor () -> Void) {
        for observer in observers { notifications.removeObserver(observer) }
        observers = [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification].map { name in
            notifications.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in changed() }
            }
        }
    }

    func requestQuit(_ application: AppQuitApplication) -> Bool {
        guard !Snapshot.active, application.id.launchDate != nil,
              let running = NSRunningApplication(processIdentifier: application.id.processIdentifier),
              descriptor(running).id == application.id,
              !AppQuitPolicy.visibleApplications([descriptor(running)],
                  ownProcessIdentifier: ProcessInfo.processInfo.processIdentifier,
                  ownBundleIdentifier: Bundle.main.bundleIdentifier).isEmpty else { return false }
        return running.terminate()
    }

    func icon(for application: AppQuitApplication) -> NSImage? {
        guard let running = NSRunningApplication(processIdentifier: application.id.processIdentifier),
              descriptor(running).id == application.id else { return nil }
        return running.icon
    }

    private func descriptor(_ application: NSRunningApplication) -> AppQuitApplication {
        AppQuitApplication(processIdentifier: application.processIdentifier,
                           bundleIdentifier: application.bundleIdentifier,
                           name: application.localizedName ?? application.bundleURL?.deletingPathExtension().lastPathComponent
                               ?? application.bundleIdentifier ?? String(application.processIdentifier),
                           launchDate: application.launchDate, bundlePath: application.bundleURL?.path,
                           isRegular: application.activationPolicy == .regular, isTerminated: application.isTerminated)
    }
}
