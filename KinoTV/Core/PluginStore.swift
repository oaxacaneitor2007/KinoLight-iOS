import Foundation

/// Plugin agregado por el usuario (addon de Stremio, por la URL de su manifest).
/// Se guarda con el manifest ya interpretado, asi funciona sin conexion y arranca rapido.
struct UserPlugin: Codable, Identifiable, Hashable {
    var id: String          // URL normalizada del manifest
    var url: String
    var name: String
    var enabled: Bool
    var addon: Addon?
    var error: String?      // ultimo error al actualizar (nil = todo bien)
    var note: String?       // aviso informativo (p. ej. "no ofrece fuentes")
}

enum AddOutcome {
    case added(name: String, warning: String?)
    case exists(name: String)
    case failed(String)
}

struct Probe {
    var addon: Addon? = nil
    var error: String? = nil
    var warning: String? = nil
}

/// Conexion automatica a la fuente de plugins incluidos (GitHub -> archive.org -> jsDelivr -> catalogo
/// incluido en la app) + plugins que agrega el usuario.
@MainActor
final class PluginStore: ObservableObject {
    enum State { case loading, ready, failed }

    /// Addons del catalogo incluido (se pueden activar/desactivar).
    @Published private(set) var builtin: [Addon] = []
    /// Addons agregados por el usuario.
    @Published private(set) var userPlugins: [UserPlugin] = []
    @Published private(set) var disabledBuiltin: Set<String> = []
    @Published private(set) var state: State = .loading
    @Published private(set) var refreshing = false
    /// Direccion recibida por enlace (stremio:// o kinotv://) pendiente de agregar.
    @Published var incoming: String?

    /// Addons activos: los del usuario primero (mismo `base` => gana el del usuario).
    var addons: [Addon] {
        var out = userPlugins.compactMap { $0.enabled ? $0.addon : nil }
        let seen = Set(out.map { $0.base })
        out += builtin.filter { !disabledBuiltin.contains($0.base) && !seen.contains($0.base) }
        return out
    }

    /// Hay al menos un plugin que pueda dar fuentes de reproduccion.
    var hasStreamPlugin: Bool { addons.contains { !$0.stream.isEmpty } }

    private static let sources = [
        "https://raw.githubusercontent.com/kinotvapp/kino-plugins/main/catalog.json",
        "https://archive.org/download/kino-app/plugin-catalog.json",
        "https://cdn.jsdelivr.net/gh/kinotvapp/kino-plugins@main/catalog.json"
    ]
    private static let ttl: TimeInterval = 21600 // 6 h, igual que el original
    private let userKey = "kino_user_plugins_v1"
    private let disabledKey = "kino_disabled_builtin_v1"

