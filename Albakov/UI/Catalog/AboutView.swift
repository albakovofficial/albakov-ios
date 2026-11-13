import SwiftUI

// «О бренде» (1.0.1): текст страницы из панели раскладывается по дизайну — как на сайте (app.js aboutPage).
// Первая строка **Название. Слоган.** — заголовок и девиз; список под вступлением — факты с объёмными иконками;
// разделы «## Стиль», «## Качество», «## Индивидуальность» — карточки-опоры; остальные «## …» — главы с номерами;
// последняя строка *Имя, роль* — подпись основателя, короткая фраза перед ней — его заключительные слова.

struct AboutDoc {
    struct Section { var title: String; var paras: [String] = []; var list: [String] = [] }
    var title = "", motto: [String] = [], lead: [String] = [], facts: [String] = [], sections: [Section] = [], sign = "", closing = ""

    init(_ body: String) {
        var cur: Int? = nil
        for raw in body.components(separatedBy: "\n") {
            let t = raw.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("![") { continue }   // фото основателя в приложении не показываем — на его месте знак бренда
            if t.hasPrefix("## ") { sections.append(Section(title: String(t.dropFirst(3)).trimmingCharacters(in: CharacterSet(charactersIn: "# ")))); cur = sections.count - 1; continue }
            if t.count > 2, t.hasPrefix("*"), t.hasSuffix("*"), !t.hasPrefix("**") { sign = String(t.dropFirst().dropLast()); continue }
            let item = t.hasPrefix("- ") ? String(t.dropFirst(2)) : nil
            if let i = cur {
                if let item { sections[i].list.append(item) } else { sections[i].paras.append(t) }
                continue
            }
            if t.hasPrefix("**"), t.hasSuffix("**"), t.count > 4, title.isEmpty {
                let parts = String(t.dropFirst(2).dropLast(2)).components(separatedBy: ".").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                title = parts.first ?? ""; motto = Array(parts.dropFirst()); continue
            }
            if let item { facts.append(item) } else { lead.append(t) }
        }
        if !sign.isEmpty, var last = sections.last, last.paras.count > 1, let p = last.paras.last, p.count < 90 {
            closing = p; last.paras.removeLast(); sections[sections.count - 1] = last
        }
    }

    static let pillarTitle = try? NSRegularExpression(pattern: "^(стиль|качество|индивидуальность|материал\\S*|ткан\\S*|крой|детали)$", options: .caseInsensitive)
    static func isPillar(_ title: String) -> Bool {
        let s = title.trimmingCharacters(in: .whitespaces)
        return pillarTitle?.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }
    /// Объёмная иконка с сайта (img/benefits/…webp) по словам в тексте — те же правила, что на сайте
    static let words: [(String, String)] = [
        ("стил|образ|гардероб", "style"), ("индивидуал|уникал|характер|личност", "gem"), ("петербург|москв|город|родил", "pin"), ("фабрик|россии|шьём|шьем|пошив|производ|отшив", "spool"),
        ("доставк|курьер|сдэк|отправ", "delivery"), ("качеств|гаранти|провер", "quality"), ("ткан|материал|шерст|кашемир|хлоп|шёлк|шелк|лён|трикотаж|пряж", "fabric"),
        ("примерк|подош|примерить", "fitting"), ("возврат|обмен|вернуть", "return"), ("оплат|карт|рассроч|сплит|долям", "payment"), ("подар|упаков", "gift")
    ]
    static let glow = ["style": "#c9925e", "gem": "#7b61ff", "spool": "#ff8b74", "pin": "#ff8b74", "delivery": "#1ab248", "quality": "#e8b84a", "fabric": "#c9925e",
                       "fitting": "#ff8b74", "return": "#7b61ff", "payment": "#16b5a5", "gift": "#f0587c"]
    static func icon(_ text: String) -> String? {
        let s = text.lowercased()
        return words.first { s.range(of: $0.0, options: .regularExpression) != nil }?.1
    }
}

struct AboutView: View {
    let page: Page
    @EnvironmentObject private var shop: Shop
    @EnvironmentObject private var router: Router
    private static let gold = Color(hex: "#e8b84a"), violet = Color(hex: "#7b61ff")

