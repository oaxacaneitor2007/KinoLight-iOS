import Foundation

/// Cache en memoria de catalogos para no repetir peticiones al volver a mostrar una fila.
actor CatalogCache {
    static let shared = CatalogCache()
    private var store: [String: [MetaItem]] = [:]
    func get(_ k: String) -> [MetaItem]? { store[k] }
    func set(_ k: String, _ v: [MetaItem]) { store[k] = v }
    func clear() { store.removeAll() }
}

/// Protocolo de addons de Stremio: /catalog, /meta, /stream, /subtitles.
enum Stremio {

    // MARK: Catalogos y busqueda

    static func parseMetas(_ data: Data, type: String, base: String) -> [MetaItem] {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let metas = o["metas"] as? [Any] else { return [] }
        var out: [MetaItem] = []
        var seen = Set<String>()
        for m in metas {
            guard let mt = m as? [String: Any] else { continue }
            let id = jStr(mt["id"])
            if id.isEmpty || seen.contains(id) { continue }
            seen.insert(id)
            let t = jStr(mt["type"]).isEmpty ? type : jStr(mt["type"])
            out.append(MetaItem(id: id, type: t, name: jStr(mt["name"]), poster: jStr(mt["poster"]),
                                desc: String(jStr(mt["description"]).prefix(400)),
                                year: jStr(mt["releaseInfo"]), abase: base))
            if out.count >= 40 { break }
        }
        return out
    }

    static func catalog(_ addon: Addon, _ cat: CatalogDef) async -> [MetaItem] {
        let url = "\(addon.base)/catalog/\(Http.enc(cat.type))/\(Http.enc(cat.id)).json"
        if let c = await CatalogCache.shared.get(url) { return c }
        guard let d = await Http.data(url, timeout: 12) else { return [] }
        let items = parseMetas(d, type: cat.type, base: addon.base)
        if !items.isEmpty { await CatalogCache.shared.set(url, items) }
        return items
    }

    static func search(_ q: String, addons: [Addon]) async -> [MetaItem] {
        var reqs: [(key: String, url: String)] = []
        var seen = Set<String>()
        for (i, a) in addons.enumerated() {
            for c in a.catalogs where c.search {
                let k = "\(i)|\(c.type)"
                if seen.contains(k) || reqs.count >= 10 { continue }
                seen.insert(k)
                reqs.append((key: k, url: "\(a.base)/catalog/\(Http.enc(c.type))/\(Http.enc(c.id))/search=\(Http.enc(q)).json"))
            }
        }
        let res = await Http.many(reqs, timeout: 9)
        var buckets: [Int: [MetaItem]] = [:]
        var seenIds = Set<String>()
        for r in reqs {
            guard let d = res[r.key] else { continue }
            let parts = r.key.split(separator: "|")
            guard parts.count == 2, let ai = Int(parts[0]), ai < addons.count else { continue }
            for it in parseMetas(d, type: String(parts[1]), base: addons[ai].base) {
                if seenIds.insert(it.type + "|" + it.id).inserted {
                    buckets[typePriority(it.type), default: []].append(it)
                }
            }
        }
        var out: [MetaItem] = []
        for k in buckets.keys.sorted() { out.append(contentsOf: buckets[k] ?? []) }
        return Array(out.prefix(60))
    }

    // MARK: Meta (descripcion, episodios)

    static func meta(for item: MetaItem, addons: [Addon]) async -> MetaDetail? {
        var order: [Addon] = []
        for a in addons where a.base == item.abase && a.meta.covers(item.type, item.id) { order.append(a) }
        for a in addons where order.count < 2 && a.meta.covers(item.type, item.id) && !order.contains(where: { $0.base == a.base }) {
            order.append(a)
        }
        for a in order {
            let t = a.meta.asked(item.type, item.id)
            let url = "\(a.base)/meta/\(Http.enc(t))/\(Http.enc(item.id)).json"
            if let o = await Http.object(url, timeout: 8), let m = o["meta"] as? [String: Any] {
                return parseMeta(m)
            }
        }
        return nil
    }

