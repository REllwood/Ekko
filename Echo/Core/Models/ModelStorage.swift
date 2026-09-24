import Foundation

/// On-disk layout of downloaded WhisperKit models.
///
/// `WhisperKit.download(variant:downloadBase:)` hands the files to the Hugging Face hub client,
/// which stores a repository at `<downloadBase>/<repoType>/<repoId>`; the variant folder sits
/// directly inside it. For our repository that is:
///
///     ~/Library/Application Support/Echo/Models/models/argmaxinc/whisperkit-coreml/<variant>/
///
/// A variant is only usable once the three CoreML bundles and `config.json` are all present.
enum ModelStorage {
    /// Hugging Face repository the catalog variants come from.
    static let repoID = "argmaxinc/whisperkit-coreml"

    /// Path the hub client appends to `downloadBase` for `repoID` ("models" is the repo type).
    static let repoSubpath = "models/argmaxinc/whisperkit-coreml"

    /// Entries that must exist inside a variant folder for it to count as installed.
    static let requiredEntries = [
        "AudioEncoder.mlmodelc",
        "TextDecoder.mlmodelc",
        "MelSpectrogram.mlmodelc",
        "config.json",
    ]

    /// `~/Library/Application Support/Echo/Models`.
    static var defaultDownloadBase: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return support.appendingPathComponent("Echo/Models", isDirectory: true)
    }

    /// Folder holding every downloaded variant.
    static func variantsRoot(downloadBase: URL) -> URL {
        downloadBase.appendingPathComponent(repoSubpath, isDirectory: true)
    }

    /// Folder a variant lives in, whether or not it has been downloaded.
    static func folder(downloadBase: URL, variant: ModelID) -> URL {
        variantsRoot(downloadBase: downloadBase).appendingPathComponent(variant, isDirectory: true)
    }

    /// True when `folder` contains a complete, loadable model. Pure — safe to unit test on a temp dir.
    static func isValidInstall(folder: URL, fileManager: FileManager = .default) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }
        return requiredEntries.allSatisfy { entry in
            fileManager.fileExists(atPath: folder.appendingPathComponent(entry).path)
        }
    }

    /// Bytes on disk under `folder`, or 0 when it cannot be measured.
    static func directorySize(of folder: URL, fileManager: FileManager = .default) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey])
            guard values?.isRegularFile == true else { continue }
            let size = values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0
            total += Int64(size)
        }
        return total
    }
}
