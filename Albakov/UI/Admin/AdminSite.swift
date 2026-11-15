import SwiftUI
import PhotosUI

// Внешний вид сайта и доступ: слайдер на главной, логотип и название, сотрудники.
// Всё как в панели сайта (sliderSection, slideEditor, brandSection, staffSection в public/js/admin.js).

// MARK: - Слайдер на главной

private enum SlideKit {
    static let tpl: [(key: String, name: String, hint: String, slide: [String: Any])] = [
        ("sale", "Акция", "Связан с акцией: сам покажет скидку и срок и скроется, когда акция закончится",
         ["layout": "full", "eyebrow": "Акция", "title": "Название\n*акции*", "text": "Коротко о том, на что скидка.", "image": "img/slide-sale.jpg", "btn1": ["label": "Смотреть товары", "link": "#/sale"], "btn2": ["label": "Все акции", "link": "#/sale"]]),
        ("welcome", "Скидка на первый заказ", "С промокодом, который покупатель копирует одним нажатием",
         ["layout": "split", "eyebrow": "Для новых покупателей", "title": "−10%\nна *первый заказ*", "text": "Зарегистрируйтесь и введите промокод при оформлении.", "image": "img/slide-welcome.jpg", "code": "WELCOME10", "btn1": ["label": "Зарегистрироваться", "link": "#/account?tab=register"], "btn2": ["label": "", "link": ""]]),
        ("news", "Новинки", "Новая коллекция или поступление",
         ["layout": "split", "eyebrow": "Новое поступление", "title": "Новая\n*коллекция*", "text": "Пара строк о коллекции.", "image": "img/slide-new.jpg", "btn1": ["label": "Смотреть новинки", "link": "#/catalog?tag=new"], "btn2": ["label": "Весь каталог", "link": "#/catalog"]]),
        ("blank", "Пустой слайд", "Свой текст, фото и кнопки",
         ["layout": "split", "eyebrow": "", "title": "Заголовок", "text": "", "image": "", "btn1": ["label": "Подробнее", "link": "#/catalog"], "btn2": ["label": "", "link": ""]])
    ]
    @MainActor static func blank(_ key: String) -> [String: Any] {
        var s: [String: Any] = ["id": uid("sl"), "active": true, "layout": "split", "eyebrow": "", "title": "", "text": "", "image": "", "badge": "", "code": "", "promotionId": "",
                                "btn1": ["label": "", "link": ""], "btn2": ["label": "", "link": ""], "gender": "", "startsAt": "", "endsAt": ""]
        for (k, v) in (tpl.first { $0.key == key } ?? tpl[3]).slide { s[k] = v }
        let d = Admin.shared.data
        if key == "sale", let p = d["promotions"].array.first(where: { Promotion($0).inWindow(Date()) }) ?? d["promotions"].array.first {
            s["promotionId"] = p["id"].str; s["title"] = p["title"].str; if !p["description"].str.isEmpty { s["text"] = p["description"].str }
        }
        if key == "welcome" { s["code"] = d["promocodes"].array.first { $0["active"].bool }?["code"].str ?? "" }
        return s
    }
    static func clean(_ t: String) -> String { t.replacingOccurrences(of: "*", with: "").replacingOccurrences(of: "\n", with: " ") }
    @MainActor static func status(_ s: JSON) -> (String, Color) {
        let now = Date(), pid = s["promotionId"].str
        let pr = Admin.shared.data["promotions"].array.first { $0["id"].str == pid }
        if !s["active"].bool { return ("Скрыт", Theme.muted) }
        if let a = ISO.day(s["startsAt"].str), now < a { return ("Покажется с " + Fmt.date(a), Theme.warn) }
        if let b = ISO.day(s["endsAt"].str), now > b.addingTimeInterval(86_399) { return ("Период показа закончился", Theme.danger) }
        if !pid.isEmpty && (pr == nil || !Promotion(pr!).inWindow(now)) { return ("Акция не действует — слайд скрыт", Theme.danger) }
        return ("Показывается", Theme.ok)
    }
    @MainActor static func save(_ cfg: [String: Any], _ msg: String) async -> Bool {
        var s = Admin.shared.data["settings"].dictAny; s["slider"] = cfg
        do { try await AdminAPI.saveSettings(s); await AdminAPI.reload(); Toast.shared.show(msg); return true } catch { Toast.shared.show(error.userMessage); return false }
    }
}

