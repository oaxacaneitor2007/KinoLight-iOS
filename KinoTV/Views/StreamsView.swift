import SwiftUI

struct StreamsView: View {
    let item: MetaItem
    let name: String
    let poster: String
    let request: SourcesRequest
    let onClosed: (Bool) -> Void

    @EnvironmentObject var store: PluginStore
    @Environment(\.dismiss) private var dismiss

    enum Phase { case loading, empty, ready }
    @State private var phase: Phase = .loading
    @State private var streams: [StreamOption] = []
    @State private var subs: [SubTrack] = []
    @State private var player: PlayRequest?
    @State private var result = SourcesResult()
    @State private var showPlugins = false

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .loading:
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Buscando fuentes…").foregroundStyle(.secondary)
                    }
                case .empty:
                    VStack(spacing: 16) {
                        Text(emptyMessage)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        Button { showPlugins = true } label: {
                            Label("Administrar plugins", systemImage: "puzzlepiece.extension")
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Reintentar") { Task { await reload() } }
                    }
                    .padding()
                case .ready:
                    List(Array(streams.enumerated()), id: \.element.id) { i, s in
                        Button { player = makeRequest(i) } label: {
                            Text(s.label).font(.subheadline).lineLimit(2)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Fuentes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } }
            }
        }
        .task { await load() }
        .sheet(isPresented: $showPlugins, onDismiss: { Task { await reload() } }) {
            PluginsView().environmentObject(store)
        }
        .fullScreenCover(item: $player) { p in
            PlayerScreen(request: p) { finished in
                player = nil
                if finished { onClosed(true) }
            }
        }
    }

    private var emptyMessage: String {
        if result.asked == 0 {
            return "Ningún plugin activo ofrece fuentes para este contenido.\nAgrega un plugin de fuentes para poder reproducirlo."
        }
        if result.answered == 0 {
            return "Los plugins de fuentes no respondieron (\(result.asked) consultados).\nRevisa tu conexión o que el plugin siga funcionando."
        }
        if result.torrents > 0 {
            return "Los plugins devolvieron \(result.torrents) torrents, pero iOS solo reproduce enlaces directos.\nUsa un plugin con servicio debrid (entrega enlaces directos)."
        }
        return "Los plugins respondieron, pero sin enlaces reproducibles para este título."
    }

    private func reload() async {
        phase = .loading
        await load()
    }

    private func load() async {
        let r = await Stremio.sources(type: item.type, vid: request.vid, addons: store.addons)
        result = r
        streams = r.streams
        subs = r.subs
        if streams.isEmpty {
            phase = .empty
        } else if streams.count == 1 {
            phase = .ready
            player = makeRequest(0)
        } else {
            phase = .ready
        }
    }

    private func makeRequest(_ i: Int) -> PlayRequest {
        PlayRequest(key: item.type + "|" + item.id, type: item.type, metaId: item.id, abase: item.abase,
                    name: name, poster: poster, vid: request.vid, title: request.title,
                    season: request.season, episode: request.episode, resume: request.resume,
                    streams: streams, startIndex: i, subs: subs)
    }
}
