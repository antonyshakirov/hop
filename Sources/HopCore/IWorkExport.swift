import Foundation

/// Batch export of Pages, Numbers and Keynote documents.
///
/// The iWork formats are undocumented zip containers of protobuf, and every
/// third-party reader of them is reverse engineering that breaks on the next
/// major release — formulas first (decided 2026-07-25). So Hop does not read
/// them at all: it asks the applications themselves, through Apple Events, to
/// run their own "Export to…". The quality is therefore exactly the quality of
/// doing it by hand, and there is nothing of ours to break.
///
/// The cost is honest and stated in the UI: it needs the apps installed and the
/// Automation permission — the only feature in Hop that does.
public enum IWorkExport {
    public enum App: String, CaseIterable, Sendable {
        case pages
        case numbers
        case keynote

        /// The application's own name, which is also its Apple Events target.
        public var appName: String {
            switch self {
            case .pages: return "Pages"
            case .numbers: return "Numbers"
            case .keynote: return "Keynote"
            }
        }

        public var bundleID: String {
            switch self {
            case .pages: return "com.apple.iWork.Pages"
            case .numbers: return "com.apple.iWork.Numbers"
            case .keynote: return "com.apple.iWork.Keynote"
            }
        }
    }

    public enum Target: String, CaseIterable, Sendable {
        case pdf
        case docx
        case xlsx
        case pptx

        public var fileExtension: String { rawValue }

        /// What the application's own export dictionary calls this format.
        var scriptConstant: String {
            switch self {
            case .pdf: return "PDF"
            case .docx: return "Microsoft Word"
            case .xlsx: return "Microsoft Excel"
            case .pptx: return "Microsoft PowerPoint"
            }
        }
    }

    /// The document extensions each application owns.
    public static func app(for url: URL) -> App? {
        switch url.pathExtension.lowercased() {
        case "pages": return .pages
        case "numbers": return .numbers
        case "key": return .keynote
        default: return nil
        }
    }

    public static var handledExtensions: Set<String> { ["pages", "numbers", "key"] }

    public static func isExportable(_ url: URL) -> Bool { app(for: url) != nil }

    /// What that application can be asked for. PDF is everywhere; the Office
    /// format is the one its own menu offers.
    public static func targets(for app: App) -> [Target] {
        switch app {
        case .pages: return [.pdf, .docx]
        case .numbers: return [.pdf, .xlsx]
        case .keynote: return [.pdf, .pptx]
        }
    }

    /// The Office format this application exports to — what "office" means for
    /// a mixed batch, where one setting has to serve three kinds of document.
    public static func officeTarget(for app: App) -> Target {
        switch app {
        case .pages: return .docx
        case .numbers: return .xlsx
        case .keynote: return .pptx
        }
    }

    /// The target to use for a document when the chosen one does not apply —
    /// asking Numbers for a .docx is not a failure, it is a PDF.
    public static func resolvedTarget(_ chosen: Target, for app: App) -> Target {
        targets(for: app).contains(chosen) ? chosen : .pdf
    }

    /// The AppleScript that performs one export. The document is opened, told
    /// to export, and closed WITHOUT saving — a batch must not modify what it
    /// was given.
    public static func script(input: URL, output: URL, target: Target) -> String? {
        guard let app = app(for: input) else { return nil }
        let format = resolvedTarget(target, for: app)
        let inPath = escaped(input.path)
        let outPath = escaped(output.path)
        return """
        tell application "\(app.appName)"
            set hopDoc to open POSIX file "\(inPath)"
            export hopDoc to POSIX file "\(outPath)" as \(format.scriptConstant)
            close hopDoc saving no
        end tell
        """
    }

    /// A path inside an AppleScript string literal. Backslashes first, or the
    /// escaping escapes its own escapes.
    static func escaped(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Whether the message an export failed with is the system refusing
    /// permission rather than the document being wrong. The two need different
    /// words on screen: one is a switch in System Settings, the other is not.
    public static func isPermissionRefusal(_ message: String) -> Bool {
        let text = message.lowercased()
        return text.contains("-1743")          // errAEEventNotPermitted
            || text.contains("not allowed to send apple events")
            || text.contains("not authorized to send apple events")
    }

    /// Whether the failure is "that application is not installed".
    public static func isMissingApp(_ message: String) -> Bool {
        let text = message.lowercased()
        return text.contains("-600")           // procNotFound
            || text.contains("-10814")         // no application knows how to open
            || text.contains("can’t be found")
            || text.contains("can't be found")
    }
}
