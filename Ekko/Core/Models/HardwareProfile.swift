import Darwin
import Foundation

/// A snapshot of the Mac we are running on, used to recommend models.
struct HardwareProfile: Sendable, Equatable {
    enum Architecture: String, Sendable {
        case appleSilicon
        case intel
    }

    /// Apple Silicon tiers. `.unknown` for Intel or unparsed names.
    enum ChipClass: String, Sendable {
        case base
        case pro
        case max
        case ultra
        case unknown
    }

    /// e.g. "MacBookPro18,2"
    let modelIdentifier: String
    /// e.g. "Apple M1 Max" or "Intel(R) Core(TM) i7-9750H"
    let chipName: String
    let architecture: Architecture
    let chipClass: ChipClass
    /// 1 for M1, 2 for M2, ... nil for Intel/unknown.
    let chipGeneration: Int?
    let memoryGB: Int
    let coreCount: Int
    let hasNeuralEngine: Bool

    /// Coarse capability bucket driving recommendations and badges.
    var performanceTier: PerformanceTier {
        switch architecture {
        case .intel:
            return .limited
        case .appleSilicon:
            if chipClass == .max || chipClass == .ultra || memoryGB >= 32 { return .exceptional }
            if chipClass == .pro || memoryGB >= 16 { return .strong }
            return .capable
        }
    }

    /// Short human description, e.g. "Apple M1 Max · 32 GB".
    var summary: String {
        "\(chipName) · \(memoryGB) GB"
    }

    /// Detects the current machine via sysctl.
    static func detect() -> HardwareProfile {
        let modelIdentifier = sysctlString("hw.model") ?? "Unknown"
        let brandString = sysctlString("machdep.cpu.brand_string")
        let memoryBytes = sysctlUInt64("hw.memsize") ?? ProcessInfo.processInfo.physicalMemory
        let memoryGB = max(1, Int((Double(memoryBytes) / 1_073_741_824).rounded()))
        let coreCount = sysctlUInt64("hw.ncpu").map(Int.init) ?? ProcessInfo.processInfo.processorCount

        #if arch(arm64)
        let fallbackChipName = "Apple Silicon"
        #else
        let fallbackChipName = "Intel"
        #endif

        let chipName = brandString?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? fallbackChipName
        let chip = parse(chipName: chipName) ?? parse(chipName: fallbackChipName) ?? ChipInfo(
            architecture: .intel,
            chipClass: .unknown,
            generation: nil,
            hasNeuralEngine: false
        )

        return HardwareProfile(
            modelIdentifier: modelIdentifier,
            chipName: chipName,
            architecture: chip.architecture,
            chipClass: chip.chipClass,
            chipGeneration: chip.generation,
            memoryGB: memoryGB,
            coreCount: coreCount,
            hasNeuralEngine: chip.hasNeuralEngine
        )
    }

    /// What `parse(chipName:)` could work out from a CPU brand string.
    struct ChipInfo: Equatable, Sendable {
        let architecture: Architecture
        let chipClass: ChipClass
        let generation: Int?
        let hasNeuralEngine: Bool
    }

    /// Pure parser for `machdep.cpu.brand_string` values such as "Apple M1 Max" or
    /// "Intel(R) Core(TM) i7-9750H CPU @ 2.60GHz". Returns nil when the string is not recognised.
    static func parse(chipName: String) -> ChipInfo? {
        let lowered = chipName.lowercased()
        guard !lowered.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        if lowered.contains("intel") {
            return ChipInfo(architecture: .intel, chipClass: .unknown, generation: nil, hasNeuralEngine: false)
        }
        guard lowered.contains("apple") else { return nil }

        let tokens = lowered.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        var generation: Int?
        var chipClass: ChipClass = .unknown

        for (index, token) in tokens.enumerated() {
            guard token.first == "m" else { continue }
            let digits = token.dropFirst()
            guard !digits.isEmpty, digits.allSatisfy({ $0.isNumber }), let value = Int(digits) else { continue }
            generation = value
            chipClass = .base
            if index + 1 < tokens.count {
                switch tokens[index + 1] {
                case "pro": chipClass = .pro
                case "max": chipClass = .max
                case "ultra": chipClass = .ultra
                default: break
                }
            }
            break
        }

        return ChipInfo(
            architecture: .appleSilicon,
            chipClass: chipClass,
            generation: generation,
            hasNeuralEngine: true
        )
    }

    // MARK: - sysctl

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    private static func sysctlUInt64(_ name: String) -> UInt64? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0 else { return nil }
        switch size {
        case MemoryLayout<UInt64>.size:
            var value: UInt64 = 0
            guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
            return value
        case MemoryLayout<UInt32>.size:
            var value: UInt32 = 0
            guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
            return UInt64(value)
        default:
            return nil
        }
    }
}

enum PerformanceTier: Int, Comparable, Sendable {
    case limited = 0
    case capable = 1
    case strong = 2
    case exceptional = 3

    static func < (lhs: PerformanceTier, rhs: PerformanceTier) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .limited: return "Limited"
        case .capable: return "Capable"
        case .strong: return "Strong"
        case .exceptional: return "Exceptional"
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
