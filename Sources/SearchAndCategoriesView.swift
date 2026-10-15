import SwiftUI

private func posterColumns(_ count: Int) -> [GridItem] {
    Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: count)
}

/// "Buscar": en la demo filtra el catálogo del aparato mientras escribes.
struct SearchView: View {
    let rows: [CatalogRow]
    @State private var text = ""

    private var results: [Film] { searchFilms(rows, query: text) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Películas y series")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                if results.isEmpty {
                    Text("Sin resultados")
                        .font(.system(size: 11))
                        .foregroundStyle(Kino.textSecondary)
                }
                LazyVGrid(columns: posterColumns(3), alignment: .leading, spacing: 16) {
                    ForEach(results) { film in
                        NavigationLink(value: film) {
                            PosterCard(film: film, showMeta: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("En la app completa la búsqueda también pregunta a tus plugins.")
                    .font(.system(size: 12))
                    .foregroundStyle(Kino.textSecondary)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Kino.black)
        .navigationTitle("Buscar")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always), prompt: "Buscar…")
        .kinoBars()
        .toolbar(.hidden, for: .tabBar)
    }
}

/// "Categorías": un mosaico por fila del catálogo; al tocarlo se abre su lista de películas.
struct CategoriesView: View {
    let rows: [CatalogRow]

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var query = ""

    private var columns: Int { sizeClass == .regular ? 4 : 2 }

    private var shown: [CatalogRow] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return rows }
        return rows.filter { $0.title.range(of: q, options: .caseInsensitive) != nil }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Categorías")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Destacadas")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Kino.red)
                        .padding(.top, 4)
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: columns),
                        spacing: 10
                    ) {
                        ForEach(shown) { row in
                            NavigationLink(value: row) { CategoryCard(row: row) }
                                .buttonStyle(.plain)
                        }
                    }
                    if shown.isEmpty {
                        Text("Sin resultados para \"\(query)\"")
                            .foregroundStyle(Kino.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 32)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .background(Kino.black)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .principal) { KinoWordmark(height: 22) } }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Buscar categoría…")
            .kinoBars()
            .navigationDestination(for: CatalogRow.self) { CategoryFilmsView(row: $0) }
            .navigationDestination(for: Film.self) { TitleView(film: $0) }
        }
    }
}

private struct CategoryCard: View {
    let row: CatalogRow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Kino.surfaceHigh
                .frame(height: 110)
                .overlay(PosterImage(url: row.films.first?.posterUrl ?? ""))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(row.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 2)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Las películas de una categoría, en cuadrícula.
private struct CategoryFilmsView: View {
    let row: CatalogRow

    var body: some View {
        ScrollView {
            LazyVGrid(columns: posterColumns(3), alignment: .leading, spacing: 16) {
                ForEach(row.films) { film in
                    NavigationLink(value: film) {
                        PosterCard(film: film, showMeta: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Kino.black)
        .navigationTitle(row.title)
        .navigationBarTitleDisplayMode(.inline)
        .kinoBars()
    }
}

/// "Acerca de": qué es esta app y dónde está la completa.
struct AboutView: View {
    @Environment(\.openURL) private var openURL

    private var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Acerca de")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                    KinoWordmark(height: 40)
                        .padding(.vertical, 8)
                    Text("Kino Tv reproduce películas de dominio público. Kino completo (plugins, En vivo, cast, sincronización…) es una app aparte y se descarga en \(Kino.fullAppURL.absoluteString)")
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                    Text("Las películas son de dominio público en EE. UU. según el Internet Archive y se reproducen directo desde archive.org. Kino es un reproductor: no aloja ni distribuye contenido.")
                        .font(.system(size: 13))
                        .foregroundStyle(Kino.textSecondary)

                    Button { openURL(Kino.fullAppURL) } label: {
                        Text("Descargar Kino completo")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Kino.red, in: Capsule())
                    }
                    Button { openURL(Kino.telegramURL) } label: {
                        Text("Telegram: t.me/Kinoapptv")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .overlay(Capsule().stroke(Kino.textSecondary.opacity(0.6), lineWidth: 1))
                    }

                    Text("Kino Tv \(version) · Código bajo licencia Apache-2.0. El nombre y el logo de Kino no están licenciados.")
                        .font(.system(size: 12))
                        .foregroundStyle(Kino.textSecondary)
                        .padding(.top, 8)
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
            }
            .background(Kino.black)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .principal) { KinoWordmark(height: 22) } }
            .kinoBars()
        }
    }
}
