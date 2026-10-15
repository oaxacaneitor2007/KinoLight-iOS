import SwiftUI
import UIKit

/// Los pósters van dentro de la app: `file:///android_asset/posters/x.jpg` en el JSON se
/// resuelve a `posters/x.jpg` del bundle.
enum LocalPoster {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(for urlString: String) -> UIImage? {
        guard urlString.hasPrefix("file://") || !urlString.contains("://") else { return nil }
        let name = (urlString as NSString).lastPathComponent
        if let cached = cache.object(forKey: name as NSString) { return cached }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        guard
            let url = Bundle.main.url(forResource: base, withExtension: ext, subdirectory: "posters"),
            let image = UIImage(contentsOfFile: url.path)
        else { return nil }
        cache.setObject(image, forKey: name as NSString)
        return image
    }
}

struct PosterImage: View {
    let url: String

    var body: some View {
        if let image = LocalPoster.image(for: url) {
            Image(uiImage: image).resizable().scaledToFill()
        } else if url.hasPrefix("http"), let remote = URL(string: url) {
            AsyncImage(url: remote) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Kino.surfaceHigh
                }
            }
        } else {
            Kino.surfaceHigh
        }
    }
}

/// Carátula 2:3 con el título debajo.
struct PosterCard: View {
    let film: Film
    var showMeta = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Kino.surfaceHigh
                .aspectRatio(2.0 / 3.0, contentMode: .fit)
                .overlay(PosterImage(url: film.posterUrl))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(film.title)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
            if showMeta {
                Text(film.metaLine())
                    .font(.system(size: 11))
                    .foregroundStyle(Kino.textSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
