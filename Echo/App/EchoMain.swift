import AppKit

@main
@MainActor
enum EchoMain {
    /// NSApplication.delegate is unowned; keep the delegate alive here.
    private static var delegate: AppDelegate?

    static func main() {
        let app = NSApplication.shared
        let appDelegate = AppDelegate()
        delegate = appDelegate
        app.delegate = appDelegate
        app.setActivationPolicy(.accessory)
        _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }
}
