import SwiftUI

@main
struct DiskAnalyzerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Scan Directory...") {
                    NotificationCenter.default.post(name: .openDirectoryPicker, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let openDirectoryPicker = Notification.Name("openDirectoryPicker")
}
