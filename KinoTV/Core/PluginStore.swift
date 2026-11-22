import Foundation

/// Conexion automatica a la fuente de plugins (mismo orden que el APK original):
/// GitHub -> archive.org -> jsDelivr -> catalogo incluido en la app.
/// No hay comprobacion ni aviso de actualizaciones de la app.
@MainActor
final class PluginStore: ObservableObject {
    enum State { case loading, ready, failed }

    @Published private(set) var addons: [Addon] = []
    @Published private(set) var state: State = .loading

    private static let sources = [
        "https://raw.githubusercontent.com/kinotvapp/kino-plugins/main/catalog.json",
        "https://archive.org/download/kino-app/plugin-catalog.json",
        "https://cdn.jsdelivr.net/gh/kinotvapp/kino-plugins@main/catalog.json"
    ]
    private static let ttl: TimeInterval = 21600 // 6 h, igual que el original

    private var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("kino_addons_v1.json")
    }

    func load(force: Bool = false) async {
        state = .loading
        let now = Date().timeIntervalSince1970
        let cache = readCache()
        if !force, let c = cache, now - c.t < Self.ttl {
            addons = c.addons
            state = .ready
            return
        }

        let entries = await loadEntries()
        var reqs: [(key: String, url: String)] = []
        var seen = Set<String>()
        for e in entries {
            guard var u = e["stremio"] as? String else { continue }
            if u.lowercased().hasPrefix("stremio://") { u = "https://" + String(u.dropFirst(10)) }
            guard u.lowercased().hasPrefix("http"), !seen.contains(u) else { continue }
            seen.insert(u)
            reqs.append((key: u, url: u))
        }

        let results = await Http.many(reqs, timeout: 15)
        var built: [Addon] = []
        var failed = 0
        for r in reqs {
            if let d = results[r.key],
               let mf = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
               let a = Self.buildAddon(mf, url: r.url) {
                built.append(a)
            } else {
                failed += 1
            }
        }

        if built.isEmpty {
            if let c = cache { built = c.addons }
        } else {
            // Si algun addon no respondio (hosting lento), el cache dura 15 min en vez de 6 h.
            let stamp = failed > 0 ? now - (Self.ttl - 900) : now
            writeCache(CachedAddons(t: stamp, addons: built))
        }
        addons = built
        state = built.isEmpty ? .failed : .ready
    }

    private func loadEntries() async -> [[String: Any]] {
        for src in Self.sources {
            if let o = await Http.object(src, timeout: 8), let list = Self.entries(o), !list.isEmpty {
                return list
            }
        }
        if let url = Bundle.main.url(forResource: "plugin-catalog-seed", withExtension: "json"),
           let d = try? Data(contentsOf: url),
           let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
           let list = Self.entries(o) {
            return list
        }
        return []
    }

    private static func entries(_ o: [String: Any]) -> [[String: Any]]? {
        guard jInt(o["schema"]) == 1, let p = o["plugins"] as? [Any] else { return nil }
        return p.compactMap { $0 as? [String: Any] }
    }

    /// Solo los addons de Stremio (HTTP + JSON) se portan: los plugins "repo" de Kino son JavaScript
    /// para el motor QuickJS de Android y se omiten.
    static func buildAddon(_ mf: [String: Any], url: String) -> Addon? {
        if let h = mf["behaviorHints"] as? [String: Any] {
            if h["adult"] as? Bool == true { return nil }
            if h["configurationRequired"] as? Bool == true { return nil }
        }
        var base = url
        if base.lowercased().hasSuffix("/manifest.json") { base = String(base.dropLast(14)) }

        let topTypes = (mf["types"] as? [Any])?.compactMap { ($0 as? String)?.lowercased() }
        let topPrefixes = (mf["idPrefixes"] as? [Any])?.compactMap { $0 as? String }
        var stream: [Scope] = [], meta: [Scope] = [], subs: [Scope] = []

        for r in (mf["resources"] as? [Any]) ?? [] {
            var name = ""
            var types = topTypes
            var prefixes = topPrefixes
            if let s = r as? String {
                name = s
            } else if let o = r as? [String: Any] {
                name = (o["name"] as? String) ?? ""
                if let t = o["types"] as? [Any] { types = t.compactMap { ($0 as? String)?.lowercased() } }
                if let p = o["idPrefixes"] as? [Any] { prefixes = p.compactMap { $0 as? String } }
            }
            let sc = Scope(types: types, prefixes: prefixes)
            switch name {
            case "stream": stream.append(sc)
            case "meta": meta.append(sc)
            case "subtitles": subs.append(sc)
            default: break
            }
        }

        var cats: [CatalogDef] = []
        for c in (mf["catalogs"] as? [Any]) ?? [] {
            guard let o = c as? [String: Any],
                  let cid = o["id"] as? String,
                  let ctype = (o["type"] as? String)?.lowercased(),
                  !cid.isEmpty, !ctype.isEmpty else { continue }
            var searchable = false, blocked = false, searchRequired = false
            if let extra = o["extra"] as? [Any] {
                for x in extra {
                    guard let xo = x as? [String: Any], let xn = xo["name"] as? String else { continue }
                    if xn == "search" { searchable = true }
                    if xo["isRequired"] as? Bool == true {
                        if xn == "search" { searchRequired = true } else { blocked = true }
                    }
                }
            } else {
                if let sup = o["extraSupported"] as? [Any], sup.contains(where: { ($0 as? String) == "search" }) { searchable = true }
                for x in (o["extraRequired"] as? [Any]) ?? [] {
                    if (x as? String) == "search" { searchRequired = true } else { blocked = true }
                }
            }
            if blocked { continue }
            cats.append(CatalogDef(id: cid, type: ctype, name: (o["name"] as? String) ?? cid,
                                   search: searchable, browse: !searchRequired))
        }

        if cats.isEmpty && stream.isEmpty && meta.isEmpty && subs.isEmpty { return nil }
        let name = (mf["name"] as? String) ?? base
        return Addon(name: name, base: base, stream: stream, meta: meta, subtitles: subs, catalogs: cats)
    }

    private func readCache() -> CachedAddons? {
        guard let d = try? Data(contentsOf: cacheURL),
              let c = try? JSONDecoder().decode(CachedAddons.self, from: d),
              !c.addons.isEmpty else { return nil }
        return c
    }

    private func writeCache(_ c: CachedAddons) {
        if let d = try? JSONEncoder().encode(c) { try? d.write(to: cacheURL, options: .atomic) }
    }
}