    static func parseMeta(_ m: [String: Any]) -> MetaDetail {
        var d = MetaDetail()
        d.name = jStr(m["name"])
        d.desc = jStr(m["description"])
        d.poster = jStr(m["poster"])

        var parts: [String] = []
        var y = jStr(m["releaseInfo"])
        if y.isEmpty { y = jStr(m["year"]) }
        if !y.isEmpty { parts.append(y) }
        let rt = jStr(m["runtime"])
        if !rt.isEmpty { parts.append(rt) }
        let rating = jStr(m["imdbRating"])
        if !rating.isEmpty { parts.append("★ " + rating) }
        let g = (m["genres"] as? [Any]) ?? (m["genre"] as? [Any])
        if let g = g {
            let gs = g.prefix(3).map { jStr($0) }.filter { !$0.isEmpty }.joined(separator: ", ")
            if !gs.isEmpty { parts.append(gs) }
        }
        d.line = parts.joined(separator: "  ·  ")

        var map: [Int: [Episode]] = [:]
        for v in (m["videos"] as? [Any]) ?? [] {
            guard let vo = v as? [String: Any] else { continue }
            let vid = jStr(vo["id"])
            if vid.isEmpty { continue }
            let s = jInt(vo["season"])
            var e = jInt(vo["episode"])
            if e == 0 { e = jInt(vo["number"]) }
            var t = jStr(vo["title"])
            if t.isEmpty { t = jStr(vo["name"]) }
            map[s, default: []].append(Episode(id: vid, season: s, number: e, title: t))
        }
        // temporadas en orden numerico; la 0 (especiales) al final; episodios por numero (orden estable)
        let keys = map.keys.sorted { a, b in
            let ka = a == 0 ? Int.max : a
            let kb = b == 0 ? Int.max : b
            return ka < kb
        }
        for k in keys {
            let eps = (map[k] ?? []).enumerated().sorted { x, y in
                x.element.number != y.element.number ? x.element.number < y.element.number : x.offset < y.offset
            }.map { $0.element }
            d.seasons.append(Season(number: k, episodes: eps))
        }
        return d
    }

    // MARK: Fuentes y subtitulos (todo en paralelo)

    static func sources(type: String, vid: String, addons: [Addon]) async -> (streams: [StreamOption], subs: [SubTrack]) {
        let live = isLiveType(type)
        var reqs: [(key: String, url: String)] = []
        for (i, a) in addons.enumerated() {
            if a.stream.covers(type, vid) {
                reqs.append((key: "s:\(i)", url: "\(a.base)/stream/\(Http.enc(a.stream.asked(type, vid)))/\(Http.enc(vid)).json"))
            }
            if !live && a.subtitles.covers(type, vid) {
                reqs.append((key: "t:\(i)", url: "\(a.base)/subtitles/\(Http.enc(a.subtitles.asked(type, vid)))/\(Http.enc(vid)).json"))
            }
        }
        let res = await Http.many(reqs, timeout: 10)

        var streams: [StreamOption] = []
        var subs: [SubTrack] = []
        var seenUrl = Set<String>()
        var seenSub = Set<String>()
        var nSpa = 0, nEng = 0

        for r in reqs {
            guard let d = res[r.key],
                  let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { continue }
            let parts = r.key.split(separator: ":")
            guard parts.count == 2, let ai = Int(parts[1]), ai < addons.count else { continue }
            if parts[0] == "s" {
                for st in (o["streams"] as? [Any]) ?? [] {
                    if let s = makeStream(st, addon: addons[ai].name, seen: &seenUrl) { streams.append(s) }
                }
            } else {
                for sb in (o["subtitles"] as? [Any]) ?? [] {
                    guard let tr = makeSub(sb), !seenSub.contains(tr.url) else { continue }
                    seenSub.insert(tr.url)
                    if tr.lang == "spa" && nSpa < 3 {
                        nSpa += 1
                        subs.append(nSpa > 1 ? SubTrack(url: tr.url, lang: tr.lang, label: "\(tr.label) \(nSpa)") : tr)
                    } else if tr.lang == "eng" && nEng < 2 {
                        nEng += 1
                        subs.append(nEng > 1 ? SubTrack(url: tr.url, lang: tr.lang, label: "\(tr.label) \(nEng)") : tr)
                    }
                }
            }
        }

        // mejor primero (orden estable); maximo 40
        let sorted = streams.enumerated().sorted { x, y in
            x.element.score != y.element.score ? x.element.score > y.element.score : x.offset < y.offset
        }.map { $0.element }
        return (Array(sorted.prefix(40)), subs)
    }

