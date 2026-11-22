import Foundation

// MARK: - Alcance de un addon (types / idPrefixes), igual que decide Stremio a quién preguntar

struct Scope: Codable, Hashable {
    var types: [String]?
    var prefixes: [String]?

    static func twin(_ t: String) -> String? {
        if t == "series" { return "anime" }
        if t == "anime" { return "series" }
        return nil
    }

    func coversType(_ t: String) -> Bool {
        guard let types = types else { return true }
        let lt = t.lowercased()
        if types.contains(lt) { return true }
        if let tw = Scope.twin(lt), types.contains(tw) { return true }
        return false
    }

    func coversId(_ id: String) -> Bool {
        guard let prefixes = prefixes else { return true }
        return prefixes.contains { id.hasPrefix($0) }
    }
}

extension Array where Element == Scope {
    func covers(_ type: String, _ id: String) -> Bool {
        return contains { $0.coversType(type) && $0.coversId(id) }
    }

    /// Algunos addons de anime declaran "anime" y otros "series": se pregunta con el tipo que el addon declara.
    func asked(_ type: String, _ id: String) -> String {
        let lt = type.lowercased()
        guard let tw = Scope.twin(lt) else { return type }
        for s in self where s.coversId(id) {
            if s.types == nil || s.types!.contains(lt) { return type }
        }
        for s in self where s.coversId(id) {
            if let t = s.types, t.contains(tw) { return tw }
        }
        return type
    }
}

// MARK: - Addons

struct CatalogDef: Codable, Hashable {
    var id: String
    var type: String
    var name: String
    var search: Bool
    var browse: Bool
}

struct Addon: Codable, Hashable, Identifiable {
    var name: String
    var base: String
    var stream: [Scope]
    var meta: [Scope]
    var subtitles: [Scope]
    var catalogs: [CatalogDef]
    var id: String { base }
}

struct CachedAddons: Codable {
    var t: TimeInterval
    var addons: [Addon]
}

// MARK: - Contenido

func typeLabel(_ t: String) -> String {
    switch t {
    case "movie": return "Películas"
    case "series": return "Series"
    case "anime": return "Anime"
    case "tv": return "TV en vivo"
    case "channel": return "Canales"
    case "radio": return "Radio"
    default: return t.prefix(1).uppercased() + String(t.dropFirst())
    }
}

func typePriority(_ t: String) -> Int {
    switch t {
    case "movie": return 1
    case "series": return 2
    case "anime": return 3
    case "tv": return 4
    case "channel": return 5
    case "radio": return 6
    default: return 9
    }
}

func isSeriesType(_ t: String) -> Bool { t == "series" || t == "anime" }
func isLiveType(_ t: String) -> Bool { t == "tv" || t == "channel" || t == "radio" }

struct MetaItem: Identifiable, Hashable {
    let id: String
    let type: String
    var name: String
    var poster: String
    var desc: String
    var year: String
    let abase: String
}

struct Episode: Identifiable, Hashable {
    let id: String
    let season: Int
    let number: Int
    let title: String
    var label: String { title.isEmpty ? "Episodio \(number)" : title }
}

struct Season: Identifiable, Hashable {
    let number: Int
    var episodes: [Episode]
    var id: Int { number }
    var title: String { number == 0 ? "Especiales" : "Temporada \(number)" }
}

struct MetaDetail {
    var name = ""
    var desc = ""
    var poster = ""
    var line = ""
    var seasons: [Season] = []
}

struct SubTrack: Hashable, Identifiable {
    let url: String
    let lang: String
    let label: String
    var id: String { url }
}

struct StreamOption: Hashable, Identifiable {
    let url: String
    let label: String
    let score: Int
    let headers: [String: String]
    let subs: [SubTrack]
    var id: String { url }
}

struct SourcesRequest: Identifiable {
    let id = UUID()
    let vid: String
    let title: String
    let resume: Int
    let season: Int
    let episode: Int
}

struct PlayRequest: Identifiable {
    let id = UUID()
    let key: String
    let type: String
    let metaId: String
    let abase: String
    let name: String
    let poster: String
    let vid: String
    let title: String
    let season: Int
    let episode: Int
    let resume: Int
    let streams: [StreamOption]
    let startIndex: Int
    let subs: [SubTrack]
    var live: Bool { isLiveType(type) }
    var audio: Bool { type == "radio" }
}
