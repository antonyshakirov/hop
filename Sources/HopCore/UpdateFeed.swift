import Foundation

/// Builds the update-check URL. The manifest itself never changes shape; the
/// query carries the one thing the site cannot infer from the request — which
/// version is asking.
///
/// This is the only signal a copy of Hop emits at all. Release downloads are
/// counted by GitHub alone, so a build handed over directly (AirDrop, a zip in
/// a chat, a USB stick) is invisible everywhere else, while its hourly update
/// check still arrives. Version is deliberately the whole payload: no
/// identifier, no fingerprint, nothing that outlives the request beyond a line
/// in an access log.
public enum UpdateFeed {
    /// - Parameters:
    ///   - feed: the manifest URL (UpdateChecker.feedURL in the app).
    ///   - version: the running CFBundleShortVersionString.
    public static func checkURL(feed: String, version: String) -> URL? {
        // URLComponents happily parses a blank or relative string into something
        // that still yields a URL ("?v=1.4.0"), which fails much later and much
        // less legibly — demand an absolute address up front
        guard var components = URLComponents(string: feed),
              components.scheme != nil, components.host != nil
        else { return nil }
        // a blank version would land in the log as an empty parameter and read
        // as a parsing bug on the other side — send nothing instead
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return components.url }
        components.queryItems = [URLQueryItem(name: "v", value: trimmed)]
        return components.url
    }

    /// Whether the release being offered is later than the one running. Compared
    /// as numbers per component, never as text: 1.10.0 stands above 1.9.1 while
    /// the strings sort the other way round, and every Mac's update to 1.10.0
    /// rides on that (Anton, 2026-09-03). Anything that is not a version answers
    /// false — a build is not replaced on a reading nobody can make sense of.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let offered = ReleaseNews.Version(candidate),
              let running = ReleaseNews.Version(current) else { return false }
        return running < offered
    }
}
