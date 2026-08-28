import Foundation

/// When converting an image would only make it worse.
///
/// A JPEG re-encoded at quality 100 is not the file it started as: the original
/// was written at some ordinary quality with subsampled colour, and asking the
/// encoder for its best writes full colour and barely-quantised detail — a
/// grainy photo can come back several times heavier for a picture nobody can
/// tell apart (Anton, 2026-08-28). When nothing is actually being asked for —
/// same format, full scale, quality at the top — the honest answer is the file
/// itself, copied.
public enum ImagePassthrough {
    /// The extensions each output format may already be in. JPEG has two
    /// spellings, and HEIC files are sometimes named .heif.
    static func extensions(of format: String) -> Set<String> {
        switch format.lowercased() {
        case "jpeg", "jpg": return ["jpg", "jpeg"]
        case "png": return ["png"]
        case "heic": return ["heic", "heif"]
        case "avif": return ["avif"]
        default: return [format.lowercased()]
        }
    }

    /// True when the conversion would produce a copy of the input at best: the
    /// file is already in the target format, nothing is being scaled, and the
    /// quality dial is at the top.
    ///
    /// `quality` is the 0…1 the encoder takes. Below the top the user IS asking
    /// for something — a smaller file — so the encode goes ahead.
    public static func isNoOp(source: URL, format: String,
                              scale: Double, quality: Double) -> Bool {
        guard scale >= 1, quality >= 1 else { return false }
        return extensions(of: format).contains(source.pathExtension.lowercased())
    }
}
