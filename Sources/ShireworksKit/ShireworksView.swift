// The one view modifier an app adopts the kit by, on Apple's systems (the
// shake and its report need them, as ShireworksShake's views do).
#if canImport(SwiftUI) && (canImport(UIKit) || canImport(AppKit))
import ShireworksCrashes
import ShireworksShake
import SwiftUI

extension View {
    /// Everything of Shireworks Kit an app's views have, in one modifier on
    /// its root view (each window's, for an app with several):
    ///
    /// - at its first appearance, `ShireworksKit.start()`, once a process:
    ///   crashes caught and filed, the build recorded in the app group, and,
    ///   on a Mac, Shireworks' offers of the app's updates looked at (on the
    ///   group's signal, every five minutes, and as the app comes to the
    ///   front) and answered with the update sheet, unless the app
    ///   registered its own answer (`AppUpdates.register(autoUpdate:)`);
    /// - shake to report (`.shakeToReport`), filed in `repository`.
    ///
    /// `repository` ("owner/name") is the Info.plist's
    /// `ShireworksRepository` unless given; crashes are filed there too.
    /// With neither, there's no shake to report, and crashes are kept
    /// unfiled. On a Mac, Help › Report a Bug… is the scene's
    /// `.commands { ShakeKitCommands() }`, and a menu-bar app adds
    /// `ShakeKitReportWindow` (docs/shake).
    public func shireworks(repository: String? = nil) -> some View {
        var crashes = CrashesConfiguration.main
        if let repository { crashes.repository = repository }
        return modifier(ShireworksModifier(crashes: crashes))
    }
}

struct ShireworksModifier: ViewModifier {
    let crashes: CrashesConfiguration

    @ViewBuilder
    private func shake(_ content: Content) -> some View {
        if let repository = crashes.repository {
            content.shakeToReport(repository: repository)
        } else {
            content
        }
    }

    func body(content: Content) -> some View {
        shake(content)
            .onAppear { ShireworksKit.start(crashes: crashes) }
    }
}
#endif