extension ISO {
    /// «2026-03-01» → начало этого дня
    static func day(_ s: String) -> Date? {
        guard s.count >= 10 else { return nil }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f.date(from: String(s.prefix(10)))
    }
}

struct AdminSlider: View {
    @ObservedObject private var admin = Admin.shared
    @State private var pick = false
    @State private var del: Int?
    private var cfg: [String: Any] {
        var c: [String: Any] = ["enabled": true, "autoplay": true, "interval": 7, "slides": [Any]()]
        for (k, v) in admin.data["settings"]["slider"].dictAny { c[k] = v }
        return c
    }
    var body: some View {
        let c = JSON(cfg), sl = c["slides"].array
        List {
            Section {
                Text("Первый экран главной страницы. Слайды сменяют друг друга по порядку из списка. Изменения сохраняются сразу.").font(Theme.font(13)).foregroundStyle(Theme.muted)
                Toggle(isOn: Binding(get: { c["enabled"].bool }, set: { v in set("enabled", v, v ? "Слайдер включён" : "Слайдер выключен") })) {
                    VStack(alignment: .leading) { Text("Показывать слайдер на главной"); Text("Если выключить, на первом экране будет обычный блок из «Главной страницы»").font(Theme.font(12)).foregroundStyle(Theme.muted) }
                }.tint(Theme.ink)
                Toggle("Листать автоматически", isOn: Binding(get: { c["autoplay"].bool }, set: { v in set("autoplay", v, v ? "Автопрокрутка включена" : "Автопрокрутка выключена") })).tint(Theme.ink)
                Stepper("Смена слайда: \(c["interval"].int ?? 7) с", value: Binding(get: { c["interval"].int ?? 7 }, set: { v in set("interval", min(20, max(3, v)), "Слайды меняются каждые \(min(20, max(3, v))) с") }), in: 3...20)
            }
            Section {
                Button { pick = true } label: { Label("Добавить слайд", systemImage: "plus") }.font(Theme.font(15, .medium))
                if sl.isEmpty { Text("Слайдов нет. Добавьте первый слайд — например, о текущей акции.").font(Theme.font(13.5)).foregroundStyle(Theme.muted) }
                ForEach(sl.indices, id: \.self) { i in
                    let x = sl[i], st = SlideKit.status(x)
                    NavigationLink { SlideEdit(slide: x.dictAny, isNew: false) } label: {
                        HStack(spacing: 12) {
                            Text("\(i + 1)").font(Theme.font(12)).foregroundStyle(Theme.muted).frame(width: 16)
                            Group { if x["image"].str.isEmpty { ArtView(kind: "coat", tone: "#3d3d40") } else { RemoteImage(path: x["image"].str) } }
                                .frame(width: 64, height: 44).clipShape(RoundedRectangle(cornerRadius: 8)).opacity(x["active"].bool ? 1 : 0.45)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(SlideKit.clean(x["title"].str).isEmpty ? "Без заголовка" : SlideKit.clean(x["title"].str)).font(Theme.font(14.5, .medium)).lineLimit(2)
                                Text(pills(x)).font(Theme.font(11.5)).foregroundStyle(Theme.muted).lineLimit(2)
                                Text(st.0).font(Theme.font(11.5, .medium)).foregroundStyle(st.1)
                            }
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Удалить", role: .destructive) { del = i }
                        Button("Копия") { var s = slides(); var cp = s[i]; cp["id"] = uid("sl"); cp["active"] = false; s.insert(cp, at: i + 1); setSlides(s, "Копия создана — она скрыта, пока вы её не включите") }.tint(Theme.muted)
                    }
                    .swipeActions(edge: .leading) {
                        Button(x["active"].bool ? "Скрыть" : "Показать") { var s = slides(); let on = !x["active"].bool; s[i]["active"] = on; setSlides(s, on ? "Слайд показан" : "Слайд скрыт") }.tint(Theme.ink)
                    }
                }
                .onMove { from, to in var s = slides(); s.move(fromOffsets: from, toOffset: to); setSlides(s, "Порядок изменён") }
            } footer: { Text("Смахните влево — копия или удаление, вправо — скрыть или показать. Порядок — «Править».").font(Theme.font(12)) }
        }
        .font(Theme.font(15))
        .navigationTitle("Слайдер на главной").navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .task { if !admin.data.exists { await admin.load() } }
        .sheet(isPresented: $pick) {
            NavigationStack {
                List(SlideKit.tpl, id: \.key) { t in
                    NavigationLink { SlideEdit(slide: SlideKit.blank(t.key), isNew: true, done: { pick = false }).environmentObject(Shop.shared).environmentObject(Router.shared) } label: {
                        VStack(alignment: .leading, spacing: 3) { Text(t.name).font(Theme.font(15, .medium)); Text(t.hint).font(Theme.font(12.5)).foregroundStyle(Theme.muted) }
                    }
                }
                .navigationTitle("Какой слайд добавить?").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Отмена") { pick = false } } }
            }
        }
        .confirmationDialog("Удалить слайд?", isPresented: Binding(get: { del != nil }, set: { if !$0 { del = nil } }), titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { if let i = del { var s = slides(); s.remove(at: i); setSlides(s, "Слайд удалён") } }
        }
    }
    private func slides() -> [[String: Any]] { (cfg["slides"] as? [Any] ?? []).compactMap { $0 as? [String: Any] } }
    private func setSlides(_ s: [[String: Any]], _ msg: String) { var c = cfg; c["slides"] = s; Task { _ = await SlideKit.save(c, msg) } }
    private func set(_ k: String, _ v: Any, _ msg: String) { var c = cfg; c[k] = v; Task { _ = await SlideKit.save(c, msg) } }
    private func pills(_ x: JSON) -> String {
        var p: [String] = []
        if !x["gender"].str.isEmpty { p.append("Только «\(Sections.name(x["gender"].str))»") }
        switch Slide(x).who { case "guest": p.append("Только гостям"); case "new": p.append("Новым покупателям"); case "user": p.append("Только вошедшим"); default: break }
        if let pr = admin.data["promotions"].array.first(where: { $0["id"].str == x["promotionId"].str }) { p.append("Акция: " + pr["title"].str) }
        if !x["code"].str.isEmpty { p.append("Промокод " + x["code"].str) }
        return p.joined(separator: " · ")
    }
}

