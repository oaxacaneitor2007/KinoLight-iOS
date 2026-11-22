import SwiftUI

struct DetailView: View {
    let item: MetaItem
    @EnvironmentObject var store: PluginStore

    @State private var meta: MetaDetail?
    @State private var loading = true
    @State private var seasonIdx = 0
    @State private var cw: ContinueEntry?
    @State private var request: SourcesRequest?
    @State private var highlight: String?

    private var name: String { (meta?.name.isEmpty == false) ? meta!.name : item.name }
    private var poster: String { (meta?.poster.isEmpty == false) ? meta!.poster : item.poster }
    private var desc: String { (meta?.desc.isEmpty == false) ? meta!.desc : item.desc }
    private var line: String { (meta?.line.isEmpty == false) ? meta!.line : item.year }
    private var seasons: [Season] { meta?.seasons ?? [] }
    private var hasEpisodes: Bool { isSeriesType(item.type) && !seasons.isEmpty }
    private var cwKey: String { item.type + "|" + item.id }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    PosterCard(item: MetaItem(id: item.id, type: item.type, name: "", poster: poster, desc: "", year: "", abase: item.abase), width: 120)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(name).font(.title2.bold())
                        if !line.isEmpty { Text(line).font(.subheadline).foregroundStyle(.secondary) }
                    }
                }
                if !desc.isEmpty { Text(desc).font(.body) }

                if loading && isSeriesType(item.type) {
                    ProgressView("Cargando episodios…")
                } else if hasEpisodes {
                    if let cw = cw {
                        Button { play(vid: cw.v, title: cw.n, resume: cw.pos, s: cw.s, e: cw.e) } label: {
                            Label("Continuar \(epTag(cw.s, cw.e))", systemImage: "play.fill").frame(maxWidth: .infinity)
                        }.buttonStyle(.borderedProminent)
                    }
                    episodesSection
                } else if !loading || !isSeriesType(item.type) {
                    playButtons
                }
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            cw = ContinueStore.find(cwKey)
            meta = await Stremio.meta(for: item, addons: store.addons)
            loading = false
            if let c = cw, let m = meta, let i = m.seasons.firstIndex(where: { $0.episodes.contains { $0.id == c.v } }) {
                seasonIdx = i
            }
        }
        .sheet(item: $request, onDismiss: { cw = ContinueStore.find(cwKey) }) { r in
            StreamsView(item: item, name: name, poster: poster, request: r) { finished in
                request = nil
                if finished { advance(after: r.vid) }
            }
            .environmentObject(store)
        }
    }

    // MARK: Botones de pelicula / canal / radio

    @ViewBuilder private var playButtons: some View {
        let resumable = (cw?.pos ?? 0) > 10 && !isLiveType(item.type)
        if resumable, let c = cw {
            Button { play(vid: c.v, title: c.n, resume: c.pos, s: c.s, e: c.e) } label: {
                Label("Continuar desde \(fmtTime(c.pos))", systemImage: "play.fill").frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent)
            Button { play(vid: item.id, title: name, resume: 0, s: 0, e: 0) } label: {
                Label("Desde el inicio", systemImage: "gobackward").frame(maxWidth: .infinity)
            }.buttonStyle(.bordered)
        } else {
            Button { play(vid: item.id, title: name, resume: 0, s: 0, e: 0) } label: {
                Label("Reproducir", systemImage: "play.fill").frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent)
        }
    }

    // MARK: Temporadas y episodios

    @ViewBuilder private var episodesSection: some View {
        let list = seasons
        let idx = min(seasonIdx, list.count - 1)
        if list.count > 1 {
            Picker("Temporada", selection: $seasonIdx) {
                ForEach(Array(list.enumerated()), id: \.offset) { i, s in Text(s.title).tag(i) }
            }
            .pickerStyle(.menu)
        }
        LazyVStack(spacing: 0) {
            ForEach(list[idx].episodes) { ep in
                Button {
                    var resume = 0
                    if let c = cw, c.v == ep.id, c.pos > 10 { resume = c.pos }
                    play(vid: ep.id, title: "\(name)  ·  \(epTag(ep.season, ep.number))", resume: resume, s: ep.season, e: ep.number)
                } label: {
                    HStack {
                        Text("\(ep.number).  \(ep.label)").lineLimit(1)
                        Spacer()
                        if cw?.v == ep.id { Image(systemName: "clock").foregroundStyle(.secondary) }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 8)
                    .background(highlight == ep.id ? Color.accentColor.opacity(0.25) : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
    }

    private func epTag(_ s: Int, _ e: Int) -> String {
        if s > 0 && e > 0 { return "T\(s) E\(e)" }
        if e > 0 { return "E\(e)" }
        return ""
    }

    private func play(vid: String, title: String, resume: Int, s: Int, e: Int) {
        request = SourcesRequest(vid: vid, title: title, resume: resume, season: s, episode: e)
    }

    /// Al terminar un episodio, deja resaltado el siguiente.
    private func advance(after vid: String) {
        for (si, s) in seasons.enumerated() {
            guard let ei = s.episodes.firstIndex(where: { $0.id == vid }) else { continue }
            if ei + 1 < s.episodes.count {
                seasonIdx = si
                highlight = s.episodes[ei + 1].id
            } else if si + 1 < seasons.count {
                seasonIdx = si + 1
                highlight = seasons[si + 1].episodes.first?.id
            }
            return
        }
    }
}
