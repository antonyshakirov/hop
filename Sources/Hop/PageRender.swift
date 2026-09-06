import AppKit
import HopCore
import PDFKit
import WebKit

/// SPEC: docs/spec.md — "Converter: web pages".
@MainActor
enum PageRender {
    private static let layoutWidth: CGFloat = 800
    private static let layoutHeight: CGFloat = 900
    private static let loadTimeout: TimeInterval = 30

    /// Web fonts and late stylesheets arrive after `didFinish`.
    private static let settleNanoseconds: UInt64 = 400_000_000

    private static let paperSize = NSSize(width: 595, height: 842)
    private static let paperMargin: CGFloat = 36

    /// A loaded page; `finish()` releases its WebContent process and window.
    final class Page {
        let webView: WKWebView
        let title: String?
        fileprivate let window: NSWindow
        fileprivate let loader: PageLoad

        fileprivate init(webView: WKWebView, window: NSWindow, loader: PageLoad, title: String?) {
            self.webView = webView
            self.window = window
            self.loader = loader
            self.title = title
        }

        @MainActor
        func finish() {
            webView.navigationDelegate = nil
            webView.stopLoading()
            window.contentView = nil
            window.close()
        }
    }

    /// Load a page — a file on disk or an address — and wait for it to settle.
    static func load(_ url: URL) async -> Page? {
        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        let frame = NSRect(x: 0, y: 0, width: layoutWidth, height: layoutHeight)
        let webView = WKWebView(frame: frame, configuration: configuration)

        // a view in no window is not guaranteed to render, and a snapshot asks
        // it to; off-screen rather than hidden, so it draws without being seen
        let window = NSWindow(contentRect: frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isExcludedFromWindowsMenu = true
        window.collectionBehavior = [.stationary, .ignoresCycle, .canJoinAllSpaces]
        window.contentView = webView
        window.setFrameOrigin(NSPoint(x: -30_000, y: -30_000))
        window.orderFrontRegardless()

        let loader = PageLoad()
        webView.navigationDelegate = loader
        if url.isFileURL {
            // the folder, not just the file: a saved page keeps its assets beside it
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            webView.load(URLRequest(url: url))
        }

        guard await loader.wait(timeout: loadTimeout) else {
            webView.navigationDelegate = nil
            window.contentView = nil
            window.close()
            return nil
        }
        try? await Task.sleep(nanoseconds: settleNanoseconds)
        let title = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Page(webView: webView, window: window, loader: loader,
                    title: (title?.isEmpty ?? true) ? nil : title)
    }

    // MARK: - PDF

    /// WORKAROUND: `WKWebView.printOperation` against an off-screen window never
    /// gets its layout back, keeps the page range `1…NSIntegerMax` and prints
    /// until the disk fills. WebKit's own render is cut into sheets instead.
    /// SPEC: docs/spec.md — "Converter: web pages".
    static func writePDF(_ page: Page, to url: URL) async -> Bool {
        guard let data = await pdfData(page),
              let source = PDFDocument(data: data),
              let long = source.page(at: 0) else { return false }
        let bounds = long.bounds(for: .mediaBox)
        let printable = NSSize(width: paperSize.width - paperMargin * 2,
                               height: paperSize.height - paperMargin * 2)
        guard let plan = PagePagination.plan(
            contentWidth: Double(bounds.width), contentHeight: Double(bounds.height),
            printableWidth: Double(printable.width), printableHeight: Double(printable.height)
        ) else { return false }

        let output = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: paperSize)
        guard let consumer = CGDataConsumer(data: output),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else { return false }

        for index in 0..<plan.pageCount {
            context.beginPDFPage(nil)
            context.saveGState()
            // a sheet's origin is bottom-left; slices run from the source's top down
            let sliceTop = bounds.height - CGFloat(plan.sourceOffset(ofPage: index))
            context.translateBy(x: paperMargin, y: paperSize.height - paperMargin)
            context.scaleBy(x: CGFloat(plan.scale), y: CGFloat(plan.scale))
            context.translateBy(x: -bounds.minX, y: -sliceTop)
            context.clip(to: CGRect(x: bounds.minX, y: sliceTop - printable.height / CGFloat(plan.scale),
                                    width: bounds.width,
                                    height: printable.height / CGFloat(plan.scale)))
            long.draw(with: .mediaBox, to: context)
            context.restoreGState()
            context.endPDFPage()
        }
        context.closePDF()
        return output.write(to: url, atomically: true)
    }

    private static func pdfData(_ page: Page) async -> Data? {
        await withCheckedContinuation { continuation in
            page.webView.createPDF(configuration: WKPDFConfiguration()) { result in
                continuation.resume(returning: try? result.get())
            }
        }
    }

    // MARK: - A picture of the whole page

    static func writePNG(_ page: Page, to url: URL) async -> Bool {
        let measured = await contentHeight(page)
        let width = page.webView.frame.width
        let height = max(measured, page.webView.frame.height)

        // grown to the document's height, so the whole page is "on screen"
        page.window.setContentSize(NSSize(width: width, height: height))
        page.webView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        try? await Task.sleep(nanoseconds: settleNanoseconds)

        let scale = HTMLConversion.snapshotScale(contentHeight: Double(height),
                                                 cap: HTMLConversion.snapshotHeightCap)
        let configuration = WKSnapshotConfiguration()
        configuration.rect = page.webView.bounds
        configuration.snapshotWidth = NSNumber(value: Double(width) * scale)

        guard let image = await snapshot(page, configuration: configuration),
              let tiff = image.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiff),
              let data = representation.representation(using: .png, properties: [:])
        else { return false }
        return (try? data.write(to: url)) != nil
    }

    private static func snapshot(
        _ page: Page, configuration: WKSnapshotConfiguration
    ) async -> NSImage? {
        await withCheckedContinuation { continuation in
            page.webView.takeSnapshot(with: configuration) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    private static func contentHeight(_ page: Page) async -> CGFloat {
        let script = "Math.max(document.body ? document.body.scrollHeight : 0,"
            + " document.documentElement.scrollHeight)"
        guard let value = await evaluate(page, script) as? NSNumber else { return 0 }
        return CGFloat(truncating: value)
    }

    // MARK: - The page's own markup

    /// The DOM after loading — the only route to the text of an archive or address.
    static func source(of page: Page) async -> String? {
        await evaluate(page, "document.documentElement.outerHTML") as? String
    }

    /// WORKAROUND: the async overload of `evaluateJavaScript` traps when a
    /// script returns nothing, and a page is entitled to return nothing.
    private static func evaluate(_ page: Page, _ script: String) async -> Any? {
        await withCheckedContinuation { continuation in
            page.webView.evaluateJavaScript(script) { value, _ in
                continuation.resume(returning: value)
            }
        }
    }
}

/// Waits for one navigation, resuming exactly once: a page can both fail and
/// time out, and resuming a checked continuation twice is a crash.
private final class PageLoad: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Bool, Never>?
    private var settled = false

    func wait(timeout: TimeInterval) async -> Bool {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.settle(false)
            }
        }
    }

    private func settle(_ loaded: Bool) {
        guard !settled else { return }
        settled = true
        let pending = continuation
        continuation = nil
        pending?.resume(returning: loaded)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        settle(true)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        settle(false)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        settle(false)
    }
}