/// Карточка слайда: поля как на сайте и живой предпросмотр того, как слайд выглядит в приложении
private struct SlideEdit: View {
    let slide: [String: Any]
    let isNew: Bool
    var done: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var admin = Admin.shared
    @StateObject private var doc = Doc([:])
    @State private var loaded = false
    @State private var busy = false
    @State private var error: String?
    @State private var askDel = false
    private var defs: [FDef] {
        let d = admin.data
        let promo = [("", "Не связан с акцией")] + d["promotions"].array.map { ($0["id"].str, $0["title"].str + (Promotion($0).inWindow(Date()) ? " — действует" : " — не действует")) }
        let codes = [("", "Без промокода")] + d["promocodes"].array.map { ($0["code"].str, $0["code"].str + ($0["active"].bool ? "" : " (выключен)") + ($0["note"].str.isEmpty ? "" : " — " + $0["note"].str)) }
        return [.section("Основное"), FDef(k: "active", label: "Показывать слайд на сайте", kind: .bool),
                FDef(k: "audience", label: "Кому показывать", kind: .select([("", "Сам решит: со ссылкой на регистрацию — новым покупателям, пока не воспользовались скидкой"), ("all", "Всем"), ("guest", "Только тем, кто не вошёл"), ("user", "Только вошедшим в личный кабинет")])),
                FDef(k: "gender", label: "Для какого раздела", kind: .select([("", "Всем покупателям")] + Sections.all.map { ($0.key, "Только «\($0.name)»") })),
                .section("Текст"), FDef(k: "eyebrow", label: "Надзаголовок", hint: "Маленькая строка над заголовком"),
                FDef(k: "title", label: "Заголовок", kind: .area(2), hint: "Новая строка — перенос. *Слово в звёздочках* — курсивом."),
                FDef(k: "text", label: "Текст", kind: .area(3)),
                FDef(k: "badge", label: "Крупная надпись над заголовком", hint: "Например, −15%. Если слайд связан с акцией, а поле пустое — подставится размер скидки."),
                FDef(k: "image", label: "Фото", kind: .image, hint: "Горизонтальное фото от 1600×1000 пикселей. В макете «на весь экран» главное держите в правой части кадра."),
                .section("Предложение"), FDef(k: "promotionId", label: "Связать с акцией", kind: .select(promo), hint: "Слайд покажет срок и размер скидки и сам скроется, когда акция закончится."),
                FDef(k: "code", label: "Промокод на слайде", kind: .select(codes), hint: "Покупатель копирует его одним нажатием."),
                .section("Кнопки"), FDef(k: "b1l", label: "Главная кнопка — текст", hint: "Пусто — кнопки нет"), FDef(k: "b1h", label: "Главная кнопка — ссылка", kind: .select(links(doc.str("b1h")))),
                FDef(k: "b2l", label: "Вторая кнопка — текст", hint: "Пусто — кнопки нет"), FDef(k: "b2h", label: "Вторая кнопка — ссылка", kind: .select(links(doc.str("b2h")))),
                .section("Когда показывать"), FDef(k: "startsAt", label: "Показывать с", kind: .date, hint: "Пусто — сразу"), FDef(k: "endsAt", label: "Показывать по", kind: .date, hint: "Пусто — без срока")]
    }
    /// Куда ведёт кнопка: разделы сайта, категории, страницы (и уже стоящая ссылка, если она своя)
    private func links(_ cur: String) -> [(String, String)] {
        var l = [("", "Нет кнопки"), ("#/catalog", "Каталог"), ("#/catalog?tag=new", "Новинки"), ("#/sale", "Акции"), ("#/account?tab=register", "Регистрация"), ("#/sizes", "Таблица размеров")]
            + admin.data["categories"].array.map { ("#/catalog?cat=" + $0["slug"].str, "Категория: " + $0["name"].str) }
            + admin.data["pages"].array.map { ("#/page/" + $0["slug"].str, "Страница: " + $0["title"].str) }
        if !cur.isEmpty && !l.contains(where: { $0.0 == cur }) { l.append((cur, cur)) }
        return l
    }
    private var current: [String: Any] {
        var x = slide
        for k in ["active", "audience", "gender", "eyebrow", "title", "text", "badge", "image", "promotionId", "code", "startsAt", "endsAt"] { x[k] = doc.v[k] ?? "" }
        x["active"] = doc.bool("active")
        x["btn1"] = ["label": doc.str("b1l"), "link": doc.str("b1h")]; x["btn2"] = ["label": doc.str("b2l"), "link": doc.str("b2h")]
        return x
    }
    var body: some View {
        AdminPage(title: isNew ? "Новый слайд" : (SlideKit.clean(slide["title"] as? String ?? "").isEmpty ? "Слайд" : SlideKit.clean(slide["title"] as? String ?? "")), busy: busy, error: error, onSave: { Task { await save() } }) {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: "Предпросмотр")
                HeroSlider(slides: [Slide(JSON(current))], preview: true).allowsHitTesting(false).padding(.horizontal, -Theme.gutter)
                Text("На сайте и в приложении изменения появятся после «Сохранить».").font(Theme.font(12.5)).foregroundStyle(Theme.muted)
            }
            DefForm(defs: defs, doc: doc).padding(16).softCard(20)
            if !isNew { GhostButton(title: "Удалить слайд", icon: "trash") { askDel = true } }
        }
        .onAppear {
            guard !loaded else { return }
            var f = slide
            let b1 = slide["btn1"] as? [String: Any] ?? [:], b2 = slide["btn2"] as? [String: Any] ?? [:]
            f["b1l"] = b1["label"] ?? ""; f["b1h"] = b1["link"] ?? ""; f["b2l"] = b2["label"] ?? ""; f["b2h"] = b2["link"] ?? ""
            doc.v = f; loaded = true
        }
        .confirmationDialog("Удалить слайд?", isPresented: $askDel, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { Task { await write(remove: true) } }
        }
    }
    private func save() async {
        error = nil
        let x = JSON(current)
        if x["title"].str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { error = "Напишите заголовок"; return }
        if !x["btn1"]["label"].str.isEmpty && x["btn1"]["link"].str.isEmpty { error = "Укажите ссылку для главной кнопки"; return }
        if !x["btn2"]["label"].str.isEmpty && x["btn2"]["link"].str.isEmpty { error = "Укажите ссылку для второй кнопки"; return }
        await write(remove: false)
    }
    private func write(remove: Bool) async {
        busy = true; defer { busy = false }
        var c: [String: Any] = ["enabled": true, "autoplay": true, "interval": 7]
        for (k, v) in admin.data["settings"]["slider"].dictAny { c[k] = v }
        var s = (c["slides"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
        let id = slide["id"] as? String ?? ""
        if remove { s.removeAll { ($0["id"] as? String) == id } }
        else if let i = s.firstIndex(where: { ($0["id"] as? String) == id }) { s[i] = current } else { s.append(current) }
        c["slides"] = s
        if await SlideKit.save(c, remove ? "Слайд удалён" : isNew ? "Слайд добавлен" : "Слайд сохранён") { done?(); dismiss() }
    }
}

// MARK: - Логотип и название

struct AdminBrand: View {
    @ObservedObject private var admin = Admin.shared
    @State private var s: [String: Any] = [:]
    @State private var b: [String: Any] = [:]
    @State private var loaded = false
    @State private var removeBg = true
    @State private var recolor = true
    @State private var busy = false
    @State private var error: String?
    private static let modes = [("both", "Знак и надпись"), ("word", "Только надпись"), ("mark", "Только знак"), ("text", "Название текстом")]
    var body: some View {
        AdminPage(title: "Логотип и название", sub: "Надпись стоит в шапке, в меню на телефоне, в подвале и в письмах покупателям. Знак — водяным знаком в подвале.", busy: busy, error: error, onSave: { Task { await save() } }) {
            VStack(alignment: .leading, spacing: 16) {
                LogoSlot(title: "Знак", hint: "Иконка или монограмма, примерно квадратная", src: src("mark"), removeBg: removeBg, recolor: recolor) { b["mark"] = $0.map { $0 as Any } ?? NSNull() }
                LogoSlot(title: "Надпись", hint: "Название бренда в фирменном начертании, вытянутое по горизонтали", src: src("word"), removeBg: removeBg, recolor: recolor) { b["word"] = $0.map { $0 as Any } ?? NSNull() }
                Eyebrow(text: "При загрузке")
                Toggle("Убрать однотонный фон (белый, чёрный и т. п.)", isOn: $removeBg).tint(Theme.ink)
                Toggle("Перекрасить в светлый цвет сайта — чтобы логотип был виден на тёмном фоне", isOn: $recolor).tint(Theme.ink)
            }.font(Theme.font(14)).padding(16).softCard(20)
            VStack(alignment: .leading, spacing: 14) {
                Field(label: "Название магазина", text: Binding(get: { s["storeName"] as? String ?? "" }, set: { s["storeName"] = $0 }))
                Text("Используется в заголовке вкладки, в письмах и там, где выбрано «Название текстом»").font(Theme.font(12)).foregroundStyle(Theme.muted)
                VStack(alignment: .leading) {
                    Text("Размер логотипа: \(scale)%").font(Theme.font(14)).foregroundStyle(Theme.muted)
                    Slider(value: Binding(get: { Double(scale) }, set: { b["scale"] = Int($0) }), in: 70...150, step: 5).tint(Theme.ink)
                }
                modePicker("desktop", "На компьютере показывать")
                modePicker("mobile", "На телефоне показывать")
                Toggle("Знак ® рядом с логотипом и пометка «зарегистрированный товарный знак» в подвале", isOn: flag("trademark")).tint(Theme.ink)
                Toggle("Водяной знак в подвале сайта — крупно и едва заметно, справа. Работает, если загружен знак.", isOn: flag("footerMark")).tint(Theme.ink)
            }.font(Theme.font(14)).padding(16).softCard(20)
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "Так выглядит шапка на телефоне")
                HStack { Image(systemName: "line.3.horizontal"); Spacer(); preview("mobile"); Spacer(); Image(systemName: "bag") }
                    .padding(.horizontal, 16).frame(height: 56).background(RoundedRectangle(cornerRadius: 14).fill(.white)).hairline(RoundedRectangle(cornerRadius: 14), 0.09)
                ForEach(warnings, id: \.self) { Text($0).font(Theme.font(12.5)).foregroundStyle(Theme.warn) }
            }
        }
        .task {
            if !admin.data.exists { await admin.load() }
            guard !loaded else { return }
            s = admin.data["settings"].dictAny
            b = ["desktop": "word", "mobile": "word", "scale": 100]
            for (k, v) in admin.data["settings"]["brand"].dictAny { b[k] = v }
            loaded = true
        }
    }
    private var scale: Int { JSON(b["scale"]).int ?? 100 }
    private func src(_ k: String) -> String { JSON(b[k])["src"].str }
    private func flag(_ k: String) -> Binding<Bool> { Binding(get: { !(b[k] is Bool) || (b[k] as? Bool) == true }, set: { b[k] = $0 }) }
    /// Что реально покажется, если нужной картинки нет (brandMode на сайте)
    private func mode(_ w: String) -> String {
        let want = b[w] as? String ?? "word", m = !src("mark").isEmpty, wd = !src("word").isEmpty
        switch want {
        case "both": return m && wd ? "both" : wd ? "word" : m ? "mark" : "text"
        case "word": return wd ? "word" : m ? "mark" : "text"
        case "mark": return m ? "mark" : wd ? "word" : "text"
        default: return "text"
        }
    }
    private var warnings: [String] {
        ["desktop", "mobile"].compactMap { w in
            let want = b[w] as? String ?? "word", got = mode(w)
            guard want != got else { return nil }
            let n = { (k: String) in AdminBrand.modes.first { $0.0 == k }?.1 ?? k }
            return (w == "desktop" ? "На компьютере" : "На телефоне") + " выбрано «\(n(want))», но нужного изображения нет — показано «\(n(got))»"
        }
    }
    @ViewBuilder private func preview(_ w: String) -> some View {
        let k = CGFloat(scale) / 100, m = mode(w)
        HStack(spacing: 6) {
            if m == "mark" || m == "both" { RemoteImage(path: src("mark"), contentMode: .fit).frame(height: 26 * k).colorInvert() }
            if m == "word" || m == "both" { RemoteImage(path: src("word"), contentMode: .fit).frame(width: 130 * k, height: 22 * k).colorInvert() }
            if m == "text" { Text(s["storeName"] as? String ?? "").font(Theme.font(18 * k, .semibold)).foregroundStyle(Theme.ink) }
        }
    }
    private func modePicker(_ k: String, _ title: String) -> some View {
        Picker(title, selection: Binding(get: { b[k] as? String ?? "word" }, set: { b[k] = $0 })) { ForEach(AdminBrand.modes, id: \.0) { Text($0.1).tag($0.0) } }
            .pickerStyle(.menu).tint(Theme.ink)
    }
    private func save() async {
        error = nil
        if (s["storeName"] as? String ?? "").trimmingCharacters(in: .whitespaces).isEmpty { error = "Укажите название магазина"; return }
        busy = true; defer { busy = false }
        var x = admin.data["settings"].dictAny; x["storeName"] = s["storeName"]; x["brand"] = b
        do { try await AdminAPI.saveSettings(x); await AdminAPI.reload(); Haptic.success(); Toast.shared.show("Логотип сохранён") } catch { self.error = error.userMessage }
    }
}

