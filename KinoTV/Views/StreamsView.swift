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
                    Text("No se encontraron fuentes reproducibles.\nSolo se reproducen enlaces directos (no torrents).")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
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
        .fullScreenCover(item: $player) { p in
            PlayerScreen(request: p) { finished in
                player = nil
                if finished { onClosed(true) }
            }
        }
    }

    private func load() async {
        let r = await Stremio.sources(type: item.type, vid: request.vid, addons: store.addons)
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