    var body: some View {
        let d = AboutDoc(shop.settings.fill(page.body))
        let motto = d.motto.isEmpty ? shop.settings.tagline.components(separatedBy: ".").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } : d.motto
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero(d, motto: motto)
                ForEach(Array(blocks(d).enumerated()), id: \.offset) { _, b in
                    switch b {
                    case .story(let s, let n): story(s, n: n)
                    case .pillars(let list): pillars(list)
                    }
                }
                if !d.sign.isEmpty || !d.closing.isEmpty { founder(d) }
            }
            .padding(.bottom, 32)
        }
        .navigationTitle(page.title).navigationBarTitleDisplayMode(.inline)
    }

    private enum Block { case story(AboutDoc.Section, n: Int), pillars([AboutDoc.Section]) }
    /// Подряд идущие опоры — одна сетка карточек, остальные разделы — главы по порядку
    private func blocks(_ d: AboutDoc) -> [Block] {
        var out: [Block] = [], n = 0
        for s in d.sections {
            if AboutDoc.isPillar(s.title) {
                if case .pillars(let list)? = out.last { out[out.count - 1] = .pillars(list + [s]) } else { out.append(.pillars([s])) }
            } else { n += 1; out.append(.story(s, n: n)) }
        }
        return out
    }

    // MARK: Обложка: знак бренда на светлом круге со свечением, надпись, девиз через точки, вступление и факты

    private func hero(_ d: AboutDoc, motto: [String]) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Eyebrow(text: page.title)
            ZStack {
                Circle().fill(Self.gold.opacity(0.45)).frame(width: 150).blur(radius: 40).offset(x: -60, y: -40)
                Circle().fill(Self.violet.opacity(0.4)).frame(width: 140).blur(radius: 40).offset(x: 70, y: 50)
                Circle().strokeBorder(Theme.ink.opacity(0.12)).frame(width: 236, height: 236)
                Image("Logo").resizable().scaledToFit().frame(width: 110)
            }
            .frame(maxWidth: .infinity).frame(height: 270)
            if d.title.isEmpty || d.title.lowercased() == shop.settings.storeName.lowercased() {
                Image("Wordmark").resizable().scaledToFit().frame(maxWidth: 300, alignment: .leading).accessibilityLabel(shop.settings.storeName)
            } else {
                Text(d.title).font(Theme.font(44, .light)).kerning(-1.4)
            }
            if !motto.isEmpty { mottoRow(motto) }
            ForEach(Array(d.lead.enumerated()), id: \.offset) { _, p in
                Text(Self.md(p)).font(Theme.font(17)).lineSpacing(6).foregroundStyle(Theme.muted)
            }
            if !d.facts.isEmpty {
                VStack(spacing: 10) {
                    ForEach(Array(d.facts.enumerated()), id: \.offset) { i, f in
                        fact(f, icon: AboutDoc.icon(f) ?? ["quality", "gem", "style"][i % 3])
                    }
                }.padding(.top, 8)
            }
        }
        .padding(.horizontal, Theme.gutter).padding(.top, 18).padding(.bottom, 36)
    }

    private func mottoRow(_ words: [String]) -> some View {
        FlowRow(spacing: 6) {
            ForEach(Array(words.enumerated()), id: \.offset) { i, w in
                HStack(spacing: 0) {
                    if i > 0 { Circle().fill(LinearGradient(colors: [Self.gold, Self.violet], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 5, height: 5).padding(.horizontal, 12) }
                    Text(w.uppercased()).font(Theme.font(12.5, .medium)).kerning(2.6).foregroundStyle(Theme.text)
                }
            }
        }
    }

    private func fact(_ text: String, icon: String) -> some View {
        HStack(spacing: 14) {
            RemoteImage(path: "img/benefits/\(icon).webp", contentMode: .fit).frame(width: 56, height: 56)
            Text(Self.md(text)).font(Theme.font(15)).foregroundStyle(Theme.text).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 10).padding(.trailing, 18).padding(.vertical, 10)
        .background(alignment: .leading) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 22).fill(Theme.surface)
                Circle().fill(Color(hex: AboutDoc.glow[icon] ?? "#c2c7cd").opacity(0.22)).frame(width: 120).blur(radius: 26).offset(x: -40)
            }.clipShape(RoundedRectangle(cornerRadius: 22))
        }
    }

    // MARK: Глава истории: номер с линией, крупный заголовок, первый абзац крупнее

    private func story(_ s: AboutDoc.Section, n: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Text(String(format: "%02d", n)).font(Theme.font(13)).kerning(2.6).foregroundStyle(Theme.dim)
                LinearGradient(colors: [Self.gold, Self.violet], startPoint: .leading, endPoint: .trailing).frame(width: 48, height: 1)
            }
            Text(s.title).font(Theme.font(32, .light)).kerning(-0.6).fixedSize(horizontal: false, vertical: true)
            if let first = s.paras.first {
                Text(Self.md(first)).font(Theme.font(19)).lineSpacing(6).foregroundStyle(Theme.text)
            }
            ForEach(Array(s.paras.dropFirst().enumerated()), id: \.offset) { _, p in
                Text(Self.md(p)).font(Theme.font(16)).lineSpacing(7).foregroundStyle(Theme.muted)
            }
            if !s.list.isEmpty { bullets(s.list) }
        }
        .padding(.horizontal, Theme.gutter).padding(.vertical, 40)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Divider1() }
    }

    private func bullets(_ list: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(list.enumerated()), id: \.offset) { _, x in
                HStack(alignment: .top, spacing: 12) {
                    Circle().fill(LinearGradient(colors: [Self.gold, Self.violet], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 8, height: 8).padding(.top, 8)
                    Text(Self.md(x)).font(Theme.font(16)).lineSpacing(5).foregroundStyle(Theme.muted)
                }
            }
        }
    }

    // MARK: Опоры: белые карточки с номером, объёмной иконкой и мягким свечением её цвета

    private func pillars(_ list: [AboutDoc.Section]) -> some View {
        VStack(spacing: 12) {
            ForEach(Array(list.enumerated()), id: \.offset) { i, s in
                let icon = AboutDoc.icon(s.title) ?? AboutDoc.icon(s.paras.joined(separator: " ")) ?? "quality"
                let glow = Color(hex: AboutDoc.glow[icon] ?? "#c2c7cd")
                VStack(alignment: .leading, spacing: 12) {
                    RemoteImage(path: "img/benefits/\(icon).webp", contentMode: .fit).frame(width: 120, height: 120).padding(.leading, -12).padding(.top, -10)
                    Text(s.title).font(Theme.font(28, .light)).kerning(-0.5)
                    ForEach(Array(s.paras.enumerated()), id: \.offset) { _, p in
                        Text(Self.md(p)).font(Theme.font(15.5)).lineSpacing(6).foregroundStyle(Theme.muted)
                    }
                    if !s.list.isEmpty { bullets(s.list) }
                }
                .padding(24).frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .topTrailing) { Text("\(i + 1)").font(Theme.font(13)).kerning(2.6).foregroundStyle(Theme.dim).padding(22) }
                .background {
                    ZStack(alignment: .topTrailing) {
                        RoundedRectangle(cornerRadius: 26).fill(.white)
                        Circle().fill(glow.opacity(0.26)).frame(width: 260).blur(radius: 50).offset(x: 80, y: -90)
                    }.clipShape(RoundedRectangle(cornerRadius: 26))
                }
                .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(Theme.line))
            }
        }
        .padding(.horizontal, Theme.gutter).padding(.vertical, 28)
        .background(LinearGradient(colors: [.white, Theme.surface, Theme.surface, .white], startPoint: .top, endPoint: .bottom))
    }

    // MARK: Слова основателя: знак, цитата, подпись и кнопка в каталог

    private func founder(_ d: AboutDoc) -> some View {
        let sign = d.sign.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return VStack(alignment: .leading, spacing: 18) {
            Image("Logo").resizable().scaledToFit().frame(width: 44).colorInvert()
            if !d.closing.isEmpty { Text(Self.md(d.closing)).font(Theme.font(24, .light)).lineSpacing(5).foregroundStyle(.white) }
            if let name = sign.first, !name.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(Theme.font(16, .semibold)).foregroundStyle(.white)
                    if sign.count > 1 { Text(sign.dropFirst().joined(separator: ", ")).font(Theme.font(13)).foregroundStyle(.white.opacity(0.6)) }
                }
            }
            Button { router.reset(.catalog) } label: {
                HStack(spacing: 12) { Text("Смотреть коллекцию").font(Theme.font(14, .medium)); ArrowDot(size: 34, dark: true) }
                    .foregroundStyle(Theme.text).padding(.leading, 20).padding(.trailing, 7).frame(height: 48).background(Capsule().fill(.white))
            }.buttonStyle(Pressable()).padding(.top, 4)
        }
        .padding(26).frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 26).fill(Theme.night)
                Circle().fill(Self.gold.opacity(0.22)).frame(width: 220).blur(radius: 50).offset(x: -60, y: -80)
                Circle().fill(Self.violet.opacity(0.22)).frame(width: 220).blur(radius: 50).offset(x: 200, y: 140)
            }.clipShape(RoundedRectangle(cornerRadius: 26))
        }
        .padding(.horizontal, Theme.gutter).padding(.top, 20)
    }

    /// **жирный**, *курсив* и [ссылки] внутри абзаца
    static func md(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}
