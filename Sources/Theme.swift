import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// Paleta de Kino (misma que Theme.kt). Kino siempre es oscuro.
enum Kino {
    static let red = Color(hex: 0xE50914)
    static let logoRed = Color(hex: 0xE53224) // el rojo del punto del logo
    static let black = Color(hex: 0x0E0E0E)
    static let surface = Color(hex: 0x181818)
    static let surfaceHigh = Color(hex: 0x242424)
    static let textPrimary = Color(hex: 0xF5F5F5)
    static let textSecondary = Color(hex: 0xB3B3B3)

    static let fullAppURL = URL(string: "https://archive.org/details/kino-app")!
    static let telegramURL = URL(string: "https://t.me/Kinoapptv")!
}

extension View {
    /// Barra superior e inferior negras, como en la versión Android.
    func kinoBars() -> some View {
        self
            .toolbarBackground(Kino.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Kino.black, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

/// "m:ss" o "h:mm:ss".
func formatDuration(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds > 0 else { return "0:00" }
    let total = Int(seconds)
    let h = total / 3600, m = (total % 3600) / 60, s = total % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}
