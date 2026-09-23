/// Where Hop lives on the web, for the links the app hands out.
/// SPEC: docs/spec.md — "Sharing Hop".
/// Tests: Tests/HopCoreTests/ProductLinkTests.swift
public enum ProductLink {
    public static let repository = "https://github.com/antonyshakirov/hop"

    /// The site publishes every language the app speaks; English sits on the
    /// bare domain, the rest under their code.
    static let siteLanguages: Set<String> = [
        "ru", "de", "es", "pt", "fr", "it", "zh", "ja", "nl", "ko", "th",
        "vi", "hi", "id", "tr", "pl", "sr", "ar", "he", "fa", "ur"]

    /// The product page in the language `code` names.
    public static func page(for code: String) -> String {
        siteLanguages.contains(code) ? "https://hop.tools/\(code)/" : "https://hop.tools/"
    }
}