/// Место для знака или надписи: загрузка из галереи с обработкой (убрать фон, перекрасить, обрезать поля)
private struct LogoSlot: View {
    let title: String, hint: String, src: String
    let removeBg: Bool, recolor: Bool
    let set: ([String: Any]?) -> Void
    @State private var item: PhotosPickerItem?
    @State private var busy = false
    var body: some View {
        HStack(spacing: 12) {
            Group { if src.isEmpty { Text("Не загружен").font(Theme.font(11)).foregroundStyle(.white.opacity(0.6)) } else { RemoteImage(path: src, contentMode: .fit).padding(8) } }
                .frame(width: 84, height: 64).background(RoundedRectangle(cornerRadius: 12).fill(Theme.dark))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Theme.font(15, .medium)); Text(hint).font(Theme.font(12)).foregroundStyle(Theme.muted)
                HStack(spacing: 14) {
                    PhotosPicker(selection: $item, matching: .images) { Text(busy ? "Загружаю…" : "Загрузить").font(Theme.font(13.5, .medium)).foregroundStyle(Theme.ink) }
                    if !src.isEmpty { Button("Убрать") { set(nil) }.font(Theme.font(13.5)).foregroundStyle(Theme.danger) }
                }
            }
        }
        .onChange(of: item) { it in Task { await upload(it) } }
    }
    private func upload(_ it: PhotosPickerItem?) async {
        guard let it, let data = try? await it.loadTransferable(type: Data.self) else { return }
        busy = true; defer { busy = false; item = nil }
        do {
            let r = try LogoKit.process(data, removeBg: removeBg, recolor: recolor)
            let url = try await API.shared.upload(r.png, mime: "image/png")
            set(["src": url, "w": r.w, "h": r.h])
            if let n = r.note { Toast.shared.show(n) }
        } catch { Toast.shared.show(error.userMessage) }
    }
}

