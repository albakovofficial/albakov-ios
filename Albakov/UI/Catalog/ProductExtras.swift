import SwiftUI

// Блоки карточки товара, как на сайте: характеристики (js/specs.js), подбор размера и мерки,
// доставка в город, «Не подошёл размер», «Соберите образ».

// MARK: - Характеристики: один список для витрины и панели

enum Specs {
    struct Item { let k: String, label: String; var multi = false; var custom: String? = nil; let options: [(String, String)] }
    struct Group { let title: String; let items: [Item] }

    static let groups: [Group] = [
        Group(title: "Ткань", items: [
            Item(k: "composition", label: "Состав", custom: "Свой состав, например 90% хлопок, 10% лён", options: [("c100", "100% хлопок"), ("c100p", "100% хлопок пенье"), ("c95e5", "95% хлопок, 5% эластан"), ("c92e8", "92% хлопок, 8% эластан"), ("c80p20", "80% хлопок, 20% полиэстер"), ("c70p30", "70% хлопок, 30% полиэстер"), ("p100", "100% полиэстер"), ("w", "Шерсть с добавками")]),
            Item(k: "fabric", label: "Полотно", options: [("kulirka", "Кулирная гладь"), ("futer2", "Футер двухнитка"), ("futer3", "Футер трёхнитка с начёсом"), ("loop", "Футер петля"), ("pique", "Пике"), ("rib", "Рибана"), ("interlock", "Интерлок"), ("jersey", "Джерси"), ("denim", "Деним"), ("twill", "Твил")]),
            Item(k: "density", label: "Плотность", options: ["160", "180", "200", "220", "240", "260", "280", "300", "320", "350", "400"].map { ($0, "\($0) г/м²") })
        ]),
        Group(title: "Крой", items: [
            Item(k: "fit", label: "Посадка", options: [("oversize", "Оверсайз"), ("loose", "Свободная"), ("regular", "Прямая"), ("fitted", "Приталенная"), ("slim", "Облегающая")]),
            Item(k: "shoulder", label: "Плечо", options: [("dropped", "Спущенное"), ("classic", "Классическое"), ("raglan", "Реглан")]),
            Item(k: "sleeve", label: "Рукав", options: [("short", "Короткий"), ("short_long", "Удлинённый короткий"), ("three_q", "Три четверти"), ("long", "Длинный"), ("none", "Без рукава")]),
            Item(k: "length", label: "Длина", options: [("cropped", "Укороченная"), ("standard", "Стандартная"), ("long", "Удлинённая")]),
            Item(k: "neck", label: "Горловина", options: [("round", "Круглая"), ("v", "V-образная"), ("polo", "Поло"), ("stand", "Стойка"), ("hood", "Капюшон"), ("boat", "Лодочка")])
        ]),
        Group(title: "Детали", items: [
            Item(k: "decor", label: "Отделка", multi: true, options: [("embroidery", "Вышивка"), ("print", "Принт"), ("silk", "Шелкография"), ("dtf", "DTF-печать"), ("patch", "Нашивка"), ("plain", "Без декора")]),
            Item(k: "decorPlace", label: "Расположение", multi: true, options: [("chest", "На груди"), ("center", "По центру"), ("back", "На спине"), ("sleeve", "На рукаве")]),
            Item(k: "features", label: "Особенности", multi: true, options: [("collar", "Усиленный ворот"), ("double", "Двойная строчка"), ("preshrunk", "Ткань с предусадкой"), ("opaque", "Не просвечивает"), ("nopill", "Не скатывается"), ("seamless", "Без боковых швов"), ("unisex", "Унисекс посадка")])
        ]),
        Group(title: "Прочее", items: [
            Item(k: "season", label: "Сезон", multi: true, options: [("summer", "Лето"), ("demi", "Демисезон"), ("all", "Круглый год"), ("winter", "Зима")]),
            Item(k: "country", label: "Производство", custom: "Своя страна", options: [("ru", "Россия"), ("kg", "Киргизия"), ("uz", "Узбекистан"), ("tr", "Турция"), ("cn", "Китай")])
        ])
    ]
    static let care: [(String, String)] = [("w30", "Стирка при 30 °C"), ("w40", "Стирка при 40 °C"), ("delicate", "Деликатная стирка"), ("inside", "Стирать наизнанку"), ("nobleach", "Не отбеливать"), ("iron2", "Гладить при средней температуре"), ("noironprint", "Не гладить по нанесению"), ("nodryer", "Не сушить в машине"), ("flat", "Сушить в расправленном виде"), ("nodryclean", "Без химчистки")]
    static let careIcon = ["w30": "drop", "w40": "drop.fill", "delicate": "water.waves", "inside": "arrow.uturn.left", "nobleach": "triangle", "iron2": "flame", "noironprint": "flame.circle", "nodryer": "circle.slash", "flat": "rectangle", "nodryclean": "xmark.circle"]
    static var items: [String: Item] { Dictionary(uniqueKeysWithValues: groups.flatMap(\.items).map { ($0.k, $0) }) }

