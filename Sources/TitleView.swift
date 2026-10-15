import SwiftUI

/// Ficha de una película: fondo y título, botón principal y sinopsis. Pantalla completa, sin barra.
struct TitleView: View {
    let film: Film

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var playing: Film?
    @State private var expanded = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Kino.black.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero
                    VStack(alignment: .leading, spacing: 4) {
                        let meta = film.metaLine()
                        if !meta.isEmpty {
                            Text(meta)
                                .font(.system(size: 13))
                                .foregroundStyle(Kino.textSecondary)
                        }
                        Text("Dominio público · Internet Archive")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Kino.textSecondary)
                            .padding(.top, 4)

                        Button { playing = film } label: {
                            Label("Reproducir", systemImage: "play.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .padding(.top, 16)

                        synopsis
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
                .frame(maxWidth: sizeClass == .regular ? 720 : .infinity)
                .frame(maxWidth: .infinity)
            }
            .ignoresSafeArea(edges: .top)

            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.black.opacity(0.45), in: Circle())
            }
            .padding(8)
            .accessibilityLabel("Volver")
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .fullScreenCover(item: $playing) { PlayerView(film: $0) }
    }

    private var hero: some View {
        Color.clear
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay(PosterImage(url: film.posterUrl))
            .overlay(
                LinearGradient(colors: [.clear, Kino.black], startPoint: .top, endPoint: .bottom)
                    .allowsHitTesting(false)
            )
            .overlay(alignment: .bottomLeading) {
                Text(film.title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            .clipped()
    }

    /// Tres líneas y "Más" para expandir; nada si no hay sinopsis.
    @ViewBuilder
    private var synopsis: some View {
        if !film.synopsis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(film.synopsis)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineLimit(expanded ? nil : 3)
                if film.synopsis.count > 140 {
                    Button(expanded ? "Menos" : "Más") { expanded.toggle() }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
            .padding(.top, 16)
        }
    }
}
