import Foundation

struct ContinueEntry: Codable, Identifiable, Hashable {
    var k: String      // tipo|id del meta
    var t: String      // tipo
    var i: String      // id del meta
    var a: String      // base del addon
    var n: String      // titulo
    var p: String      // poster
    var v: String      // id del video (episodio)
    var s: Int
    var e: Int
    var pos: Int
    var dur: Int
    var id: String { k }

    var asItem: MetaItem {
        MetaItem(id: i, type: t, name: n, poster: p, desc: "", year: "", abase: a)
    }
}

/// "Continuar viendo": UserDefaults, maximo 12 titulos, un punto de reanudacion por titulo.
enum ContinueStore {
    private static let key = "kino.cw"

    static func all() -> [ContinueEntry] {
        guard let d = UserDefaults.standard.data(forKey: key),
              let l = try? JSONDecoder().decode([ContinueEntry].self, from: d) else { return [] }
        return l
    }

    private static func write(_ l: [ContinueEntry]) {
        if let d = try? JSONEncoder().encode(l) { UserDefaults.standard.set(d, forKey: key) }
    }

    static func save(_ e: ContinueEntry) {
        var out = [e]
        for x in all() where x.k != e.k && out.count < 12 { out.append(x) }
        write(out)
    }

    static func remove(_ k: String) { write(all().filter { $0.k != k }) }

    static func find(_ k: String) -> ContinueEntry? { all().first { $0.k == k } }
}

func fmtTime(_ sec: Int) -> String {
    let s = max(sec, 0)
    let h = s / 3600, m = (s % 3600) / 60, x = s % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, x) : String(format: "%d:%02d", m, x)
}
