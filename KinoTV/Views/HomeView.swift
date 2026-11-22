import SwiftUI

struct HomeRow: Identifiable {
    let id: String
    let title: String
    let addon: Addon
    let cat: CatalogDef
}

struct HomeView: View {
    @EnvironmentObject var store: PluginStore
    @State private var cw: [ContinueEntry] = []
    @State private var showSearch = false
    @State private var showPlugins = false

    /// Catalogos agrupados por tipo (peliculas, series, anime, tv, radio...), maximo 30 filas.
    private var rows: [HomeRow] {
        var buckets = [[HomeRow]](repeating: [], count: 10)
        for a in store.addons {
            for c in a.catalogs where c.browse {
                let r = HomeRow(id: "\(a.base)|\(c.type)|\(c.id)",
                                title: "\(typeLabel(c.type)) · \(c.name) — \(a.name)",
                                addon: a, cat: c)
                buckets[typePriority(c.type)].append(r)
            }
        }
        return Array(buckets.flatMap { $0 }.prefix(30))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                // LazyVStack: cada fila pide su catalogo solo cuando se acerca a la pantalla.
                LazyVStack(alignment: .leading, spacing: 24) {
                    if !store.hasStreamPlugin { NoSourcesBanner { showPlugins = true } }
                    if !cw.isEmpty { ContinueRow(entries: cw) }
                    ForEach(rows) { row in RowView(row: row) }
                }
                .padding(.vertical)
            }
            .navigationTitle("Kino TV")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showPlugins = true } label: { Image(systemName: "puzzlepiece.extension") }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button { showSearch = true } label: { Image(systemName: "magnifyingglass") }
                    Button { Task { await CatalogCache.shared.clear(); await store.load(force: true) } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .navigationDestination(for: MetaItem.self) { item in DetailView(item: item) }
            .navigationDestination(isPresented: $showSearch) { SearchView() }
            .onAppear {
                cw = ContinueStore.all()
                if store.incoming != nil { showPlugins = true }
            }
            .onChange(of: store.incoming) { v in if v != nil { showPlugins = true } }
            .sheet(isPresented: $showPlugins) { PluginsView().environmentObject(store) }
        }
    }
}

/// Aviso cuando no hay ningun plugin capaz de dar fuentes de reproduccion.
struct NoSourcesBanner: View {
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Sin plugins de fuentes", systemImage: "exclamationmark.triangle.fill")
                .font(.headline).foregroundStyle(.orange)
            Text("Puedes explorar el catálogo, pero para reproducir necesitas agregar al menos un plugin que entregue enlaces directos.")
                .font(.subheadline).foregroundStyle(.secondary)
            Button("Agregar plugin", action: action).buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}

struct ContinueRow: View {
    let entries: [ContinueEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Continuar viendo").font(.headline).padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(entries) { e in
                        NavigationLink(value: e.asItem) { PosterCard(item: e.asItem) }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct RowView: View {
    let row: HomeRow
    @State private var items: [MetaItem]?

    var body: some View {
        Group {
            if let items = items, items.isEmpty {
                EmptyView() // fila sin contenido: se oculta
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(row.title).font(.headline).padding(.horizontal)
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 12) {
                            if let items = items {
                                ForEach(items) { item in
                                    NavigationLink(value: item) { PosterCard(item: item) }.buttonStyle(.plain)
                                }
                            } else {
                                ForEach(0..<6, id: \.self) { _ in
                                    RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.15)).frame(width: 120, height: 180)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
        }
        .task {
            if items == nil { items = await Stremio.catalog(row.addon, row.cat) }
        }
    }
}