    static func text(_ specs: JSON, _ it: Item) -> String {
        let v = specs[it.k]
        if it.multi { return (v.array.isEmpty ? [v] : v.array).compactMap { x in it.options.first { $0.0 == x.str }?.1 }.joined(separator: ", ") }
        let s = v.str
        if s.hasPrefix("custom:") { return String(s.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
        return it.options.first { $0.0 == s }?.1 ?? ""
    }
    /// Заполненные характеристики: [(k, label, value)]; состав — из списка, иначе из свободного поля
    static func list(_ p: Product) -> [(k: String, label: String, value: String)] {
        var out: [(k: String, label: String, value: String)] = []
        for g in groups { for it in g.items {
            var v = text(p.specs, it)
            if v.isEmpty && it.k == "composition" && !p.composition.isEmpty { v = p.composition.components(separatedBy: "\n")[0].trimmingCharacters(in: .whitespaces) }
            if !v.isEmpty { out.append((it.k, it.label, v)) }
        } }
        return out
    }
    static func careList(_ p: Product) -> [(String, String)] { let c = p.specs["care"].array.map(\.str); return care.filter { c.contains($0.0) } }
    /// «100% хлопок · 240 г/м² · Оверсайз»
    static func summary(_ p: Product) -> [String] { let l = list(p); return ["composition", "density", "fit"].compactMap { k in l.first { $0.k == k }?.value } }
}

/// Блок «Характеристики»: главное плитками, остальное строками, особенности капсулами, уход значками
struct SpecsBlock: View {
    let product: Product
    var body: some View {
        let rows = Specs.list(product), care = Specs.careList(product)
        let feat = rows.first { $0.k == "features" }?.value.components(separatedBy: ", ") ?? []
        let rest = rows.filter { $0.k != "features" }
        let hero = ["composition", "density", "fabric", "fit"].compactMap { k in rest.first { $0.k == k } }
        let main = rest.filter { r in !hero.contains { $0.k == r.k } }
        if !rest.isEmpty || !feat.isEmpty || !care.isEmpty || !product.care.isEmpty {
            AccordionCard(icon: "tag", title: "Характеристики", hint: Specs.summary(product).joined(separator: " · "), open: true) {
                VStack(alignment: .leading, spacing: 16) {
                    if !hero.isEmpty {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                            ForEach(hero, id: \.k) { r in
                                VStack(alignment: .leading, spacing: 4) { Text(r.label).font(Theme.font(13)).foregroundStyle(Theme.muted); Text(r.value).font(Theme.font(14.5, .medium)).foregroundStyle(Theme.text) }
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 16)
                                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
                            }
                        }
                    }
                    if !main.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(main, id: \.k) { r in
                                HStack(alignment: .top) { Text(r.label).font(Theme.font(14)).foregroundStyle(Theme.muted); Spacer(minLength: 12); Text(r.value).font(Theme.font(14)).multilineTextAlignment(.trailing) }
                                    .padding(.vertical, 10).overlay(alignment: .bottom) { Divider1() }
                            }
                        }
                    }
                    if !feat.isEmpty {
                        FlowRow(spacing: 6) { ForEach(feat, id: \.self) { Text($0).font(Theme.font(12.5)).padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(Theme.surface)) } }
                    }
                    if !care.isEmpty || !product.care.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Уход").font(Theme.font(14.5, .medium))
                            ForEach(care, id: \.0) { c in
                                HStack(spacing: 10) { Image(systemName: Specs.careIcon[c.0] ?? "circle").font(.system(size: 14, weight: .light)).frame(width: 24); Text(c.1).font(Theme.font(14)).foregroundStyle(Theme.muted) }
                            }
                            if !product.care.isEmpty { Text(product.care).font(Theme.font(14)).foregroundStyle(Theme.muted) }
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
                    }
                }
            }
        }
    }
}

// MARK: - Подбор размера по росту и весу, сравнение со своей футболкой, мерки изделия

