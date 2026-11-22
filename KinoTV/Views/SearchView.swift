import SwiftUI

struct SearchView: View {
    @EnvironmentObject var store: PluginStore
    @State private var query = ""
    @State private var results: [MetaItem] = []
    @State private var busy = false
    @State private var done = false

    private let cols = [GridItem(.adaptive(minimum: 120), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: cols, spacing: 16) {
                ForEach(results) { item in
                    NavigationLink(value: item) { PosterCard(item: item) }.buttonStyle(.plain)
                }
            }
            .padding()
            if busy { ProgressView().padding() }
            if done && results.isEmpty { Text("Sin resultados.").foregroundStyle(.secondary).padding() }
        }
        .navigationTitle("Buscar")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Películas, series, anime…")
        // task(id:) cancela la busqueda anterior sola cuando cambia el texto; la espera evita una peticion por tecla.
        .task(id: query) {
            let q = query.trimmingCharacters(in: .whitespaces)
            guard q.count >= 2 else { results = []; done = false; busy = false; return }
            try? await Task.sleep(nanoseconds: 700_000_000)
            if Task.isCancelled { return }
            busy = true
            done = false
            let r = await Stremio.search(q, addons: store.addons)
            if Task.isCancelled { return }
            results = r
            busy = false
            done = true
        }
    }
}
