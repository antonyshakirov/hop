import AppKit
import Combine
import HopCore
import SwiftUI

// SPEC: docs/spec.md — Clipboard, Quick picker.
@MainActor
final class ClipboardPickerModel: ObservableObject {
    @Published var query = "" {
        didSet { if query != oldValue { selectedID = nil } }
    }
    @Published var selectedID: UUID?
    @Published private(set) var items: [ClipboardItem]

    init(items: [ClipboardItem]) { self.items = items }

    var results: [ClipboardItem] { ClipboardPicker.results(in: items, query: query) }
    var selection: ClipboardItem? {
        let results = results
        return ClipboardPicker.selectedIndex(id: selectedID, in: results).map { results[$0] }
    }

    func update(_ items: [ClipboardItem]) { self.items = items }

    func move(_ delta: Int) {
        selectedID = ClipboardPicker.moving(id: selectedID, by: delta, in: results)
    }
}

@MainActor
final class ClipboardPickerWindow: NSObject, NSWindowDelegate {
    private(set) var window: NSPanel?
    let model: ClipboardPickerModel
    private let clipboard: ClipboardController
    private let copyItem: (ClipboardItem) -> Void
    private var monitor: Any?
    private var history: AnyCancellable?
    private var activation: AnyCancellable?
    private var previousApp: NSRunningApplication?

    init(clipboard: ClipboardController, copy: ((ClipboardItem) -> Void)? = nil) {
        self.clipboard = clipboard
        model = ClipboardPickerModel(items: clipboard.items)
        copyItem = copy ?? { clipboard.copy($0) }
        super.init()
        history = clipboard.$items.sink { [weak self] in self?.model.update($0) }
        activation = NotificationCenter.default.publisher(for: ModuleActivation.didChange)
            .receive(on: RunLoop.main).sink { [weak self] _ in
                MainActor.assumeIsolated {
                    if !ModuleActivation.isOn("clipboard") { self?.dismiss() }
                }
            }
    }

    func toggle() {
        guard ModuleActivation.isOn("clipboard") else { return }
        if window?.isVisible == true {
            guard (window?.firstResponder as? NSTextView)?.hasMarkedText() != true else { return }
            if let action = ModuleCatalog.open("clipboard"),
               let combo = HotkeyManager.shared.combo(for: action),
               combo.modifiers == ModuleCombo.command,
               handle(keyCode: UInt16(clamping: combo.keyCode), modifiers: NSEvent.ModifierFlags.command.rawValue,
                      editor: window?.firstResponder as? NSTextView) { return }
            dismiss(returnFocus: true)
            return
        }
        model.query = ""
        model.selectedID = nil
        previousApp = NSWorkspace.shared.frontmostApplication
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 540, height: 434),
            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = L10n.t(.tabClipboard, L10n.current).capitalizedFirst
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.delegate = self
        window.level = .floating
        window.appearance = NSAppearance(named: Theme.isDark ? .darkAqua : .aqua)
        window.backgroundColor = NSColor(Theme.background)
        let host = NSHostingController(rootView: ClipboardPickerView(model: model,
            lang: L10n.current, choose: { [weak self] in self?.choose($0) }).hopLayoutDirection())
        host.sizingOptions = []
        window.contentViewController = host
        window.setContentSize(NSSize(width: 540, height: 434))
        window.layoutIfNeeded()
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
            ?? NSScreen.main {
            let visible = screen.visibleFrame
            window.setFrameOrigin(NSPoint(x: visible.midX - window.frame.width / 2,
                                          y: visible.midY - window.frame.height / 2))
        }
        self.window = window
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak window] event in
            guard let self, let window, window.isVisible, event.window === window,
                  self.handle(keyCode: event.keyCode, modifiers: event.modifierFlags.rawValue,
                              editor: window.firstResponder as? NSTextView)
            else { return event }
            return nil
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    @discardableResult
    func handle(keyCode: UInt16, modifiers: UInt, editor: NSTextView? = nil) -> Bool {
        guard editor?.hasMarkedText() != true else { return false }
        guard let action = ClipboardPicker.action(keyCode: keyCode, modifiers: modifiers) else { return false }
        switch action {
        case .choose(let index):
            let results = model.results
            if results.indices.contains(index) { choose(results[index]) }
        case .move(let delta): model.move(delta)
        case .copySelection:
            if let selection = model.selection { choose(selection) }
        case .dismiss: dismiss(returnFocus: true)
        }
        return true
    }

    func choose(_ item: ClipboardItem) {
        guard ModuleActivation.isOn("clipboard"),
              let current = model.results.first(where: { $0.id == item.id }) else { return }
        copyItem(current)
        dismiss(returnFocus: true)
    }

    func dismiss(returnFocus: Bool = false) {
        let previous = previousApp
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        window?.orderOut(nil)
        window?.delegate = nil
        window = nil
        previousApp = nil
        if returnFocus, let application = NSApp, application.isActive, let previous, !previous.isTerminated,
           previous.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            application.yieldActivation(to: previous)
            previous.activate()
        }
    }

    func windowWillClose(_ notification: Notification) { dismiss(returnFocus: true) }
    func windowDidResignKey(_ notification: Notification) { dismiss() }
}