enum Fit {
    struct Row { var size: String; var w = 0.0, l = 0.0, sl = 0.0, hMin = 0.0, hMax = 0.0, kMin = 0.0, kMax = 0.0; var typical = false }
    static let typicalTable: [String: [Double]] = ["XS": [150, 165, 45, 58], "S": [160, 172, 52, 66], "M": [170, 180, 62, 76], "L": [176, 186, 72, 86], "XL": [182, 192, 82, 96], "2XL": [186, 198, 92, 110], "XXL": [186, 198, 92, 110], "3XL": [190, 205, 105, 125], "XXXL": [190, 205, 105, 125]]
    static let prefs = [("close", "Ближе к телу"), ("free", "Свободно, как задумано"), ("xfree", "Очень свободно")]

    static func rows(_ p: Product) -> [Row] {
        p.fit["rows"].array.filter { !$0["size"].str.isEmpty }.map { r in
            Row(size: r["size"].str, w: r["w"].double ?? 0, l: r["l"].double ?? 0, sl: r["sl"].double ?? 0, hMin: r["hMin"].double ?? 0, hMax: r["hMax"].double ?? 0, kMin: r["kMin"].double ?? 0, kMax: r["kMax"].double ?? 0)
        }
    }
    static func sizes(_ p: Product) -> [String] { var out: [String] = []; for c in p.colors { for s in c.sizes where !s.size.isEmpty && !out.contains(s.size) { out.append(s.size) } }; return out }
    /// Рост и вес: из панели, а если не заполнены — по типичной сетке
    static func rangeRows(_ p: Product) -> [Row] {
        let own = rows(p).filter { $0.hMin > 0 && $0.hMax >= $0.hMin && $0.kMin > 0 && $0.kMax >= $0.kMin }
        if own.count >= 2 { return own }
        let base = rows(p)
        let r: [Row] = sizes(p).compactMap { sz in
            guard let t = typicalTable[sz.uppercased().replacingOccurrences(of: " ", with: "")] else { return nil }
            var x = base.first { $0.size == sz } ?? Row(size: sz)
            x.hMin = t[0]; x.hMax = t[1]; x.kMin = t[2]; x.kMax = t[3]; x.typical = true
            return x
        }
        return r.count >= 2 ? r : []
    }
    static func canPick(_ p: Product) -> Bool { rangeRows(p).count >= 2 }
    static func canCompare(_ p: Product) -> Bool { rows(p).filter { $0.w > 0 && $0.l > 0 }.count >= 2 }
    /// Ближайший размер по росту и ближайший по весу — берём больший, затем поправка на посадку
    static func pick(_ p: Product, h: Double, kg: Double, pref: String) -> (row: Row, prev: Row?, outside: Bool)? {
        let rs = rangeRows(p); guard !rs.isEmpty else { return nil }
        func near(_ v: Double, _ lo: Double, _ hi: Double) -> Double { v < lo ? lo - v : v > hi ? v - hi : 0 }
        func arg(_ f: (Row) -> Double) -> Int { var bi = 0, bv = Double.infinity; for (i, r) in rs.enumerated() { let v = f(r); if v < bv - 1e-9 { bv = v; bi = i } }; return bi }
        let ih = arg { near(h, $0.hMin, $0.hMax) * 10 + abs(h - ($0.hMin + $0.hMax) / 2) / 100 }
        let ik = arg { near(kg, $0.kMin, $0.kMax) * 10 + abs(kg - ($0.kMin + $0.kMax) / 2) / 100 }
        var i = max(ih, ik) + (pref == "close" ? -1 : pref == "xfree" ? 1 : 0)
        let outside = near(h, rs[0].hMin, rs[rs.count - 1].hMax) > 6 || near(kg, rs[0].kMin, rs[rs.count - 1].kMax) > 8
        i = max(0, min(rs.count - 1, i))
        return (rs[i], i > 0 ? rs[i - 1] : nil, outside)
    }
    static func cm(_ v: Double) -> String { v > 0 ? (v.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(v))" : String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",")) + " см" : "—" }

    // Сохранённые мерки покупателя — как localStorage «albakov:fit» на сайте
    static var saved: [String: Any] {
        get { UserDefaults.standard.dictionary(forKey: "fit") ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "fit") }
    }
}

