import SwiftUI

/// La línea al pie del Inicio que dice qué es esta app.
let footerNote =
    "Películas de dominio público del Internet Archive. " +
    "La app completa, Kino, se descarga en archive.org/details/kino-app."

/// Inicio: un destacado grande y una fila de pósters por cada fila del catálogo.
struct HomeView: View {
    let rows: [CatalogRow]

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var path = NavigationPath()
    @State private var showSearch = false
    @State private var playing: Film?

    private var isWide: Bool { sizeClass == .regular }
    private var heroHeight: CGFloat { isWide ? 420 : 220 }
    private var posterWidth: CGFloat { isWide ? 180 : 120 }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let hero = rows.first?.films.first {
                        Hero(
                            film: hero,
                            height: heroHeight,
                            onPlay: { playing = hero },
                            onOpen: { path.append(hero) }
                        )
                    }
                    ForEach(rows) { row in
                        FilmRow(row: row, posterWidth: posterWidth)
                    }
                    Text(footerNote)
                        .font(.system(size: 12))
                        .foregroundStyle(Kino.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 28)
                        .padding(.bottom, 24)
                }
            }
            .background(Kino.black)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { KinoWordmark(height: 22) }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showSearch = true } label: {
                        Image(systemName: "magnifyingglass").foregroundStyle(.white)
                    }
                    .accessibilityLabel("Buscar")
                }
            }
            .kinoBars()
            .navigationDestination(for: Film.self) { TitleView(film: $0) }
            .navigationDestination(isPresented: $showSearch) { SearchView(rows: rows) }
        }
        .fullScreenCover(item: $playing) { PlayerView(film: $0) }
    }
}

/// Destacado a ancho completo: fondo, degradado inferior, título y botón de reproducir.
private struct Hero: View {
    let film: Film
    let height: CGFloat
    let onPlay: () -> Void
    let onOpen: () -> Void

    var body: some View {
        Color.clear
            .frame(height: height)
            .overlay(PosterImage(url: film.posterUrl))
            .overlay(
                LinearGradient(colors: [.clear, Kino.black], startPoint: .top, endPoint: .bottom)
                    .allowsHitTesting(false)
            )
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(film.title)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(film.metaLine())
                        .font(.system(size: 13))
                        .foregroundStyle(Kino.textSecondary)
                        .lineLimit(2)
                    Button(action: onPlay) {
                        Label("Reproducir", systemImage: "play.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(Kino.red, in: Capsule())
                    }
                    .padding(.top, 8)
                }
                .padding(16)
            }
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
    }
}

/// Una fila del Inicio: su título y una línea horizontal de pósters.
private struct FilmRow: View {
    let row: CatalogRow
    let posterWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(row.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.leading, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(row.films) { film in
                        NavigationLink(value: film) {
                            PosterCard(film: film)
                        }
                        .buttonStyle(.plain)
                        .frame(width: posterWidth)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.top, 16)
    }
}
