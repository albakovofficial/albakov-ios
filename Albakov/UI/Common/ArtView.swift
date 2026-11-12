import SwiftUI

/// Студийная заглушка товара без фото — та же, что на сайте (public/js/art.js): силуэт изделия
/// в цвете товара на светлом фоне с мягкой тенью. Как только у товара есть фото, показывается фото.
struct ArtView: View {
    var kind: String = "tee"
    var tone: String = "#3a3632"

    var body: some View {
        GeometryReader { geo in
            // viewBox 300×400, preserveAspectRatio="xMidYMid slice" — заполняет место с обрезкой по краям
            let s = max(geo.size.width / 300, geo.size.height / 400)
            let dx = (geo.size.width - 300 * s) / 2, dy = (geo.size.height - 400 * s) / 2
            ZStack(alignment: .topLeading) {
                RadialGradient(colors: [Color(hex: "#f9fafb"), Color(hex: "#e4e7eb")], center: UnitPoint(x: 0.5, y: 0.38), startRadius: 0, endRadius: 0.75 * 400 * s)
                Ellipse().fill(Color(red: 20 / 255, green: 20 / 255, blue: 22 / 255).opacity(0.14))
                    .frame(width: 192 * s, height: 18 * s).position(x: dx + 150 * s, y: dy + 364 * s)
                let shape = ArtView.shapes[kind] ?? ArtView.shapes["tee"]!
                ForEach(Array(shape.enumerated()), id: \.offset) { _, part in
                    let path = ArtView.path(part.d).applying(CGAffineTransform(translationX: dx / s, y: dy / s + 6).concatenating(CGAffineTransform(scaleX: s, y: s)))
                    switch part.kind {
                    case .fill:
                        path.fill(LinearGradient(colors: [ArtView.shade(tone, 1.25), ArtView.shade(tone, 0.78)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    case .stroke(let w, let a):
                        path.stroke(Color.black.opacity(a), style: StrokeStyle(lineWidth: w * s, lineCap: .butt, lineJoin: .miter))
                    case .handle(let w):
                        path.stroke(ArtView.shade(tone, 0.9), style: StrokeStyle(lineWidth: w * s))
                    case .dot(let a):
                        path.fill(Color.black.opacity(a))
                    }
                }
            }
        }
        .clipped()
    }

    enum Kind { case fill, stroke(CGFloat, Double), handle(CGFloat), dot(Double) }
    struct Part { let d: String; let kind: Kind }

    private static func dots(_ pts: [(CGFloat, CGFloat)]) -> Part {
        Part(d: pts.map { "M \($0.0 - 3) \($0.1) Q \($0.0 - 3) \($0.1 - 3) \($0.0) \($0.1 - 3) Q \($0.0 + 3) \($0.1 - 3) \($0.0 + 3) \($0.1) Q \($0.0 + 3) \($0.1 + 3) \($0.0) \($0.1 + 3) Q \($0.0 - 3) \($0.1 + 3) \($0.0 - 3) \($0.1) Z" }.joined(separator: " "), kind: .dot(0.35))
    }

    static let shapes: [String: [Part]] = [
        "coat": [Part(d: "M112 74 L138 62 L150 104 L162 62 L188 74 L232 100 L248 300 L226 305 L210 168 L214 352 L86 352 L90 168 L74 305 L52 300 L68 100 Z", kind: .fill),
                 Part(d: "M138 62 L150 104 L162 62 M150 104 L150 352", kind: .stroke(2, 0.28)),
                 dots([(140, 150), (140, 190), (160, 150), (160, 190)])],
        "knit": [Part(d: "M114 72 Q150 92 186 72 L232 96 L254 286 L230 292 L208 150 L210 312 L90 312 L92 150 L70 292 L46 286 L68 96 Z", kind: .fill),
                 Part(d: "M92 300 L208 300 M230 280 L252 276 M70 280 L48 276", kind: .stroke(6, 0.25)),
                 Part(d: "M118 74 Q150 96 182 74", kind: .stroke(5, 0.25))],
        "shirt": [Part(d: "M116 70 L138 62 L150 80 L162 62 L184 70 L230 96 L250 284 L228 290 L208 150 L210 320 L90 320 L92 150 L72 290 L50 284 L70 96 Z", kind: .fill),
                  Part(d: "M138 62 L150 92 L162 62 M150 92 L150 320", kind: .stroke(2, 0.22))],
        "tee": [Part(d: "M112 76 Q150 96 188 76 L240 100 L258 150 L222 162 L210 138 L212 316 L88 316 L90 138 L78 162 L42 150 L60 100 Z", kind: .fill),
                Part(d: "M116 78 Q150 100 184 78", kind: .stroke(4, 0.25))],
        "trousers": [Part(d: "M98 64 L202 64 L216 352 L166 352 L150 142 L134 352 L84 352 Z", kind: .fill),
                     Part(d: "M98 80 L202 80", kind: .stroke(3, 0.25)),
                     Part(d: "M122 84 L114 352 M178 84 L186 352", kind: .stroke(1.5, 0.18))],
        "dress": [Part(d: "M124 58 L140 58 Q150 74 160 58 L176 58 L184 128 L178 160 L232 350 L68 350 L122 160 L116 128 Z", kind: .fill),
                  Part(d: "M118 156 L182 156", kind: .stroke(3, 0.25))],
        "bag": [Part(d: "M112 140 Q112 70 150 70 Q188 70 188 140", kind: .handle(9)),
                Part(d: "M78 140 L222 140 L236 326 L64 326 Z", kind: .fill),
                Part(d: "M78 160 L222 160", kind: .stroke(2, 0.25))]
    ]

    /// Разбор пути SVG: команды M, L, Q, Z с абсолютными координатами (только они и есть в заглушках сайта)
    static func path(_ d: String) -> Path {
        var p = Path()
        let spaced = d.replacingOccurrences(of: "([MLQZ])", with: " $1 ", options: .regularExpression).replacingOccurrences(of: ",", with: " ")
        let toks = spaced.split(separator: " ").map(String.init)
        var i = 0, cmd = "M"
        func num() -> CGFloat { defer { i += 1 }; return i < toks.count ? CGFloat(Double(toks[i]) ?? 0) : 0 }
        while i < toks.count {
            let t = toks[i]
            if ["M", "L", "Q", "Z"].contains(t) { cmd = t; i += 1; if cmd == "Z" { p.closeSubpath() }; continue }
            switch cmd {
            case "M": p.move(to: CGPoint(x: num(), y: num())); cmd = "L"
            case "L": p.addLine(to: CGPoint(x: num(), y: num()))
            case "Q": let c = CGPoint(x: num(), y: num()); p.addQuadCurve(to: CGPoint(x: num(), y: num()), control: c)
            default: i += 1
            }
        }
        return p
    }

    static func shade(_ hex: String, _ k: Double) -> Color {
        var s = hex; if s.hasPrefix("#") { s.removeFirst() }
        let n = UInt64(s, radix: 16) ?? 0x3a3632
        func f(_ c: UInt64) -> Double { min(255, max(0, (Double(c) * k).rounded())) / 255 }
        return Color(.sRGB, red: f((n >> 16) & 255), green: f((n >> 8) & 255), blue: f(n & 255), opacity: 1)
    }
}

/// Фото товара, а если его нет — заглушка-силуэт, как на сайте
struct ProductImage: View {
    let path: String
    var kind = "tee"
    var tone = "#3a3632"
    var body: some View {
        if path.isEmpty { ArtView(kind: kind, tone: tone) } else { RemoteImage(path: path) }
    }
}
