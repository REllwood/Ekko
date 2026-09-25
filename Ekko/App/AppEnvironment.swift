import Foundation

/// Facts about the process Ekko is running in.
enum AppEnvironment {
    /// True when Ekko.app was launched only to host the unit tests. XCTest sets these variables in
    /// every process it injects a test bundle into. The app must then stay inert: no container,
    /// menu-bar item, HUD, event tap, permission prompt or onboarding, and nothing read from or
    /// written to the user's defaults and files.
    static let isHostingUnitTests: Bool = {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
    }()
}
