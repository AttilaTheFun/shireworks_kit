// A menu-bar app's scenes as README shows them, compiled on a Mac: the
// report window, its button and the command fit an app's body as written.
#if os(macOS)
import ShakeKit
import SwiftUI
import Testing

struct MenuBarAppScenes: Scene {
    var body: some Scene {
        MenuBarExtra("App", systemImage: "cloud") {
            ShakeKitReportButton()
        }
        Window("App", id: "main") {
            Text("Main").shakeToReport(repository: "owner/app")
        }
        ShakeKitReportWindow(repository: "owner/app")
            .commands { ShakeKitCommands() }
    }
}

@MainActor
struct MenuBarAppScenesTests {
    @Test func theReportWindowHasItsID() {
        #expect(ShakeKitReportWindow.id == "shakekit.report")
        _ = MenuBarAppScenes()
    }
}
#endif