/// «Убедитесь, что размер ваш»: до подбора — приглашение, после — вывод под выбранный размер
struct FitCheckCard: View {
    let product: Product, color: PColor
    let selected: String?
    let onFind: () -> Void, onCompare: () -> Void, onPick: (String) -> Void
    @AppStorage("fitTick") private var tick = 0
    var body: some View {
        let sv = Fit.saved
        let h = sv["h"] as? Double ?? 0, kg = sv["kg"] as? Double ?? 0, pref = sv["pref"] as? String ?? "free", done = sv["done"] as? Bool ?? false
        let res = done && h > 0 && kg > 0 ? Fit.pick(product, h: h, kg: kg, pref: pref) : nil
        let _ = tick
        if Fit.canPick(product) {
            HStack(alignment: .top, spacing: 14) {
                Group {
                    if let res, selected == res.row.size { Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).frame(width: 40, height: 40).background(Circle().fill(Theme.ok)) }
                    else { Image(systemName: "ruler").font(.system(size: 16, weight: .light)).frame(width: 40, height: 40).background(Circle().fill(.white)).hairline(Circle()) }
                }
                VStack(alignment: .leading, spacing: 8) {
                    if let res {
                        let rec = res.row.size, recOut = (color.sizes.first { $0.size == rec }?.stock ?? 1) <= 0
                        let pn = ["close": "ближе к телу", "free": "свободно", "xfree": "очень свободно"][pref] ?? ""
                        Text("ВАШИ МЕРКИ: \(Int(h)) СМ · \(Int(kg)) КГ · \(pn.uppercased())").font(Theme.font(10.5, .medium)).kerning(1).foregroundStyle(Theme.muted)
                        if selected == rec {
                            Text("\(rec) — ваш размер").font(Theme.font(19, .medium))
                            Text("Сядет " + (["close": "аккуратно, ближе к телу", "free": "свободно — так, как задумано", "xfree": "очень свободно, с запасом"][pref] ?? "") + ".").font(Theme.font(14)).foregroundStyle(Theme.muted)
                        } else if let s = selected {
                            Text("Вам скорее подойдёт \(rec)").font(Theme.font(19, .medium))
                            Text("Вы выбрали \(s). По вашим меркам \(rec) сядет так, как задумано" + (recOut ? " — но в этом цвете его сейчас нет." : ".")).font(Theme.font(14)).foregroundStyle(Theme.muted)
                        } else {
                            Text("Ваш размер — \(rec)" + (recOut ? " (в этом цвете сейчас нет)" : "")).font(Theme.font(19, .medium))
                            Text("Подобрали по вашим меркам. Отметьте его ниже или нажмите «Выбрать».").font(Theme.font(14)).foregroundStyle(Theme.muted)
                        }
                        HStack(spacing: 14) {
                            if selected != rec && !recOut { Button { onPick(rec) } label: { Text("Выбрать \(rec)").font(Theme.font(14, .medium)).foregroundStyle(.white).padding(.horizontal, 18).frame(height: 40).background(Capsule().fill(Theme.ink)) } }
                            Button("Изменить мерки", action: onFind).font(Theme.font(13.5)).foregroundStyle(Theme.text)
                            if Fit.canCompare(product) { Button("Сравнить", action: onCompare).font(Theme.font(13.5)).foregroundStyle(Theme.muted) }
                        }.padding(.top, 4)
                        if res.row.typical { Text("По типичной размерной сетке").font(Theme.font(12)).foregroundStyle(Theme.dim) }
                    } else {
                        Text("ПОДБОР РАЗМЕРА · 10 СЕКУНД").font(Theme.font(10.5, .medium)).kerning(1.2).foregroundStyle(Theme.muted)
                        Text(selected.map { "Убедитесь, что \($0) — ваш размер" } ?? "Не уверены в размере?").font(Theme.font(19, .medium))
                        Text("Чтобы вещь села именно так, как задумано, рекомендуем свериться с подбором: укажите рост и вес — подскажем ваш размер и как он сядет.").font(Theme.font(14)).foregroundStyle(Theme.muted).lineSpacing(3)
                        Button(action: onFind) {
                            HStack { Text("Подобрать размер").font(Theme.font(14, .medium)); Spacer(); ArrowDot(size: 26) }
                                .foregroundStyle(.white).padding(.leading, 20).padding(.trailing, 9).frame(height: 44).background(Capsule().fill(Theme.accentGradient))
                        }.buttonStyle(Pressable()).padding(.top, 6)
                        if Fit.canCompare(product) { Button("Сравнить со своей футболкой", action: onCompare).font(Theme.font(13.5)).foregroundStyle(Theme.text).padding(.top, 2) }
                    }
                }
            }
            .padding(.leading, 14).padding([.top, .bottom, .trailing], 18)
            .background(RoundedRectangle(cornerRadius: 22).fill(RadialGradient(colors: [Color(hex: "#f6f3ee"), .white], center: .topLeading, startRadius: 0, endRadius: 260)))
            .hairline(RoundedRectangle(cornerRadius: 22))
        }
    }
}

