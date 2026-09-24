import Foundation

/// How well a model fits the current Mac. Drives the badge on each model card.
enum ModelSuitability: Int, Comparable, Sendable {
    case notRecommended = 0
    case slow = 1
    case good = 2
    case great = 3
    case recommended = 4

    static func < (lhs: ModelSuitability, rhs: ModelSuitability) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .notRecommended: return "Not recommended"
        case .slow: return "Slow on this Mac"
        case .good: return "Good fit"
        case .great: return "Great fit"
        case .recommended: return "Recommended for your Mac"
        }
    }
}

struct ModelRecommendation: Sendable, Equatable {
    let recommended: ModelDescriptor
    /// Other sensible choices, best first.
    let alternatives: [ModelDescriptor]
    /// e.g. "Your Mac can run our best model."
    let headline: String
    /// One or two sentences explaining why.
    let rationale: String
    let tier: PerformanceTier
}

/// Pure functions mapping hardware -> model advice. Must be deterministic and
/// unit-tested for each tier x (english / multilingual).
enum ModelRecommender {
    // Catalog ids used by the recommendation table. Force-unwrapped lookups by literal id are safe:
    // `ModelCatalog.all` is a compile-time constant and `catalogIdsAreValid` covers it in tests.
    private enum Pick {
        static let tiny = ModelCatalog.descriptor(for: "openai_whisper-tiny")!
        static let baseEn = ModelCatalog.descriptor(for: "openai_whisper-base.en")!
        static let base = ModelCatalog.descriptor(for: "openai_whisper-base")!
        static let smallEn = ModelCatalog.descriptor(for: "openai_whisper-small.en")!
        static let small = ModelCatalog.descriptor(for: "openai_whisper-small")!
        static let distilTurbo = ModelCatalog.descriptor(for: "distil-whisper_distil-large-v3_turbo_600MB")!
        static let turboCompact = ModelCatalog.descriptor(for: "openai_whisper-large-v3-v20240930_turbo_632MB")!
        static let turbo = ModelCatalog.descriptor(for: "openai_whisper-large-v3-v20240930_turbo")!
        static let large = ModelCatalog.descriptor(for: "openai_whisper-large-v3-v20240930")!
    }

    /// `preferEnglishOnly` is true when the user's dictation language is English.
    static func recommendation(for hardware: HardwareProfile, preferEnglishOnly: Bool) -> ModelRecommendation {
        let tier = hardware.performanceTier
        let table = picks(for: tier, preferEnglishOnly: preferEnglishOnly)

        // Never recommend something that cannot fit in memory; fall back to the best model that does.
        let recommended = fits(table.recommended, on: hardware)
            ? table.recommended
            : (table.alternatives.first { fits($0, on: hardware) } ?? Pick.base)

        let alternatives = table.alternatives
            .filter { $0.id != recommended.id && fits($0, on: hardware) }

        return ModelRecommendation(
            recommended: recommended,
            alternatives: alternatives,
            headline: headline(for: tier),
            rationale: rationale(for: tier, hardware: hardware, model: recommended),
            tier: tier
        )
    }

    /// Badge for a model card. Uses the multilingual recommendation, which is the catalog default.
    static func suitability(of model: ModelDescriptor, on hardware: HardwareProfile) -> ModelSuitability {
        suitability(of: model, on: hardware, preferEnglishOnly: false)
    }

    /// Badge for a model card when the user's dictation language is known.
    static func suitability(
        of model: ModelDescriptor,
        on hardware: HardwareProfile,
        preferEnglishOnly: Bool
    ) -> ModelSuitability {
        if !fits(model, on: hardware) { return .notRecommended }
        if hardware.architecture == .intel && model.accuracy >= 4 { return .notRecommended }

        let advice = recommendation(for: hardware, preferEnglishOnly: preferEnglishOnly)
        if model.id == advice.recommended.id { return .recommended }
        if advice.alternatives.contains(where: { $0.id == model.id }) { return .great }
        if estimatedRealtimeFactor(of: model, on: hardware) < 3 { return .slow }
        return .good
    }

