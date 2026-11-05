import AppKit

@main
enum AirSkipApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = AirSkipAppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
