import SwiftUI

@main
struct KinoApp: App {
    private let rows = loadCatalog()

    var body: some Scene {
        WindowGroup {
            RootView(rows: rows)
        }
    }
}
