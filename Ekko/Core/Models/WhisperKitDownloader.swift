import Foundation
import WhisperKit

/// Progress reported while a model downloads.
///
/// WhisperKit's `Progress` counts *files*, not bytes, so byte figures are derived from
/// `fraction` and the catalog's download size by `ModelManager`.
struct ProgressSnapshot: Sendable, Equatable {
    let fraction: Double
    let completedFiles: Int64
    let totalFiles: Int64
}

/// Fetches model files for `ModelManager`. `WhisperKitModelDownloader` is the live one; tests
/// use a fake so they never touch the network.
protocol ModelDownloading: Sendable {
    /// Downloads `variant` into `downloadBase` and returns the folder it was written to.
    func download(
        variant: ModelID,
        downloadBase: URL,
        progress: @escaping @Sendable (ProgressSnapshot) -> Void
    ) async throws -> URL

    /// Fetches the tokenizer a freshly installed model needs to load offline.
    func prefetchTokenizer(for variant: ModelID, downloadBase: URL) async throws
}

/// The live downloader, backed by WhisperKit's Hugging Face client.
struct WhisperKitModelDownloader: ModelDownloading {
    func download(
        variant: ModelID,
        downloadBase: URL,
        progress: @escaping @Sendable (ProgressSnapshot) -> Void
    ) async throws -> URL {
        try await WhisperKitDownloader.download(variant: variant, downloadBase: downloadBase, progress: progress)
    }

    func prefetchTokenizer(for variant: ModelID, downloadBase: URL) async throws {
        try await WhisperKitDownloader.prefetchTokenizer(for: variant, downloadBase: downloadBase)
    }
}

/// Thin wrapper around WhisperKit’s Hugging Face download so that `ModelManager` never has to
/// `import WhisperKit` (ArgmaxCore exports a `ModelManager` type of its own).
enum WhisperKitDownloader {
    /// Downloads `variant` into `downloadBase` and returns the folder WhisperKit wrote it to
    /// (`<downloadBase>/models/argmaxinc/whisperkit-coreml/<variant>`).
    static func download(
        variant: ModelID,
        downloadBase: URL,
        progress: @escaping @Sendable (ProgressSnapshot) -> Void
    ) async throws -> URL {
        try? FileManager.default.createDirectory(at: downloadBase, withIntermediateDirectories: true)
        return try await WhisperKit.download(
            variant: variant,
            downloadBase: downloadBase,
            useBackgroundSession: false,
            from: ModelStorage.repoID,
            progressCallback: { progress(snapshot(from: $0)) }
        )
    }

    /// Whisper tokenizers live in a separate Hugging Face repo and are otherwise fetched the first
    /// time a model is loaded. Pulling one right after the download keeps the model usable offline.
    static func prefetchTokenizer(for variant: ModelID, downloadBase: URL) async throws {
        _ = try await ModelUtilities.loadTokenizer(
            for: whisperVariant(for: variant),
            tokenizerFolder: downloadBase
        )
    }

    private static func snapshot(from progress: Progress) -> ProgressSnapshot {
        ProgressSnapshot(
            fraction: progress.fractionCompleted,
            completedFiles: progress.completedUnitCount,
            totalFiles: progress.totalUnitCount
        )
    }

    /// Maps a catalog id onto the Whisper variant whose tokenizer it uses.
    private static func whisperVariant(for id: ModelID) -> ModelVariant {
        switch id {
        case "openai_whisper-tiny": return .tiny
        case "openai_whisper-tiny.en": return .tinyEn
        case "openai_whisper-base": return .base
        case "openai_whisper-base.en": return .baseEn
        case "openai_whisper-small": return .small
        case "openai_whisper-small.en": return .smallEn
        case "openai_whisper-medium": return .medium
        case "openai_whisper-medium.en": return .mediumEn
        default: return .largev3
        }
    }
}