    private var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("kino_addons_v1.json")
    }

    init() {
        if let d = UserDefaults.standard.data(forKey: userKey),
           let l = try? JSONDecoder().decode([UserPlugin].self, from: d) {
            userPlugins = l
        }
        disabledBuiltin = Set(UserDefaults.standard.stringArray(forKey: disabledKey) ?? [])
    }

    // MARK: Carga

    func load(force: Bool = false) async {
        state = .loading
        // Los plugins del usuario ya estan en disco: se usan al instante y se actualizan en segundo plano.
        Task { await refreshUserPlugins() }
        await loadBuiltin(force: force)
        state = addons.isEmpty ? .failed : .ready
    }

    private func loadBuiltin(force: Bool) async {
        let now = Date().timeIntervalSince1970
        let cache = readCache()
        if !force, let c = cache, now - c.t < Self.ttl {
            builtin = c.addons
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
        builtin = built
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

    // MARK: Plugins del usuario

    /// Agrega un plugin a partir de una URL (acepta https://, http://, stremio://, o sin esquema).
    func addPlugin(_ raw: String) async -> AddOutcome {
        guard let url = Self.normalize(raw) else {
            return .failed("La dirección no es válida.")
        }
        if let p = userPlugins.first(where: { $0.url == url }) { return .exists(name: p.name) }
        let probe = await Self.probe(url)
        guard let a = probe.addon else { return .failed(probe.error ?? "No se pudo leer el addon.") }
        // Pudo agregarse el mismo mientras se verificaba.
        if let p = userPlugins.first(where: { $0.url == url }) { return .exists(name: p.name) }
        userPlugins.append(UserPlugin(id: url, url: url, name: a.name, enabled: true,
                                      addon: a, error: nil, note: probe.warning))
        saveUser()
        return .added(name: a.name, warning: probe.warning)
    }

    func setEnabled(_ id: String, _ on: Bool) {
        guard let i = userPlugins.firstIndex(where: { $0.id == id }) else { return }
        userPlugins[i].enabled = on
        saveUser()
    }

    func removeUserPlugins(at offsets: IndexSet) {
        let ids = offsets.compactMap { $0 < userPlugins.count ? userPlugins[$0].id : nil }
        userPlugins.removeAll { ids.contains($0.id) }
        saveUser()
    }

    func setBuiltinEnabled(_ base: String, _ on: Bool) {
        if on { disabledBuiltin.remove(base) } else { disabledBuiltin.insert(base) }
        UserDefaults.standard.set(Array(disabledBuiltin), forKey: disabledKey)
    }

    /// Vuelve a leer el manifest de cada plugin del usuario. Si uno falla conserva la copia anterior.
    func refreshUserPlugins() async {
        let targets = userPlugins.filter { $0.enabled }.map { $0.url }
        guard !targets.isEmpty else { return }
        let results: [String: Probe] = await withTaskGroup(of: (String, Probe).self) { group in
            for u in targets { group.addTask { (u, await PluginStore.probe(u)) } }
            var out: [String: Probe] = [:]
            for await (u, p) in group { out[u] = p }
            return out
        }
        for i in userPlugins.indices {
            guard let p = results[userPlugins[i].url] else { continue }
            if let a = p.addon {
                userPlugins[i].addon = a
                userPlugins[i].name = a.name
                userPlugins[i].error = nil
                userPlugins[i].note = p.warning
            } else {
                userPlugins[i].error = p.error ?? "Sin respuesta."
            }
        }
        saveUser()
    }

    /// Boton "Actualizar" de la pantalla de plugins (no toca el estado global de la app).
    func refreshPlugins() async {
        refreshing = true
        await refreshUserPlugins()
        refreshing = false
    }

    /// Enlaces stremio://... o kinotv://... recibidos desde fuera de la app.
    func handleIncoming(_ url: URL) {
        var raw = url.absoluteString
        if url.scheme?.lowercased() == "kinotv" {
            if let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let q = c.queryItems?.first(where: { $0.name == "url" })?.value {
                raw = q
            } else {
                raw = String(raw.dropFirst("kinotv://".count))
            }
        }
        incoming = raw
    }

    private func saveUser() {
        if let d = try? JSONEncoder().encode(userPlugins) {
            UserDefaults.standard.set(d, forKey: userKey)
        }
    }

    // MARK: Manifest

    /// Deja la URL lista para pedir el manifest: stremio:// -> https://, agrega https:// si falta,
    /// quita /configure y asegura que termine en /manifest.json.
    nonisolated static func normalize(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        let low = s.lowercased()
        if low.hasPrefix("stremio://") {
            s = "https://" + String(s.dropFirst(10))
        } else if !low.hasPrefix("http://") && !low.hasPrefix("https://") {
            s = "https://" + s
        }
        guard var c = URLComponents(string: s), let host = c.host, !host.isEmpty else { return nil }
        var path = c.percentEncodedPath
        if !path.lowercased().hasSuffix("/manifest.json") {
            while path.hasSuffix("/") { path.removeLast() }
            if path.lowercased().hasSuffix("/configure") { path = String(path.dropLast(10)) }
            path += "/manifest.json"
        }
        c.percentEncodedPath = path
        c.fragment = nil
        return c.string
    }

    /// Descarga y valida un manifest. Nunca lanza: devuelve el addon o un mensaje de error legible.
    nonisolated static func probe(_ url: String) async -> Probe {
        guard let u = URL(string: url) else { return Probe(error: "La dirección no es válida.") }
        var req = URLRequest(url: u, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (d, r) = try await Http.session.data(for: req)
            guard let h = r as? HTTPURLResponse else { return Probe(error: "Respuesta inválida del servidor.") }
            guard (200..<300).contains(h.statusCode) else {
                return Probe(error: "El servidor respondió con el código \(h.statusCode).")
            }
            guard let mf = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else {
                return Probe(error: "No es un manifest de Stremio (no devolvió JSON).")
            }
            guard let a = buildAddon(mf, url: url, userAdded: true) else {
                return Probe(error: "El manifest no ofrece catálogos, fuentes ni subtítulos.")
            }
            var warns: [String] = []
            if let h = mf["behaviorHints"] as? [String: Any], h["configurationRequired"] as? Bool == true {
                warns.append("Pide configuración: usa la dirección ya configurada que te da su página.")
            }
            if a.stream.isEmpty { warns.append("No ofrece fuentes de reproducción.") }
            return Probe(addon: a, error: nil, warning: warns.isEmpty ? nil : warns.joined(separator: " "))
        } catch {
            return Probe(error: "No se pudo conectar: \(error.localizedDescription)")
        }
    }

    /// Solo los addons de Stremio (HTTP + JSON) se portan: los plugins "repo" de Kino son JavaScript
    /// para el motor QuickJS de Android y se omiten. Los que agrega el usuario no se filtran
    /// (adult / configurationRequired): es decision suya.
    nonisolated static func buildAddon(_ mf: [String: Any], url: String, userAdded: Bool = false) -> Addon? {
        if !userAdded, let h = mf["behaviorHints"] as? [String: Any] {
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

    // MARK: Cache de los plugins incluidos

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
