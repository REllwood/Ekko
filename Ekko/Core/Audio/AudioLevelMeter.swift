import Foundation

/// Turns per-buffer RMS into the 0...1 value the HUD draws: dB mapping, a mild power curve, then
/// asymmetric smoothing (fast attack, slower release) so the bars feel responsive but not jittery.
struct AudioLevelMeter {
    /// Quietest level that still shows movement.
    static let floorDecibels: Float = -50
    /// Time constants in seconds.
    static let attack: Float = 0.05
    static let release: Float = 0.25

    private(set) var level: Float = 0

    /// Maps an RMS amplitude to 0...1. Pure, so it can be unit tested.
    static func normalized(rms: Float) -> Float {
        guard rms > 0 else { return 0 }
        let decibels = 20 * log10(max(rms, 1e-7))
        let linear = (decibels - floorDecibels) / -floorDecibels
        let clamped = min(max(linear, 0), 1)
        // Exponent < 1 lifts quiet speech without letting loud speech peg the meter.
        return pow(clamped, 0.65)
    }

    /// Feeds one buffer and returns the smoothed level.
    @discardableResult
    mutating func process(rms: Float, deltaTime: TimeInterval) -> Float {
        let target = Self.normalized(rms: rms)
        let tau = target > level ? Self.attack : Self.release
        let dt = Float(min(max(deltaTime, 0), 1))
        let coefficient = tau > 0 ? 1 - exp(-dt / tau) : 1
        level += (target - level) * min(max(coefficient, 0), 1)
        if level < 0.0005 { level = 0 }
        return level
    }

    mutating func reset() {
        level = 0
    }
}