/// «Подбор размера»: рост, вес, как любите носить → ваш размер
struct FitFinderSheet: View {
    let product: Product, color: PColor
    let onPick: (String) -> Void
    var onCompare: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @AppStorage("fitTick") private var tick = 0
    @State private var h: Double = (Fit.saved["h"] as? Double) ?? 178
    @State private var kg: Double = (Fit.saved["kg"] as? Double) ?? 75
    @State private var pref: String = (Fit.saved["pref"] as? String) ?? "free"
    var body: some View {
        let res = Fit.pick(product, h: h, kg: kg, pref: pref)
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Eyebrow(text: product.name)
                DotTitle(text: "Подбор размера", size: 32, dot: false)
                slider("Рост", $h, 145...210, "см")
                slider("Вес", $kg, 40...150, "кг")
                VStack(alignment: .leading, spacing: 10) {
                    Text("Как любите носить").font(Theme.font(14)).foregroundStyle(Theme.muted)
                    FlowRow(spacing: 8) { ForEach(Fit.prefs, id: \.0) { p in Chip(title: p.1, on: pref == p.0, height: 40) { pref = p.0 } } }
                }
                if let res {
                    let r = res.row
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Ваш размер").font(Theme.font(13)).foregroundStyle(Theme.muted)
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            Text(r.size).font(Theme.font(54, .light))
                            Text(["close": "Сядет аккуратнее, ближе к телу", "free": "Сядет свободно — так, как задумано", "xfree": "Сядет очень свободно, с запасом"][pref] ?? "").font(Theme.font(14)).foregroundStyle(Theme.muted)
                        }
                        let meas = [("Ширина", r.w), ("Длина", r.l), ("Рукав", r.sl)].filter { $0.1 > 0 }
                        if !meas.isEmpty {
                            HStack(spacing: 8) {
                                ForEach(meas, id: \.0) { m in VStack(alignment: .leading, spacing: 2) { Text(m.0).font(Theme.font(12)).foregroundStyle(Theme.muted); Text(Fit.cm(m.1)).font(Theme.font(15, .medium)) }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(RoundedRectangle(cornerRadius: 12).fill(.white)) }
                            }
                        }
                        if res.outside { Text("Ваши параметры на краю нашей сетки — сверьтесь с мерками изделия или со своей футболкой.").font(Theme.font(13.5)).foregroundStyle(Theme.warn) }
                        else if pref == "free", let prev = res.prev { Text("Сомневаетесь между \(prev.size) и \(r.size)? Крой уже свободный: \(prev.size) сядет аккуратнее, \(r.size) — как задумано.").font(Theme.font(13.5)).foregroundStyle(Theme.muted) }
                        if (color.sizes.first { $0.size == r.size }?.stock ?? 1) <= 0 { Text("В цвете «\(color.name)» этого размера сейчас нет").font(Theme.font(13)).foregroundStyle(Theme.danger) }
                        if r.typical { Text("Подбор по типичной размерной сетке. Точные мерки изделия — в «Таблице размеров».").font(Theme.font(12)).foregroundStyle(Theme.dim) }
                    }.padding(18).background(RoundedRectangle(cornerRadius: 20).fill(Theme.surface))
                    PrimaryButton(title: "Выбрать размер \(r.size)") { save(done: true); dismiss(); onPick(r.size) }
                }
                if let onCompare, Fit.canCompare(product) { Button("Сравнить со своей футболкой") { dismiss(); onCompare() }.font(Theme.font(14)).foregroundStyle(Theme.text).frame(maxWidth: .infinity) }
            }.padding(20)
        }
        .onChange(of: h) { _ in save(done: false) }.onChange(of: kg) { _ in save(done: false) }.onChange(of: pref) { _ in save(done: false) }
    }
    private func save(done: Bool) {
        var s = Fit.saved; s["h"] = h.rounded(); s["kg"] = kg.rounded(); s["pref"] = pref; if done { s["done"] = true }; Fit.saved = s; tick += 1
    }
    private func slider(_ t: String, _ v: Binding<Double>, _ r: ClosedRange<Double>, _ u: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(t).font(Theme.font(15)); Spacer(); Text("\(Int(v.wrappedValue.rounded())) \(u)").font(Theme.font(17, .medium)) }
            Slider(value: v, in: r, step: 1).tint(Theme.ink)
        }
    }
}