/// Обработка логотипа как processLogo на сайте: однотонный фон → прозрачный, цвет → светлый #ece6dc, обрезка пустых полей
enum LogoKit {
    struct Fail: LocalizedError { let errorDescription: String? }
    static func process(_ data: Data, removeBg: Bool, recolor: Bool) throws -> (png: Data, w: Int, h: Int, note: String?) {
        guard let img = UIImage(data: data)?.cgImage else { throw Fail(errorDescription: "Файл не похож на изображение. Подойдут PNG, JPG или WebP.") }
        let k = min(1, 2400 / CGFloat(max(img.width, img.height)))
        let W = max(1, Int((CGFloat(img.width) * k).rounded())), H = max(1, Int((CGFloat(img.height) * k).rounded()))
        let cs = CGColorSpaceCreateDeviceRGB(), info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4, space: cs, bitmapInfo: info), let raw = ctx.data else { throw Fail(errorDescription: "Не удалось обработать картинку") }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: W, height: H))
        let px = raw.bindMemory(to: UInt8.self, capacity: W * H * 4), count = W * H * 4
        // без предумножения, как в canvas
        for i in stride(from: 0, to: count, by: 4) where px[i + 3] > 0 && px[i + 3] < 255 {
            let a = Double(px[i + 3]) / 255; for c in 0..<3 { px[i + c] = UInt8(min(255, Double(px[i + c]) / a)) }
        }
        func corner(_ x: Int, _ y: Int) -> [Double] { let i = (y * W + x) * 4; return (0..<4).map { Double(px[i + $0]) } }
        let cr = [corner(0, 0), corner(W - 1, 0), corner(0, H - 1), corner(W - 1, H - 1)]
        let bg = (0..<4).map { j in cr.reduce(0) { $0 + $1[j] } / 4 }
        let uniform = cr.allSatisfy { abs($0[0] - bg[0]) + abs($0[1] - bg[1]) + abs($0[2] - bg[2]) < 40 && $0[3] > 200 }
        var note: String?
        if removeBg && uniform {
            for i in stride(from: 0, to: count, by: 4) {
                let d = (0..<3).map { abs(Double(px[i + $0]) - bg[$0]) }.max() ?? 0
                let a = min(1, max(0, (d - 10) / 60))
                if a > 0 && a < 1 { for c in 0..<3 { px[i + c] = UInt8(max(0, min(255, bg[c] + (Double(px[i + c]) - bg[c]) / a))) } }
                px[i + 3] = UInt8((a * Double(px[i + 3])).rounded())
            }
            note = "Фон убран"
        } else if removeBg && cr.contains(where: { $0[3] > 200 }) { note = "Фон неоднородный — убрать его автоматически не получилось. Лучше загрузить PNG с прозрачным фоном." }
        if recolor { for i in stride(from: 0, to: count, by: 4) { px[i] = 0xec; px[i + 1] = 0xe6; px[i + 2] = 0xdc } }
        var x0 = W, y0 = H, x1 = -1, y1 = -1
        for y in 0..<H { for x in 0..<W where px[(y * W + x) * 4 + 3] > 8 { x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y) } }
        if x1 < 0 { throw Fail(errorDescription: "После удаления фона ничего не осталось. Попробуйте без «Убрать фон».") }
        // обратно в предумноженный вид для CGImage
        for i in stride(from: 0, to: count, by: 4) where px[i + 3] < 255 { let a = Double(px[i + 3]) / 255; for c in 0..<3 { px[i + c] = UInt8(Double(px[i + c]) * a) } }
        guard let full = ctx.makeImage(),
              let crop = full.cropping(to: CGRect(x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1)) else { throw Fail(errorDescription: "Не удалось обработать картинку") }
        let s2 = min(1, 1000 / CGFloat(crop.width), 300 / CGFloat(crop.height))
        let size = CGSize(width: max(1, (CGFloat(crop.width) * s2).rounded()), height: max(1, (CGFloat(crop.height) * s2).rounded()))
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1; fmt.opaque = false
        let out = UIGraphicsImageRenderer(size: size, format: fmt).image { _ in UIImage(cgImage: crop).draw(in: CGRect(origin: .zero, size: size)) }
        guard let png = out.pngData() else { throw Fail(errorDescription: "Не удалось обработать картинку") }
        return (png, Int(size.width), Int(size.height), note)
    }
}

