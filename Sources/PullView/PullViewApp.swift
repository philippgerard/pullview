import SwiftUI

@main
struct PullViewApp: App {
    @State private var store = PRStore()

    var body: some Scene {
        MenuBarExtra {
            ContentView(store: store)
        } label: {
            let symbol = store.error != nil ? "exclamationmark.triangle"
                : store.hasFailingOwnPR ? "xmark.circle" : "arrow.triangle.pull"
            // No count before the first successful fetch, so "0" never stands in for "unknown".
            if store.sections == nil {
                Image(systemName: symbol)
            } else {
                Label("\(store.openCount)", systemImage: symbol).labelStyle(.titleAndIcon)
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: store)
        }
    }
}