/// «Сравнить со своей»: ширина и длина любимой футболки → ближайший наш размер
struct FitCompareSheet: View {
    let product: Product, color: PColor
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var w = (Fit.saved["w"] as? Double).map { String(Int($0)) } ?? ""
    @State private var l = (Fit.saved["l"] as? Double).map { String(Int($0)) } ?? ""
    var body: some View {
        let rows = Fit.rows(product).filter { $0.w > 0 && $0.l > 0 }
        let wv = Double(w.replacingOccurrences(of: ",", with: ".")) ?? 0, lv = Double(l.replacingOccurrences(of: ",", with: ".")) ?? 0
        let best = wv > 20 && lv > 30 ? rows.min { abs($0.w - wv) * 1.5 + abs($0.l - lv) < abs($1.w - wv) * 1.5 + abs($1.l - lv) } : nil
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Eyebrow(text: product.name)
                DotTitle(text: "Сравнить со своей", size: 30, dot: false)
                Text("Возьмите футболку, которая сидит на вас идеально, разложите её ровно и измерьте: ширину — по линии подмышек, длину — от плеча до низа.").font(Theme.font(14.5)).foregroundStyle(Theme.muted)
                HStack(spacing: 10) { Field(label: "1 · Ширина, см", text: $w, placeholder: "например, 56", keyboard: .decimalPad); Field(label: "2 · Длина, см", text: $l, placeholder: "например, 72", keyboard: .decimalPad) }
                if let best {
                    VStack(spacing: 6) {
                        ForEach(rows, id: \.size) { r in
                            HStack {
                                Text(r.size).font(Theme.font(15, .medium)).frame(width: 44, alignment: .leading)
                                Text(diff(r.w - wv, "Ширина", "шире", "уже")).font(Theme.font(13))
                                Spacer()
                                Text(r.size == best.size ? "ближе всего" : diff(r.l - lv, "Длина", "длиннее", "короче")).font(Theme.font(13)).foregroundStyle(r.size == best.size ? Theme.ok : Theme.muted)
                            }.padding(12).background(RoundedRectangle(cornerRadius: 12).fill(r.size == best.size ? .white : Theme.surface)).overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(r.size == best.size ? Theme.accent : .clear))
                        }
                    }
                    PrimaryButton(title: "Выбрать размер \(best.size)") { dismiss(); onPick(best.size) }
                } else { Text("Введите обе мерки — покажем, какой наш размер ближе.").font(Theme.font(14)).foregroundStyle(Theme.muted) }
            }.padding(20)
        }
        .onChange(of: w) { _ in store() }.onChange(of: l) { _ in store() }
    }
    private func store() { var s = Fit.saved; if let x = Double(w) { s["w"] = x }; if let x = Double(l) { s["l"] = x }; Fit.saved = s }
    private func diff(_ v: Double, _ word: String, _ more: String, _ less: String) -> String {
        let d = (v * 10).rounded() / 10
        return abs(d) < 0.5 ? word + " как у вашей" : (d > 0 ? more : less) + " на " + String(format: "%g", abs(d)).replacingOccurrences(of: ".", with: ",") + " см"
    }
}

/// Мерки изделия: ширина, длина, рукав, рост и вес по размерам
struct MeasuresTable: View {
    let product: Product
    var body: some View {
        let rows = Fit.rows(product).filter { $0.w > 0 || $0.l > 0 || $0.sl > 0 }
        if !rows.isEmpty {
            let hasSl = rows.contains { $0.sl > 0 }, hasH = rows.contains { $0.hMin > 0 }
            VStack(alignment: .leading, spacing: 10) {
                DotTitle(text: "Мерки изделия", size: 28, dot: false)
                Text("Футболку разложили на столе и измерили. Ширина — от шва до шва под рукавами, длина — от плеча до низа.").font(Theme.font(14)).foregroundStyle(Theme.muted)
                ScrollView(.horizontal, showsIndicators: false) {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 0) {
                        GridRow { ForEach(["Размер", "Ширина", "Длина"] + (hasSl ? ["Рукав"] : []) + (hasH ? ["Рост", "Вес"] : []), id: \.self) { Text($0).font(Theme.font(12.5)).foregroundStyle(Theme.muted).padding(.vertical, 10) } }
                        ForEach(rows, id: \.size) { r in
                            Divider1().gridCellUnsizedAxes(.horizontal)
                            GridRow {
                                Text(r.size).font(Theme.font(14.5, .medium)); Text(Fit.cm(r.w)); Text(Fit.cm(r.l))
                                if hasSl { Text(Fit.cm(r.sl)) }
                                if hasH { Text(r.hMin > 0 ? "\(Int(r.hMin))–\(Int(r.hMax))" : "—"); Text(r.kMin > 0 ? "\(Int(r.kMin))–\(Int(r.kMax))" : "—") }
                            }.font(Theme.font(14.5)).padding(.vertical, 10)
                        }
                    }.padding(.horizontal, 16).padding(.vertical, 6)
                }.background(RoundedRectangle(cornerRadius: 18).fill(.white)).hairline(RoundedRectangle(cornerRadius: 18), 0.08)
            }
        }
    }
}

// MARK: - Доставка в город: срок и цена СДЭК для этого товара

