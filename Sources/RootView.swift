import SwiftUI

/// Animación de inicio: el logo aparece y luego se hace un zoom + fundido que descubre la app.
/// (Versión simplificada de KinoSplash.kt: sin la transición anillo → "o" del logo.)
struct KinoSplash: View {
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var exiting = false

    private let introSeconds = 0.96
    private let exitSeconds = 0.26

    var body: some View {
        ZStack {
            Kino.black.ignoresSafeArea()
            KinoWordmark(height: 64)
                .scaleEffect(appeared ? 1.0 : 0.82)
                .opacity(appeared ? 1 : 0)
        }
        .scaleEffect(exiting ? 1.12 : 1.0)
        .opacity(exiting ? 0 : 1)
        .onAppear {
            if reduceMotion {
                appeared = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { onFinished() }
                return
            }
            withAnimation(.easeOut(duration: introSeconds)) { appeared = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + introSeconds) {
                withAnimation(.easeIn(duration: exitSeconds)) { exiting = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + exitSeconds) { onFinished() }
            }
        }
    }
}

/// El caparazón de la app: tres secciones (Inicio, Categorías, Acerca de) y la animación encima.
struct RootView: View {
    let rows: [CatalogRow]
    @State private var splashVisible = true

    var body: some View {
        ZStack {
            Kino.black.ignoresSafeArea()
            TabView {
                HomeView(rows: rows)
                    .tabItem { Label("Inicio", systemImage: "house.fill") }
                CategoriesView(rows: rows)
                    .tabItem { Label("Categorías", systemImage: "square.grid.2x2.fill") }
                AboutView()
                    .tabItem { Label("Acerca de", systemImage: "info.circle.fill") }
            }
            .tint(Kino.red)

            if splashVisible {
                KinoSplash { splashVisible = false }
                    .zIndex(1)
            }
        }
        .preferredColorScheme(.dark)
    }
}
