import Foundation

/// Static description of a downloadable speech model. Fixed contract — do not change fields.
struct ModelDescriptor: Identifiable, Hashable, Sendable {
    enum Family: String, Sendable {
        case whisper
        case distilWhisper
    }

    enum LanguageSupport: String, Sendable {
        case englishOnly
        case multilingual
    }

    /// Hugging Face folder name in `argmaxinc/whisperkit-coreml` (also the WhisperKit "variant").
    let id: ModelID
    /// Human name, e.g. "Large v3 Turbo".
    let displayName: String
    let family: Family
    let languageSupport: LanguageSupport
    /// Approximate download size.
    let sizeBytes: Int64
    /// 1 (basic) ... 5 (best) — relative accuracy.
    let accuracy: Int
    /// 1 (slow) ... 5 (fastest) — relative speed on Apple Silicon.
    let speed: Int
    /// Minimum unified memory we are comfortable recommending it on.
    let minimumMemoryGB: Int
    /// Weight-compressed variant (smaller, slightly less accurate).
    let isCompressed: Bool
    /// One-line marketing-free summary for the model card.
    let summary: String

    var isEnglishOnly: Bool { languageSupport == .englishOnly }

    var sizeLabel: String {
        let mb = Double(sizeBytes) / 1_000_000
        if mb >= 1000 { return String(format: "%.1f GB", mb / 1000) }
        return String(format: "%.0f MB", mb)
    }
}
