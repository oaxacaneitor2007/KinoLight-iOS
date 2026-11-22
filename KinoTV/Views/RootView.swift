import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: PluginStore

    var body: some View {
        switch store.state {
        case .loading:
            VStack(spacing: 16) {
                ProgressView()
                Text("Conectando con las fuentes…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            VStack(spacing: 16) {
                Text("No se pudo conectar con las fuentes.")
                Button("Reintentar") { Task { await store.load(force: true) } }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready:
            HomeView()
        }
    }
}