    /// A better model for this Mac and this language, when the active one falls short: either less
    /// accurate than the recommendation, or English-only while another language is selected.
    /// nil when nothing is active (the "choose a model" prompt covers that), when the active model
    /// is already right, or when the user dismissed this particular suggestion.
    static func upgradeSuggestion(
        active: ModelDescriptor?,
        hardware: HardwareProfile,
        languageCode: String?,
        dismissedID: ModelID?
    ) -> ModelDescriptor? {
        guard let active else { return nil }
        let recommended = recommendation(for: hardware, preferEnglishOnly: languageCode == "en").recommended
        guard recommended.id != active.id, recommended.id != dismissedID else { return nil }
        let wrongLanguage = active.isEnglishOnly && languageCode != nil && languageCode != "en"
        guard wrongLanguage || recommended.accuracy > active.accuracy else { return nil }
        return recommended
    }

    /// Rough expected speed as a multiple of real time (e.g. 12 => a 10 s clip takes ~0.8 s).
    static func estimatedRealtimeFactor(of model: ModelDescriptor, on hardware: HardwareProfile) -> Double {
        baseRealtimeFactor(of: model) * tierScale(hardware.performanceTier)
    }

    // MARK: - Tables

    private struct Picks {
        let recommended: ModelDescriptor
        let alternatives: [ModelDescriptor]
    }

    private static func picks(for tier: PerformanceTier, preferEnglishOnly: Bool) -> Picks {
        switch (tier, preferEnglishOnly) {
        case (.limited, true):
            return Picks(recommended: Pick.baseEn, alternatives: [Pick.smallEn, Pick.tiny])
        case (.limited, false):
            return Picks(recommended: Pick.base, alternatives: [Pick.small, Pick.tiny])
        case (.capable, true):
            return Picks(recommended: Pick.distilTurbo, alternatives: [Pick.smallEn, Pick.baseEn])
        case (.capable, false):
            return Picks(recommended: Pick.turboCompact, alternatives: [Pick.small, Pick.base])
        case (.strong, true):
            return Picks(recommended: Pick.distilTurbo, alternatives: [Pick.turboCompact, Pick.turbo, Pick.smallEn])
        case (.strong, false):
            return Picks(recommended: Pick.turboCompact, alternatives: [Pick.turbo, Pick.small])
        case (.exceptional, true):
            return Picks(recommended: Pick.turbo, alternatives: [Pick.distilTurbo, Pick.large, Pick.turboCompact])
        case (.exceptional, false):
            return Picks(recommended: Pick.turbo, alternatives: [Pick.large, Pick.turboCompact])
        }
    }

    private static func baseRealtimeFactor(of model: ModelDescriptor) -> Double {
        switch model.id {
        case Pick.tiny.id: return 60
        case Pick.baseEn.id, Pick.base.id: return 45
        case Pick.smallEn.id, Pick.small.id: return 25
        case Pick.distilTurbo.id, Pick.turboCompact.id: return 20
        case Pick.turbo.id: return 15
        case Pick.large.id: return 6
        default:
            // Unknown catalog entries: interpolate from the accuracy rating (1 = fastest).
            return [60, 45, 25, 20, 15][max(0, min(4, model.accuracy - 1))]
        }
    }

    private static func tierScale(_ tier: PerformanceTier) -> Double {
        switch tier {
        case .exceptional: return 1.0
        case .strong: return 0.6
        case .capable: return 0.35
        case .limited: return 0.08
        }
    }

    private static func fits(_ model: ModelDescriptor, on hardware: HardwareProfile) -> Bool {
        model.minimumMemoryGB <= hardware.memoryGB
    }

    // MARK: - Copy

    private static func headline(for tier: PerformanceTier) -> String {
        switch tier {
        case .exceptional: return "Your Mac can run our best model."
        case .strong: return "Your Mac runs the big models comfortably."
        case .capable: return "Your Mac runs a great everyday model."
        case .limited: return "We picked a model that stays quick on this Mac."
        }
    }

    private static func rationale(
        for tier: PerformanceTier,
        hardware: HardwareProfile,
        model: ModelDescriptor
    ) -> String {
        let mac = "The \(hardware.chipName) with \(hardware.memoryGB) GB"
        switch tier {
        case .exceptional:
            return "\(mac) has plenty of memory and a fast Neural Engine, so \(model.displayName) stays quick."
        case .strong:
            return "\(mac) has enough memory and a fast Neural Engine for \(model.displayName), which is accurate and still returns text in about a second."
        case .capable:
            return "\(mac) is best served by a compact model, so \(model.displayName) gives you near-top accuracy without slowing your Mac down."
        case .limited:
            return "\(mac) has no Neural Engine, so \(model.displayName) is the sweet spot between accuracy and waiting for your words."
        }
    }
}