// MARK: - Сотрудники

struct AdminStaff: View {
    private static let roles: [(String, String, String)] = [
        ("manager", "Управляющий", "Всё, кроме сотрудников, оплаты, ключей и общих настроек"),
        ("orders", "Менеджер заказов", "Заказы, отправки СДЭК, обмены и возвраты, поддержка, покупатели, сертификаты, почта"),
        ("content", "Контент-менеджер", "Товары, категории, размеры, акции, промокоды, слайдер, главная, страницы, меню"),
        ("finance", "Финансы", "Финансы и аналитика")
    ]
    @State private var list: [JSON] = []
    @State private var phone = ""
    @State private var role = "orders"
    @State private var error: String?
    @State private var busy = false
    @State private var del: JSON?
    var body: some View {
        List {
            Section {
                Text("Сотрудник входит в панель своим аккаунтом — отдельных паролей нет. Выдайте роль по номеру телефона: человек должен быть уже зарегистрирован. Забрать доступ можно в любой момент.").font(Theme.font(13)).foregroundStyle(Theme.muted)
            }
            Section("Выдать доступ") {
                TextField("+7 (900) 000-00-00", text: $phone).keyboardType(.phonePad)
                Picker("Роль", selection: $role) { ForEach(AdminStaff.roles, id: \.0) { Text($0.1).tag($0.0) } }.tint(Theme.ink)
                if let error { Text(error).font(Theme.font(13)).foregroundStyle(Theme.danger) }
                Button(busy ? "Выдаю…" : "Выдать") { Task { await add() } }.font(Theme.font(15, .medium)).disabled(busy)
            }
            Section("Доступ к панели") {
                ForEach(list.indices, id: \.self) { i in
                    let x = list[i]
                    HStack(spacing: 12) {
                        Text(initials(x["name"].str)).font(Theme.font(13, .medium)).foregroundStyle(.white).frame(width: 38, height: 38).background(Circle().fill(Theme.accent))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(x["name"].str.isEmpty ? "Без имени" : x["name"].str).font(Theme.font(15, .medium))
                            Text(Fmt.phone(x["phone"].str) + (x["email"].str.isEmpty ? "" : " · " + x["email"].str)).font(Theme.font(12)).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        if x["owner"].bool { Badge(text: "Владелец", color: "#121417") }
                        else {
                            Menu {
                                ForEach(AdminStaff.roles, id: \.0) { r in Button { Task { await change(x["userId"].str, r.0, r.1) } } label: { if r.0 == x["role"].str { Label(r.1, systemImage: "checkmark") } else { Text(r.1) } } }
                                Divider()
                                Button("Забрать доступ", role: .destructive) { del = x }
                            } label: { HStack(spacing: 4) { Text(x["roleName"].str).font(Theme.font(13)); Image(systemName: "chevron.down").font(.system(size: 10)) }.foregroundStyle(Theme.ink) }
                        }
                    }
                }
            }
            Section("Что может каждая роль") {
                row("Владелец", "Всё, включая сотрудников, оплату, ключи и общие настройки")
                ForEach(AdminStaff.roles, id: \.0) { row($0.1, $0.2) }
            }
        }
        .font(Theme.font(15))
        .navigationTitle("Сотрудники").navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog("Забрать доступ к панели?", isPresented: Binding(get: { del != nil }, set: { if !$0 { del = nil } }), titleVisibility: .visible) {
            Button("Забрать доступ", role: .destructive) { if let x = del { Task { do { _ = try await API.shared.raw("DELETE", "admin/staff/" + x["userId"].str); Toast.shared.show("Доступ забран"); await load() } catch { Toast.shared.show(error.userMessage) } } } }
        }
    }
    private func row(_ t: String, _ s: String) -> some View { VStack(alignment: .leading, spacing: 2) { Text(t).font(Theme.font(14.5, .medium)); Text(s).font(Theme.font(12.5)).foregroundStyle(Theme.muted) } }
    private func initials(_ n: String) -> String { String((n.isEmpty ? "?" : n).split(separator: " ").compactMap(\.first).prefix(2)).uppercased() }
    private func load() async {
        do { list = try await API.shared.json("GET", "admin/staff")["staff"].array; error = nil } catch { self.error = error.userMessage }
    }
    private func add() async {
        error = nil
        let ph = phone.filter(\.isNumber)
        if ph.count < 10 { error = "Укажите номер телефона полностью"; return }
        busy = true; defer { busy = false }
        do {
            list = try await API.shared.json("POST", "admin/staff", body: ["phone": ph, "role": role])["staff"].array
            phone = ""; Toast.shared.show("Доступ выдан — человек увидит «Панель управления» в меню, когда войдёт в аккаунт")
        } catch { self.error = error.userMessage }
    }
    private func change(_ id: String, _ r: String, _ name: String) async {
        do { list = try await API.shared.json("PUT", "admin/staff/" + id, body: ["role": r])["staff"].array; Toast.shared.show("Роль изменена: " + name) } catch { Toast.shared.show(error.userMessage) }
    }
}