    private static func makeStream(_ any: Any, addon: String, seen: inout Set<String>) -> StreamOption? {
        guard let st = any as? [String: Any] else { return nil }
        let url = jStr(st["url"])
        guard url.lowercased().hasPrefix("http"), !seen.contains(url) else { return nil } // sin torrents ni externalUrl
        seen.insert(url)

        let name = jStr(st["name"]).replacingOccurrences(of: "\n", with: " ")
        var desc = jStr(st["title"])
        if desc.isEmpty { desc = jStr(st["description"]) }
        let fmt = guessFormat(url)

        var headers: [String: String] = [:]
        if let bh = st["behaviorHints"] as? [String: Any],
           let ph = bh["proxyHeaders"] as? [String: Any],
           let rq = ph["request"] as? [String: Any] {
            for (k, v) in rq { headers[k] = jStr(v) }
        }
        var own: [SubTrack] = []
        for sb in (st["subtitles"] as? [Any]) ?? [] {
            if let tr = makeSub(sb) { own.append(tr) }
        }

        var label = String(name.prefix(26))
        let first = desc.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""
        if !first.isEmpty { label += "  —  " + String(first.prefix(80)) }
        label += "   [\(addon)]"
        return StreamOption(url: url, label: label, score: score(name + " " + desc, fmt: fmt), headers: headers, subs: own)
    }

    private static func makeSub(_ any: Any) -> SubTrack? {
        guard let sb = any as? [String: Any] else { return nil }
        let url = jStr(sb["url"])
        guard url.lowercased().hasPrefix("http") else { return nil }
        let l = jStr(sb["lang"]).lowercased()
        if l.hasPrefix("es") || l.hasPrefix("sp") { return SubTrack(url: url, lang: "spa", label: "Español") }
        if l.hasPrefix("en") { return SubTrack(url: url, lang: "eng", label: "English") }
        return nil
    }

    static func guessFormat(_ url: String) -> String {
        var p = url.lowercased()
        if let q = p.firstIndex(of: "?") { p = String(p[..<q]) }
        if p.contains(".m3u8") { return "hls" }
        for ext in ["mp4", "m4v", "mov", "mkv", "avi", "webm", "mp3", "aac", "m4a"] where p.hasSuffix("." + ext) { return ext }
        if url.lowercased().contains("m3u8") { return "hls" }
        return ""
    }

    /// AVPlayer reproduce HLS, MP4/MOV y audio; MKV/AVI/WebM suelen fallar, por eso van al final.
    static func score(_ text: String, fmt: String) -> Int {
        let t = text.lowercased()
        var s = 50
        if t.contains("1080") { s = 100 }
        else if t.contains("2160") || t.contains("4k") || t.contains("uhd") { s = 70 }
        else if t.contains("720") { s = 80 }
        else if t.contains("480") { s = 45 }
        else if t.contains("360") { s = 30 }
        switch fmt {
        case "mp4", "m4v", "mov", "hls": s += 6
        case "mkv": s -= 40
        case "avi", "webm": s -= 60
        default: break
        }
        if t.range(of: #"\b(cam|hdcam|camrip|telesync|hdts)\b"#, options: .regularExpression) != nil { s -= 70 }
        return s
    }
}