struct ClipboardPickerView: View {
    @ObservedObject var model: ClipboardPickerModel
    let lang: AppLanguage
    var choose: (ClipboardItem) -> Void
    var preview = false
    @State private var searchFocused = false

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.textTertiary)
                if preview {
                    Text(model.query.isEmpty ? L10n.t(.searchLabel, lang) : model.query)
                        .font(Theme.mono(12)).foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    SteadyField(text: $model.query, placeholder: L10n.t(.searchLabel, lang),
                        size: 12, focus: $searchFocused)
                }
                Text("esc").font(Theme.mono(10)).foregroundStyle(Theme.textTertiary)
            }
            .padding(10)
            .background(Theme.fieldBg, in: RoundedRectangle(cornerRadius: 8))
            if model.results.isEmpty {
                Text(L10n.t(model.items.isEmpty ? .clipboardEmpty : .clipboardNoResults, lang))
                    .font(Theme.mono(11)).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if preview {
                VStack(spacing: 3) {
                    ForEach(Array(model.results.prefix(8).enumerated()), id: \.element.id) { index, item in
                        row(item, index: index)
                    }
                    Spacer(minLength: 0)
                }
            } else {
                ScrollViewReader { scroll in
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(Array(model.results.enumerated()), id: \.element.id) { index, item in
                                row(item, index: index).id(item.id)
                            }
                        }
                    }
                    .onChange(of: model.selectedID) { _, id in
                        if let id { scroll.scrollTo(id) }
                    }
                }
            }
        }
        .padding(18).padding(.top, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .onAppear { if !preview { searchFocused = true } }
    }

    private func row(_ item: ClipboardItem, index: Int) -> some View {
        let selected = model.selection?.id == item.id
        return Button { choose(item) } label: {
            HStack(spacing: 10) {
                if let file = item.imageFile, let image = ClipThumbCache.image(file) {
                    Image(nsImage: image).resizable().scaledToFit().frame(width: 36, height: 24)
                } else if let color = ColorSwatch.color(item.colorHex) {
                    RoundedRectangle(cornerRadius: 4).fill(color).frame(width: 24, height: 24)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.controlStroke))
                } else {
                    Image(systemName: item.filePaths == nil ? "text.alignleft" : "doc")
                        .foregroundStyle(Theme.textTertiary).frame(width: 24)
                }
                Text(ClipboardRules.previewLine(item.text)).font(Theme.mono(11))
                    .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                if index < 9 {
                    Text("⌘ \(index + 1)").font(Theme.mono(10)).foregroundStyle(Theme.textSecondary)
                }
            }
            .foregroundStyle(Theme.textPrimary).padding(.horizontal, 10).frame(height: 39)
            .background(selected ? Theme.chipBg : Theme.rowBg, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).hoverHighlight(6)
    }
}
