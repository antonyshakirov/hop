import AppKit
import CoreGraphics
import HopCore
import Vision

/// Text and QR codes off the screen: a hotkey (or the panel button) hands you
/// macOS's own selection crosshair, and whatever Vision reads inside the frame
/// lands in the clipboard history — already copied, no file on the desktop.
///
/// The angle that makes this worth having over Live Text or a standalone
/// grabber: the result is a HISTORY entry, searchable next to everything else
/// you copied. Recognition is Apple's Vision, entirely on this Mac and offline.
@MainActor
final class ScreenTextController: ObservableObject {
    enum State: Equatable {
        case idle
        /// The crosshair is up; the user is framing an area.
        case selecting
        case reading
        /// Read and stored — the character count is shown briefly as a receipt.
        case done(Int)
        /// The pass worked but found neither text nor a code.
        case empty
        /// Screen Recording is not granted yet (macOS has just been asked).
        case denied
        case failed
    }

    @Published private(set) var state: State = .idle
    /// The last text read, kept so the window can SHOW it: a silent copy into
    /// the clipboard history left no sign anything had happened (Anton,
    /// 2026-07-25). The window edits this freely; the history keeps the
    /// recognized original until the user copies an edited version.
    @Published var recognized: String = ""
    /// Ask the app to bring the recognition window forward (wired in AppModel).
    var onResult: (() -> Void)?

    private let clipboard: ClipboardController
    /// Screen Recording is what macOS calls the permission; the settings pane
    /// deep link lands the user exactly on that list.
    static let privacySettingsURL =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"

    init(clipboard: ClipboardController) {
        self.clipboard = clipboard
    }

    var isBusy: Bool { state == .selecting || state == .reading }

    /// Frame an area, read it, store the result. Cancelling the selection
    /// (Escape) is not a failure: the state goes quietly back to idle.
    func capture() {
        guard !isBusy, !Snapshot.active else { return }
        // Ask BEFORE the crosshair: without the permission the capture would come
        // back as a black rectangle, which reads as "the feature is broken".
        guard CGPreflightScreenCaptureAccess() else {
            _ = CGRequestScreenCaptureAccess()   // one-time system prompt
            state = .denied
            return
        }
        state = .selecting
        Task {
            guard let file = await Self.selectArea() else {
                state = .idle
                return
            }
            state = .reading
            let text = await Self.read(file)
            try? FileManager.default.removeItem(at: file)
            guard let text else {
                settle(.empty)
                return
            }
            store(text)
            settle(.done(text.count))
        }
    }

    /// A picture that already exists — dropped on the window or pasted into it.
    /// The same recognition, minus the crosshair; no screen-recording permission
    /// is involved because nothing is captured from the screen.
    func recognize(imageAt url: URL) {
        guard !isBusy, !Snapshot.active else { return }
        state = .reading
        Task {
            let text = await Self.read(url)
            guard let text else {
                settle(.empty)
                return
            }
            store(text)
            settle(.done(text.count))
        }
    }

    /// ⌘V into the window: a copied image (a screenshot on the clipboard) is
    /// recognized; a copied FILE is read from disk.
    func recognizeFromPasteboard() {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let first = urls.first {
            recognize(imageAt: first)
            return
        }
        guard let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) else {
            settle(.empty)
            return
        }
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("hop-paste-\(UUID().uuidString).png")
        // normalize through a PNG on disk so ONE reading path serves every source
        guard let rep = NSBitmapImageRep(data: data),
              let png = rep.representation(using: .png, properties: [:]),
              (try? png.write(to: file)) != nil else {
            settle(.failed)
            return
        }
        recognize(imageAt: file)
    }

    /// The window's edits stay in the window until they are copied — a stray
    /// keystroke must not rewrite what is already in the history.
    func editRecognized(_ text: String) {
        recognized = text
    }

    /// The copy button: whatever the window shows right now goes to the
    /// pasteboard AND into the history as a fresh entry.
    func copyRecognized() {
        let text = recognized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        clipboard.remember(external: text)
    }

    /// One place where a result becomes state: the window shows it, the history
    /// keeps it, the pasteboard carries it.
    private func store(_ text: String) {
        recognized = text
        clipboard.remember(external: text)
        onResult?()
    }

    /// Clear a receipt (or a complaint) after a moment, so the module returns to
    /// its resting state on its own — nothing here is worth a dialog.
    private func settle(_ result: State) {
        state = result
        Task {
            try? await Task.sleep(for: .seconds(3))
            if state == result { state = .idle }
        }
    }

    /// macOS's own interactive capture. Using the system tool rather than a
    /// hand-rolled overlay gives the real crosshair — magnifier, live dimensions,
    /// space to reposition — for free, and it is the UI users already know.
    /// Escape leaves no file behind, which is exactly how a cancel is detected.
    private nonisolated static func selectArea() async -> URL? {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("hop-screen-\(UUID().uuidString).png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // -i interactive selection, -x no shutter sound, -o no window shadow
        process.arguments = ["-i", "-x", "-o", "-t", "png", file.path]
        do {
            try process.run()
        } catch {
            return nil
        }
        await withCheckedContinuation { continuation in
            // waitUntilExit blocks, so it waits off the main thread
            DispatchQueue.global(qos: .userInitiated).async {
                process.waitUntilExit()
                continuation.resume()
            }
        }
        guard process.terminationStatus == 0,
              FileManager.default.fileExists(atPath: file.path) else { return nil }
        return file
    }

    /// One Vision pass over the captured area: text plus barcodes, since it is
    /// the same walk over the same pixels. Runs off the main thread — recognition
    /// on a large selection takes long enough to stutter the UI.
    private nonisolated static func read(_ file: URL) async -> String? {
        let languages = recognitionLanguages()
        return await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }

            let textRequest = VNRecognizeTextRequest()
            textRequest.recognitionLevel = .accurate
            textRequest.usesLanguageCorrection = true
            if !languages.isEmpty { textRequest.recognitionLanguages = languages }
            let codeRequest = VNDetectBarcodesRequest()

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([textRequest, codeRequest])
            } catch {
                return nil
            }

            let observations = textRequest.results ?? []
            let lines = ScreenTextRules.readingOrder(observations.map(\.boundingBox))
                .compactMap { observations[$0].topCandidates(1).first?.string }
            let codes = (codeRequest.results ?? []).compactMap(\.payloadStringValue)
            return ScreenTextRules.assemble(lines: lines, barcodes: codes)
        }.value
    }

    /// The app's own language plus English, mapped onto whatever Vision actually
    /// supports on this machine (its list is versioned, and an unsupported tag
    /// makes the whole request fail). Automatic detection is deliberately NOT
    /// used: it guesses badly on mixed Latin/Cyrillic screens, and the UI
    /// language is a far better hint about what its owner reads.
    private nonisolated static func recognitionLanguages() -> [String] {
        let supported = (try? VNRecognizeTextRequest().supportedRecognitionLanguages()) ?? []
        guard !supported.isEmpty else { return [] }
        var out: [String] = []
        for code in [L10n.current.rawValue, "en"] {
            // prefix match: Vision spells them "en-US", "ru-RU", "zh-Hans"
            if let match = supported.first(where: { $0.hasPrefix(code) }), !out.contains(match) {
                out.append(match)
            }
        }
        return out
    }
}
