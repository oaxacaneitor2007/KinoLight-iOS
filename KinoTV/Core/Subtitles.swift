import Foundation

struct Cue {
    let start: Double
    let end: Double
    let text: String
}

/// Lee SRT y WebVTT. AVPlayer no carga subtitulos externos sueltos, asi que se muestran como capa propia.
enum Subtitles {
    static func load(_ url: String) async -> [Cue] {
        guard let d = await Http.data(url, timeout: 12, json: false) else { return [] }
        let text = String(data: d, encoding: .utf8)
            ?? String(data: d, encoding: .windowsCP1252)
            ?? String(data: d, encoding: .isoLatin1) ?? ""
        return parse(text)
    }

    static func parse(_ raw: String) -> [Cue] {
        let text = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var cues: [Cue] = []
        for block in text.components(separatedBy: "\n\n") {
            let lines = block.components(separatedBy: "\n")
            guard let ti = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let sides = lines[ti].components(separatedBy: "-->")
            guard sides.count == 2,
                  let a = seconds(sides[0]),
                  let b = seconds(sides[1].split(separator: " ").first.map(String.init) ?? "") else { continue }
            var body = lines[(ti + 1)...].joined(separator: "\n")
            body = body.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            body = body.replacingOccurrences(of: "\\{[^}]*\\}", with: "", options: .regularExpression)
            body = body.trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty { cues.append(Cue(start: a, end: b, text: body)) }
        }
        return cues
    }

    private static func seconds(_ s: String) -> Double? {
        let parts = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".").split(separator: ":")
        guard !parts.isEmpty else { return nil }
        var v = 0.0
        for p in parts {
            guard let d = Double(p) else { return nil }
            v = v * 60 + d
        }
        return v
    }
}
