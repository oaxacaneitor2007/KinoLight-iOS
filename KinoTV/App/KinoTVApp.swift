import SwiftUI
import AVFoundation

@main
struct KinoTVApp: App {
    @StateObject private var store = PluginStore()

    init() {
        // Cache de imagenes y respuestas mas grande para desplazarse con fluidez.
        URLCache.shared = URLCache(memoryCapacity: 64 << 20, diskCapacity: 256 << 20)
        try? AVAudioSession.sharedInstance().setCategory(.playback)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .task { await store.load() }
                .onOpenURL { url in store.handleIncoming(url) }
        }
    }
}
