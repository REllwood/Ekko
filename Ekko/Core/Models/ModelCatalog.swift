import Foundation

/// Curated subset of the WhisperKit CoreML catalog. Sizes were measured from the Hugging Face
/// repo on 2026-09-19. Ordered from smallest to largest.
enum ModelCatalog {
    static let all: [ModelDescriptor] = [
        ModelDescriptor(
            id: "openai_whisper-tiny",
            displayName: "Tiny",
            family: .whisper,
            languageSupport: .multilingual,
            sizeBytes: 77_000_000,
            accuracy: 1,
            speed: 5,
            minimumMemoryGB: 4,
            isCompressed: false,
            summary: "Instant results with basic accuracy. Good for older or low-memory Macs."
        ),
        ModelDescriptor(
            id: "openai_whisper-base.en",
            displayName: "Base (English)",
            family: .whisper,
            languageSupport: .englishOnly,
            sizeBytes: 147_000_000,
            accuracy: 2,
            speed: 5,
            minimumMemoryGB: 4,
            isCompressed: false,
            summary: "Very fast English dictation with acceptable accuracy for short notes."
        ),
        ModelDescriptor(
            id: "openai_whisper-base",
            displayName: "Base",
            family: .whisper,
            languageSupport: .multilingual,
            sizeBytes: 147_000_000,
            accuracy: 2,
            speed: 5,
            minimumMemoryGB: 4,
            isCompressed: false,
            summary: "Very fast, works in many languages, accuracy suits short notes."
        ),
        ModelDescriptor(
            id: "openai_whisper-small.en",
            displayName: "Small (English)",
            family: .whisper,
            languageSupport: .englishOnly,
            sizeBytes: 487_000_000,
            accuracy: 3,
            speed: 4,
            minimumMemoryGB: 8,
            isCompressed: false,
            summary: "A solid everyday English model on 8 GB Macs."
        ),
        ModelDescriptor(
            id: "openai_whisper-small",
            displayName: "Small",
            family: .whisper,
            languageSupport: .multilingual,
            sizeBytes: 486_000_000,
            accuracy: 3,
            speed: 4,
            minimumMemoryGB: 8,
            isCompressed: false,
            summary: "Balanced speed and accuracy across major languages."
        ),
        ModelDescriptor(
            id: "distil-whisper_distil-large-v3_turbo_600MB",
            displayName: "Distil Large v3 Turbo (English)",
            family: .distilWhisper,
            languageSupport: .englishOnly,
            sizeBytes: 607_000_000,
            accuracy: 4,
            speed: 4,
            minimumMemoryGB: 8,
            isCompressed: true,
            summary: "Near large-model English accuracy at a fraction of the size."
        ),
        ModelDescriptor(
            id: "openai_whisper-large-v3-v20240930_turbo_632MB",
            displayName: "Large v3 Turbo (Compact)",
            family: .whisper,
            languageSupport: .multilingual,
            sizeBytes: 646_000_000,
            accuracy: 4,
            speed: 4,
            minimumMemoryGB: 8,
            isCompressed: true,
            summary: "Excellent accuracy in 100 languages, compressed to stay quick on 8–16 GB Macs."
        ),
        ModelDescriptor(
            id: "openai_whisper-large-v3-v20240930_turbo",
            displayName: "Large v3 Turbo",
            family: .whisper,
            languageSupport: .multilingual,
            sizeBytes: 1_638_000_000,
            accuracy: 5,
            speed: 3,
            minimumMemoryGB: 16,
            isCompressed: false,
            summary: "Top-tier accuracy in 100 languages with a fast decoder. The best all-rounder on capable Macs."
        ),
        ModelDescriptor(
            id: "openai_whisper-large-v3-v20240930",
            displayName: "Large v3",
            family: .whisper,
            languageSupport: .multilingual,
            sizeBytes: 1_620_000_000,
            accuracy: 5,
            speed: 2,
            minimumMemoryGB: 16,
            isCompressed: false,
            summary: "The full Large v3 model. Highest accuracy, noticeably slower than Turbo."
        ),
    ]

    static func descriptor(for id: ModelID) -> ModelDescriptor? {
        all.first { $0.id == id }
    }

    /// Smallest multilingual model; used when nothing else is available.
    static let fallbackID: ModelID = "openai_whisper-base"
}
