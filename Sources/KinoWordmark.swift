import SwiftUI

/// El logo "kino TV" en sus propias coordenadas (Y hacia abajo), igual que KinoWordmark.kt.
enum Wordmark {
    static let stroke: CGFloat = 42
    static let tvStroke: CGFloat = 26

    // Caja del logo completo, trazos incluidos.
    static let left: CGFloat = 126
    static let right: CGFloat = 984
    static let top: CGFloat = 84
    static let bottom: CGFloat = 350
    static var width: CGFloat { right - left }
    static var height: CGFloat { bottom - top }

    static let oCenter = CGPoint(x: 687, y: 252)
    static let oRadius: CGFloat = 80
    static let oStroke: CGFloat = 35
    static let dotRadius: CGFloat = 30.5

    static let iDot = CGPoint(x: 343, y: 123)
    static let iDotRadius: CGFloat = 25

    private static func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    static func k() -> Path {
        var p = Path()
        p.move(to: pt(147, 133)); p.addLine(to: pt(147, 324))
        p.move(to: pt(267, 170)); p.addLine(to: pt(199, 250)); p.addLine(to: pt(270, 324))
        p.move(to: pt(152, 250)); p.addLine(to: pt(199, 250))
        return p
    }

    static func iStem() -> Path {
        var p = Path()
        p.move(to: pt(343, 185)); p.addLine(to: pt(343, 324))
        return p
    }

    static func n() -> Path {
        var p = Path()
        p.move(to: pt(422, 324)); p.addLine(to: pt(422, 185))
        p.move(to: pt(422, 255))
        p.addCurve(to: pt(490, 182), control1: pt(422, 210), control2: pt(452, 182))
        p.addCurve(to: pt(544, 242), control1: pt(524, 182), control2: pt(544, 206))
        p.addLine(to: pt(544, 324))
        return p
    }

    static func tv() -> Path {
        var p = Path()
        p.move(to: pt(791, 97)); p.addLine(to: pt(862, 97))
        p.move(to: pt(826, 97)); p.addLine(to: pt(826, 182))
        p.move(to: pt(896, 97)); p.addLine(to: pt(933, 182)); p.addLine(to: pt(971, 97))
        return p
    }

    static func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    }
}

/// El logo estático, de `height` de alto (el ancho sigue la proporción del logo).
struct KinoWordmark: View {
    var height: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let scale = size.width / Wordmark.width
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -Wordmark.left, y: -Wordmark.top)

            let letter = StrokeStyle(lineWidth: Wordmark.stroke, lineCap: .round, lineJoin: .round)
            let tvStyle = StrokeStyle(lineWidth: Wordmark.tvStroke, lineCap: .round, lineJoin: .round)

            for path in [Wordmark.k(), Wordmark.iStem(), Wordmark.n()] {
                ctx.stroke(path, with: .color(.white), style: letter)
            }
            ctx.fill(Wordmark.circle(Wordmark.iDot, Wordmark.iDotRadius), with: .color(.white))
            ctx.stroke(Wordmark.circle(Wordmark.oCenter, Wordmark.oRadius), with: .color(.white), lineWidth: Wordmark.oStroke)
            ctx.fill(Wordmark.circle(Wordmark.oCenter, Wordmark.dotRadius), with: .color(Kino.logoRed))
            ctx.stroke(Wordmark.tv(), with: .color(.white), style: tvStyle)
        }
        .frame(width: height * Wordmark.width / Wordmark.height, height: height)
        .accessibilityLabel("Kino")
    }
}