struct ShipEstimate: View {
    let product: Product
    @EnvironmentObject private var shop: Shop
    @State private var methods: [JSON] = []
    @State private var loading = true
    @State private var pickCity = false
    @AppStorage("shipCityCode") private var code = 44
    @AppStorage("shipCityName") private var city = "Москва"
    private static func inCity(_ n: String) -> String { n.hasSuffix("а") ? String(n.dropLast()) + "у" : n.hasSuffix("я") ? String(n.dropLast()) + "ю" : n }
    var body: some View {
        let cdek = shop.settings.delivery.filter { $0.isPvz || $0.isDoor || $0.priceAuto }
        if !cdek.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    IconTile(icon: "truck.box", size: 36)
                    Button { pickCity = true } label: {
                        HStack(spacing: 6) {
                            Text("Доставка в").foregroundStyle(Theme.text)
                            Text(ShipEstimate.inCity(city)).foregroundStyle(Theme.text).underline(pattern: .dot)
                            Image(systemName: "chevron.down").font(.system(size: 10, weight: .medium))
                        }.font(Theme.font(16)).foregroundStyle(Theme.text)
                    }
                }
                if loading { ProgressView().frame(maxWidth: .infinity) }
                let price = shop.price(product).price
                ForEach(Array((methods.isEmpty ? cdek.map { m in JSON(["name": m.name, "kind": m.isDoor ? "door" : "pvz", "price": m.price, "known": !m.priceAuto, "freeFrom": m.freeFrom] as [String: Any]) } : methods).enumerated()), id: \.offset) { _, m in
                    let free = (m["freeFrom"].int ?? 0) > 0 && price >= (m["freeFrom"].int ?? 0)
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m["kind"].str == "door" ? "Курьером до двери" : "В пункт выдачи СДЭК").font(Theme.font(14.5))
                            if !m["days"].str.isEmpty { Text(ShipEstimate.days(m["days"].str)).font(Theme.font(12.5)).foregroundStyle(Theme.muted) }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            if free { Text("Бесплатно").font(Theme.font(14.5, .medium)).foregroundStyle(Theme.ok) }
                            else if !m["known"].bool { Text("по тарифу СДЭК").font(Theme.font(14)); Text("цену покажем при оформлении").font(Theme.font(11.5)).foregroundStyle(Theme.muted) }
                            else { Text((m["price"].int ?? 0) > 0 ? Fmt.rub(m["price"].int ?? 0) : "Бесплатно").font(Theme.font(14.5)) }
                            if !free && (m["freeFrom"].int ?? 0) > 0 { Text("бесплатно от \(Fmt.rub(m["freeFrom"].int ?? 0))").font(Theme.font(12)).foregroundStyle(Theme.muted) }
                        }
                    }
                }
                if methods.contains(where: { !$0["days"].str.isEmpty }) { Text("Срок СДЭК — со дня отправки заказа. Точную цену покажем при оформлении.").font(Theme.font(12)).foregroundStyle(Theme.dim) }
            }
            .padding(.horizontal, 18).padding(.vertical, 16).softCard(18)
            .task(id: code) { await load() }
            .sheet(isPresented: $pickCity) { CityPicker { c in code = c.code; city = c.city; pickCity = false } }
        }
    }
    private func load() async {
        loading = true; defer { loading = false }
        if let r = try? await API.shared.json("GET", "cdek/estimate", query: ["city": String(code), "pid": product.id]) { methods = r["methods"].array }
    }
    static func days(_ d: String) -> String {
        let n = Int(d.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }.last ?? "") ?? 0
        return d + " " + Fmt.plural(n, "день", "дня", "дней")
    }
}

/// «Не подошёл размер — обменяем бесплатно»
struct FitGuarantee: View {
    @EnvironmentObject private var shop: Shop
    var body: some View {
        let e = shop.settings.raw["exchange"], enabled = !e["enabled"].exists || e["enabled"].bool, free = !e["free"].exists || e["free"].bool
        let days = max(1, e["days"].int ?? 14)
        if enabled {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 18, weight: .light)).foregroundStyle(Theme.text).padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(free ? "Не подошёл размер — обменяем бесплатно" : "Не подошёл размер — обменяем").font(Theme.font(14.5, .medium)).foregroundStyle(Theme.text)
                    Text("В течение \(days) \(Fmt.plural(days, "дня", "дней", "дней")) после получения — в пару нажатий в личном кабинете. Новый размер отправим, как только вещь вернётся к нам" + (free ? ", доставка в обе стороны за наш счёт." : "."))
                        .font(Theme.font(13)).foregroundStyle(Theme.muted).lineSpacing(3)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 18).fill(Theme.surface)).hairline(RoundedRectangle(cornerRadius: 18))
        }
    }
}

