import Foundation

/// Una película del catálogo de la demo.
struct Film: Identifiable, Hashable {
    let id: String
    let title: String
    let year: Int
    let durationMin: Int
    let synopsis: String
    let posterUrl: String
    let videoUrl: String
    let sourceUrl: String
}

/// Una fila titulada del Inicio.
struct CatalogRow: Identifiable, Hashable {
    let id: String
    let title: String
    let films: [Film]
}

extension Film {
    /// "1940 · 1 h 32 min": el año y la duración, omitiendo lo que no se sabe.
    func metaLine() -> String {
        let duration: String
        if durationMin <= 0 { duration = "" }
        else if durationMin < 60 { duration = "\(durationMin) min" }
        else if durationMin % 60 == 0 { duration = "\(durationMin / 60) h" }
        else { duration = "\(durationMin / 60) h \(durationMin % 60) min" }
        return [year > 0 ? String(year) : "", duration]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

private func isBlank(_ s: String) -> Bool {
    s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

/// Interpreta `home.json`. Las filas sin título y los items sin título o sin video se omiten
/// en lugar de romper todo el catálogo.
func parseCatalog(_ data: Data) -> [CatalogRow] {
    guard
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let rows = root["rows"] as? [[String: Any]]
    else { return [] }

    return rows.compactMap { row in
        let rowTitle = (row["title"] as? String) ?? ""
        let items = (row["items"] as? [[String: Any]]) ?? []
        let films: [Film] = items.compactMap { o in
            let title = (o["title"] as? String) ?? ""
            let video = (o["video"] as? String) ?? ""
            if isBlank(title) || isBlank(video) { return nil }
            return Film(
                id: (o["id"] as? String) ?? title,
                title: title,
                year: (o["year"] as? Int) ?? 0,
                durationMin: (o["durationMin"] as? Int) ?? 0,
                synopsis: (o["synopsis"] as? String) ?? "",
                posterUrl: (o["poster"] as? String) ?? "",
                videoUrl: video,
                sourceUrl: (o["source"] as? String) ?? ""
            )
        }
        if isBlank(rowTitle) || films.isEmpty { return nil }
        return CatalogRow(id: (row["id"] as? String) ?? rowTitle, title: rowTitle, films: films)
    }
}

/// Lee y parsea `home.json` del bundle.
func loadCatalog() -> [CatalogRow] {
    guard
        let url = Bundle.main.url(forResource: "home", withExtension: "json"),
        let data = try? Data(contentsOf: url)
    else { return [] }
    return parseCatalog(data)
}

/// Cada película una sola vez, en el orden de las filas.
func allFilms(_ rows: [CatalogRow]) -> [Film] {
    var seen = Set<String>()
    return rows.flatMap { $0.films }.filter { seen.insert($0.id).inserted }
}

private func fold(_ text: String) -> String {
    text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
}

/// Películas cuyo título o sinopsis contiene todas las palabras de `query`, sin distinguir
/// mayúsculas ni acentos. Una búsqueda vacía devuelve todo.
func searchFilms(_ rows: [CatalogRow], query: String) -> [Film] {
    let words = fold(query).split(separator: " ").map(String.init)
    let films = allFilms(rows)
    if words.isEmpty { return films }
    return films.filter { film in
        let haystack = fold("\(film.title) \(film.synopsis) \(film.year)")
        return words.allSatisfy { haystack.contains($0) }
    }
}
