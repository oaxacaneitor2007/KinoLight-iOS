import Foundation

/// Cliente HTTP. Todo en paralelo y con timeout; devuelve lo que llegue.
enum Http {
    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.httpMaximumConnectionsPerHost = 8
        c.timeoutIntervalForResource = 25
        return URLSession(configuration: c)
    }()

    static func data(_ s: String, timeout: TimeInterval = 10, json: Bool = true) async -> Data? {
        guard let url = URL(string: s) else { return nil }
        var req = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: timeout)
        if json { req.setValue("application/json", forHTTPHeaderField: "Accept") }
        guard let (d, r) = try? await session.data(for: req),
              let h = r as? HTTPURLResponse,
              (200..<300).contains(h.statusCode) else { return nil }
        return d
    }

    static func object(_ s: String, timeout: TimeInterval = 10) async -> [String: Any]? {
        guard let d = await data(s, timeout: timeout) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }

    static func many(_ reqs: [(key: String, url: String)], timeout: TimeInterval = 10) async -> [String: Data] {
        await withTaskGroup(of: (String, Data?).self) { group in
            for r in reqs {
                group.addTask { (r.key, await Http.data(r.url, timeout: timeout)) }
            }
            var out: [String: Data] = [:]
            for await (k, d) in group {
                if let d = d { out[k] = d }
            }
            return out
        }
    }

    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func enc(_ s: String) -> String {
        return s.addingPercentEncoding(withAllowedCharacters: unreserved) ?? s
    }
}

// MARK: - Utilidades de JSON laxo (los addons no son uniformes)

func jStr(_ v: Any?) -> String {
    if let s = v as? String { return s }
    if let n = v as? NSNumber { return n.stringValue }
    return ""
}

func jInt(_ v: Any?) -> Int {
    if let n = v as? Int { return n }
    if let d = v as? Double { return Int(d) }
    if let s = v as? String { return Int(s) ?? 0 }
    return 0
}