// MARK: - «Соберите образ»: вещи, отмеченные в панели «С этим носят»

struct LookSection: View {
    let product: Product
    let mainColor: PColor
    let mainSize: String?
    @EnvironmentObject private var shop: Shop
    @EnvironmentObject private var router: Router
    @State private var off: Set<String> = []
    @State private var sizes: [String: String] = [:]
    var body: some View {
        let items = product.look.compactMap { id in shop.products.first { $0.id == id && $0.id != product.id && $0.stock > 0 } }.prefix(4)
        if !items.isEmpty {
            let all = [product] + Array(items)
            let chosen = all.filter { !off.contains($0.id) }
            let sum = chosen.reduce(0) { $0 + shop.price($1).price }
            let old = chosen.reduce(0) { let pr = shop.price($1); return $0 + (pr.oldPrice > 0 ? pr.oldPrice : pr.price) }
            VStack(alignment: .leading, spacing: 18) {
                DotTitle(text: "Соберите образ", size: 28)
                ForEach(Array(all.enumerated()), id: \.offset) { i, x in
                    let c = i == 0 ? mainColor : (x.colors.first { $0.stock > 0 } ?? x.colors[0])
                    let avail = c.sizes.filter { $0.stock > 0 }
                    HStack(alignment: .top, spacing: 12) {
                        ProductImage(path: c.images.first ?? "", kind: c.artKind, tone: c.artTone).frame(width: 84, height: 112).background(Theme.photo).clipShape(RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 6) {
                            Text(i == 0 ? "ЭТА ВЕЩЬ" : c.name.uppercased()).font(Theme.font(10, .medium)).kerning(0.8).foregroundStyle(Theme.muted)
                            Button { if i > 0 { router.push(.product(x.id)) } } label: { Text(x.name).font(Theme.font(14, .medium)).foregroundStyle(Theme.text).multilineTextAlignment(.leading) }
                            PriceView(price: shop.price(x), size: 13.5)
                            if i == 0 { Text(mainSize.map { "Размер \($0)" } ?? "Размер — выше, в карточке").font(Theme.font(12.5)).foregroundStyle(Theme.muted) }
                            else {
                                FlowRow(spacing: 6) {
                                    ForEach(avail, id: \.size) { z in
                                        let on = (sizes[x.id] ?? (avail.count == 1 ? avail[0].size : nil)) == z.size
                                        Button { sizes[x.id] = z.size } label: { Text(z.size).font(Theme.font(12.5)).foregroundStyle(on ? .white : Theme.text).padding(.horizontal, 10).frame(height: 30).background(Capsule().fill(on ? Theme.accent : Theme.surface)) }
                                    }
                                }
                                Button(off.contains(x.id) ? "Вернуть в образ" : "Убрать из образа") { if off.contains(x.id) { off.remove(x.id) } else { off.insert(x.id) } }.font(Theme.font(12.5)).foregroundStyle(Theme.muted)
                            }
                        }
                        Spacer(minLength: 0)
                    }.opacity(off.contains(x.id) ? 0.45 : 1)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(chosen.count > 1 ? "Образ из \(chosen.count) \(Fmt.plural(chosen.count, "вещи", "вещей", "вещей"))" : "Одна вещь").font(Theme.font(13)).foregroundStyle(Theme.muted)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if old > sum { Text(Fmt.rub(old)).font(Theme.font(14)).strikethrough().foregroundStyle(Theme.dim) }
                        Text(Fmt.rub(sum)).font(Theme.font(24, .light))
                    }
                    PrimaryButton(title: "Добавить образ в корзину", arrow: true) { addAll(all) }
                }.padding(18).softCard(20, fill: Theme.surface)
            }.padding(.horizontal, Theme.gutter)
        }
    }
    private func addAll(_ all: [Product]) {
        guard let ms = mainSize else { Toast.shared.show("Сначала выберите размер этой вещи"); Haptic.error(); return }
        var n = 0
        for (i, x) in all.enumerated() where !off.contains(x.id) {
            let c = i == 0 ? mainColor : (x.colors.first { $0.stock > 0 } ?? x.colors[0])
            let avail = c.sizes.filter { $0.stock > 0 }
            guard let s = i == 0 ? ms : (sizes[x.id] ?? (avail.count == 1 ? avail[0].size : nil)) else { Toast.shared.show("Выберите размер для «\(x.name)»"); Haptic.error(); return }
            shop.add(x, color: c.id, size: s); n += 1
        }
        Haptic.success(); Toast.shared.show("В корзине: \(n) \(Fmt.plural(n, "вещь", "вещи", "вещей"))")
    }
}
