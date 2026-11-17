import SwiftUI
import PhotosUI

// Основа родной панели: поля форм по описанию (как fieldHtml/formHtml в public/js/admin.js),
// списки и карточки коллекций (категории, сетки, акции, промокоды, страницы, товары), формы настроек.
// Всё сохраняется теми же запросами, что и панель сайта: PUT admin/<коллекция>/<id>, DELETE …, PUT admin/settings.

// MARK: - Описание поля

enum FKind {
    case text, area(Int), number, bool, date, image, color, section
    case select([(String, String)])
    case multi([(String, String)])
    case rows([FDef])
    case parcel                 // вес и размер посылки СДЭК (weight, box)
    case look(Int)              // «С этим носят»: товары с фото, не больше N
}

struct FDef {
    let k: String
    let label: String
    var kind: FKind = .text
    var hint = ""
    static func section(_ t: String) -> FDef { FDef(k: "", label: t, kind: .section) }
}

// MARK: - Изменяемый документ: словарь JSON с доступом по ключу

final class Doc: ObservableObject {
    @Published var v: [String: Any]
    init(_ v: [String: Any]) { self.v = v }
    func str(_ k: String) -> String { (v[k] as? String) ?? (v[k] as? NSNumber).map { $0.stringValue } ?? "" }
    func num(_ k: String) -> Double { (v[k] as? NSNumber)?.doubleValue ?? Double(str(k).replacingOccurrences(of: ",", with: ".")) ?? 0 }
    func bool(_ k: String) -> Bool { (v[k] as? Bool) ?? (v[k] as? NSNumber)?.boolValue ?? false }
    func arr(_ k: String) -> [Any] { v[k] as? [Any] ?? [] }
    func set(_ k: String, _ x: Any?) { if let x { v[k] = x } else { v.removeValue(forKey: k) } }
    func text(_ k: String) -> Binding<String> { Binding(get: { self.str(k) }, set: { self.v[k] = $0 }) }
    func flag(_ k: String) -> Binding<Bool> { Binding(get: { self.bool(k) }, set: { self.v[k] = $0 }) }
    /// Число: целое хранится целым, дробное — дробным (как Number(input.value) на сайте)
    func number(_ k: String) -> Binding<String> {
        Binding(get: { let s = self.str(k); return s == "0" && self.v[k] == nil ? "" : s },
                set: { t in let n = Double(t.replacingOccurrences(of: ",", with: ".")) ?? 0; self.v[k] = n == n.rounded() ? NSNumber(value: Int(n)) : NSNumber(value: n) })
    }
}

extension JSON {
    var dictAny: [String: Any] { (raw as? [String: Any]) ?? [:] }
    var arrAny: [Any] { (raw as? [Any]) ?? [] }
}

func uid(_ prefix: String) -> String { prefix + String(Int(Date().timeIntervalSince1970 * 1000), radix: 36) + String(Int.random(in: 0..<60_466_176), radix: 36) }

/// Адрес латиницей из названия (как translit на сайте)
func translit(_ s: String) -> String {
    let m: [Character: String] = ["а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "e", "ж": "zh", "з": "z", "и": "i", "й": "j", "к": "k", "л": "l", "м": "m", "н": "n", "о": "o", "п": "p", "р": "r", "с": "s", "т": "t", "у": "u", "ф": "f", "х": "h", "ц": "c", "ч": "ch", "ш": "sh", "щ": "sch", "ъ": "", "ы": "y", "ь": "", "э": "e", "ю": "yu", "я": "ya"]
    let t = s.lowercased().map { m[$0] ?? String($0) }.joined()
    return t.replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
}

// MARK: - Запросы панели

enum AdminAPI {
    static func upsert(_ col: String, _ item: [String: Any]) async throws -> JSON {
        try await API.shared.json("PUT", "admin/\(col)/\(item["id"] as? String ?? "")", body: ["value": item])
    }
    static func delete(_ col: String, _ id: String) async throws { _ = try await API.shared.raw("DELETE", "admin/\(col)/\(id)") }
    static func saveSettings(_ s: [String: Any]) async throws { _ = try await API.shared.raw("PUT", "admin/settings", body: ["value": s]) }
    static func post(_ path: String, _ body: [String: Any] = [:]) async throws -> JSON { try await API.shared.json("POST", "admin/" + path, body: body) }
    /// После сохранения: свежие данные панели и витрины
    @MainActor static func reload() async { await Admin.shared.load(); await Shop.shared.refreshUser() }
}

/// «Сохранено» + «N покупателям ушло письмо о поступлении»
func notifyMsg(_ base: String, _ n: JSON) -> String {
    let c = n["sent"].int ?? 0
    return c > 0 ? base + " · \(c) \(Fmt.plural(c, "покупателю", "покупателям", "покупателям")) ушло письмо о поступлении" : base
}

/// Вкладки-пилюли как на сайте (.tabs): листаются вбок, названия не обрезаются
struct PillTabs: View {
    let items: [(String, String)]
    @Binding var value: String
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) { ForEach(items, id: \.0) { it in Chip(title: it.1, on: value == it.0, height: 36) { withAnimation(.easeOut(duration: 0.2)) { value = it.0 } } } }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 0))
    }
}

// MARK: - Форма по описанию

struct DefForm: View {
    let defs: [FDef]
    @ObservedObject var doc: Doc
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(defs.enumerated()), id: \.offset) { _, d in FieldView(d: d, doc: doc) }
        }
    }
}

struct FieldView: View {
    let d: FDef
    @ObservedObject var doc: Doc
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch d.kind {
            case .section:
                Text(d.label).font(Theme.font(20, .light)).padding(.top, 14)
            case .text:
                Field(label: d.label, text: doc.text(d.k))
            case .area(let n):
                AreaField(label: d.label, text: doc.text(d.k), lines: max(2, n)...max(4, n + 6))
            case .number:
                Field(label: d.label, text: doc.number(d.k), keyboard: .decimalPad)
            case .bool:
                Toggle(isOn: doc.flag(d.k)) { Text(d.label).font(Theme.font(15)) }.tint(Theme.ink)
            case .select(let opts):
                VStack(alignment: .leading, spacing: 6) {
                    Text(d.label).font(Theme.font(14)).foregroundStyle(Theme.muted)
                    Menu {
                        Picker(d.label, selection: doc.text(d.k)) { ForEach(opts, id: \.0) { Text($0.1).tag($0.0) } }
                    } label: {
                        HStack { Text(opts.first { $0.0 == doc.str(d.k) }?.1 ?? "Выберите").font(Theme.font(15.5)).foregroundStyle(Theme.text).lineLimit(1); Spacer(); Image(systemName: "chevron.up.chevron.down").font(.system(size: 11)).foregroundStyle(Theme.muted) }
                            .padding(.horizontal, 16).frame(height: 50).background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
                    }
                }
            case .multi(let opts):
                MultiPick(label: d.label, options: opts, selected: Binding(get: { doc.arr(d.k).compactMap { $0 as? String } }, set: { doc.v[d.k] = $0 }))
            case .date:
                DateField(label: d.label, value: doc.text(d.k))
            case .image:
                ImageField(label: d.label, value: doc.text(d.k))
            case .color:
                ColorField(label: d.label, hex: doc.text(d.k))
            case .parcel:
                ParcelField(doc: doc)
            case .look(let max):
                LookPick(label: d.label, max: max, selfId: doc.str("id"), selected: Binding(get: { doc.arr(d.k).compactMap { $0 as? String } }, set: { doc.v[d.k] = $0 }))
            case .rows(let cols):
                RowsEditor(label: d.label, cols: cols, rows: Binding(get: { (doc.v[d.k] as? [[String: Any]]) ?? [] }, set: { doc.v[d.k] = $0 }))
            }
            if !d.hint.isEmpty { Text(d.hint).font(Theme.font(12.5)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

/// Посылка для СДЭК: вес и размер одной вещи в упаковке (как parcelField в public/js/admin.js).
/// Уходят в цену доставки и в отправление СДЭК; несколько вещей складываются стопкой.
struct ParcelField: View {
    @ObservedObject var doc: Doc
    @ObservedObject private var admin = Admin.shared
    @State private var l = ""
    @State private var w = ""
    @State private var h = ""
    @State private var wt = ""
    @State private var ready = false
    init(doc: Doc) { self.doc = doc }
    private var cdek: JSON { admin.data["settings"]["cdek"] }
    private var packs: [JSON] {
        let p = cdek["packs"].array
        let defaults: [[String: Any]] = [["id": "bag", "name": "Пакет", "length": 30, "width": 25, "height": 5],
                                         ["id": "m", "name": "Коробка M", "length": 40, "width": 30, "height": 10],
                                         ["id": "l", "name": "Коробка L", "length": 50, "width": 40, "height": 20]]
        let list: [JSON] = p.isEmpty ? defaults.map { JSON($0) } : p
        return list.sorted { ParcelField.vol($0) < ParcelField.vol($1) }
    }
    private static func vol(_ x: JSON) -> Int {
        let a: Int = x["length"].int ?? 0, b: Int = x["width"].int ?? 0, c: Int = x["height"].int ?? 0
        return a * b * c
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Посылка для СДЭК").font(Theme.font(14)).foregroundStyle(Theme.muted)
            HStack(alignment: .bottom, spacing: 6) {
                cell("Вес", $wt, "г").frame(width: 84)
                Spacer(minLength: 4)
                cell("Длина", $l, "см"); Text("×").foregroundStyle(Theme.muted).padding(.bottom, 16)
                cell("Ширина", $w, "см"); Text("×").foregroundStyle(Theme.muted).padding(.bottom, 16)
                cell("Высота", $h, "см")
            }
            (Text("В СДЭК уйдёт: ").font(Theme.font(13.5, .medium)) + Text(summary).font(Theme.font(13.5)))
                .foregroundStyle(Theme.text).padding(.horizontal, 14).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
            Text("Вес и размер одной вещи в упаковке — как вы её отправляете. Уйдут в расчёт цены доставки и в отправление СДЭК. Несколько вещей в заказе сложатся стопкой.")
                .font(Theme.font(12.5)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
        }
        .onAppear(perform: load)
        .onChange(of: [l, w, h, wt]) { _ in store() }
    }
    private func cell(_ title: String, _ v: Binding<String>, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Theme.font(11.5)).foregroundStyle(Theme.muted)
            HStack(spacing: 2) {
                TextField("", text: v).keyboardType(.numberPad).font(Theme.font(15.5)).multilineTextAlignment(.leading)
                Text(unit).font(Theme.font(12)).foregroundStyle(Theme.dim)
            }.padding(.horizontal, 10).frame(height: 46).background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
        }
    }
    private var summary: String {
        let L = Int(l) ?? 0, W = Int(w) ?? 0, H = Int(h) ?? 0, G = Int(wt) ?? 0
        let list = packs
        let defId = cdek["defaultPack"].str
        let def: JSON = list.first(where: { $0["id"].str == defId }) ?? list.first ?? JSON(nil)
        var dims = ""
        if L > 0 && W > 0 && H > 0 {
            dims = "\(L)×\(W)×\(H) см"
        } else {
            let dl: Int = def["length"].int ?? 30, dw: Int = def["width"].int ?? 25, dh: Int = def["height"].int ?? 5
            dims = "упаковка по умолчанию «" + def["name"].str + "» \(dl)×\(dw)×\(dh) см"
        }
        let defW: Int = cdek["pkg"]["weight"].int ?? 1000
        let weight = G > 0 ? "\(G) г" : "вес по умолчанию \(defW) г"
        return dims + ", " + weight
    }
    private func load() {
        guard !ready else { return }
        let b = JSON(doc.v["box"])
        var L = b["length"].int ?? 0, W = b["width"].int ?? 0, H = b["height"].int ?? 0
        if !(L > 0 && W > 0 && H > 0), let pk = packs.first(where: { $0["id"].str == doc.str("pack") && !doc.str("pack").isEmpty }) {
            L = pk["length"].int ?? 0; W = pk["width"].int ?? 0; H = pk["height"].int ?? 0
        }
        l = L > 0 ? "\(L)" : ""; w = W > 0 ? "\(W)" : ""; h = H > 0 ? "\(H)" : ""
        let g = Int(doc.num("weight")); wt = g > 0 ? "\(g)" : ""
        ready = true
    }
    private func store() {
        guard ready else { return }
        let n = { (s: String) in max(0, Int(s.filter(\.isNumber)) ?? 0) }
        doc.v["weight"] = NSNumber(value: n(wt))
        let L = n(l), W = n(w), H = n(h)
        if L > 0 && W > 0 && H > 0 { doc.v["box"] = ["length": L, "width": W, "height": H] } else { doc.v.removeValue(forKey: "box") }
        doc.v.removeValue(forKey: "pack")
    }
}

/// «С этим носят»: крупные фото товаров, поиск, отметка до N вещей
struct LookPick: View {
    let label: String
    let max: Int
    let selfId: String
    @Binding var selected: [String]
    @ObservedObject private var admin = Admin.shared
    @State private var open = false
    init(label: String, max: Int, selfId: String, selected: Binding<[String]>) {
        self.label = label; self.max = max; self.selfId = selfId; _selected = selected
    }
    private var all: [Product] { admin.data["products"].array.map(Product.init).filter { $0.id != selfId } }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label).font(Theme.font(14)).foregroundStyle(Theme.muted)
                Spacer()
                Text(selected.isEmpty ? "Не выбрано" : "\(selected.count) из \(max)").font(Theme.font(13, .medium)).foregroundStyle(selected.isEmpty ? Theme.dim : Theme.accent)
            }
            let chosen = selected.compactMap { id in all.first { $0.id == id } }
            if !chosen.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(chosen, id: \.id) { p in
                            VStack(alignment: .leading, spacing: 5) {
                                ProductImage(path: p.image).frame(width: 92, height: 122).background(Theme.photo).clipShape(RoundedRectangle(cornerRadius: 14))
                                Text(p.name).font(Theme.font(12)).foregroundStyle(Theme.text).lineLimit(2).frame(width: 92, alignment: .leading)
                            }
                        }
                    }
                }
            }
            Button { open = true } label: {
                HStack(spacing: 8) { Image(systemName: chosen.isEmpty ? "plus" : "square.grid.2x2"); Text(chosen.isEmpty ? "Выбрать вещи" : "Изменить выбор") }
                    .font(Theme.font(14.5, .medium)).foregroundStyle(Theme.text).frame(maxWidth: .infinity).frame(height: 46)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
            }.buttonStyle(Pressable())
        }
        .sheet(isPresented: $open) { LookSheet(title: label, max: max, products: all, selected: $selected) }
    }
}

private struct LookSheet: View {
    let title: String
    let max: Int
    let products: [Product]
    @Binding var selected: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var q = ""
    private var list: [Product] {
        let f = products.filter { q.isEmpty || ($0.name + " " + $0.sku).lowercased().contains(q.lowercased()) }
        return f.sorted { (selected.firstIndex(of: $0.id) ?? 99) < (selected.firstIndex(of: $1.id) ?? 99) }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                if list.isEmpty {
                    Text(q.isEmpty ? "Других товаров пока нет" : "Ничего не нашлось").font(Theme.font(14)).foregroundStyle(Theme.muted).padding(.top, 40)
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 16) {
                    ForEach(list, id: \.id) { p in card(p) }
                }
                .padding(16)
            }
            .background(Color.white)
            .searchable(text: $q, placement: .navigationBarDrawer(displayMode: .always), prompt: "Название или артикул")
            .navigationTitle(selected.isEmpty ? "С этим носят" : "Выбрано \(selected.count) из \(max)").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
    }
    private func card(_ p: Product) -> some View {
        let on = selected.contains(p.id)
        return Button {
            if let i = selected.firstIndex(of: p.id) { selected.remove(at: i); Haptic.tap() }
            else if selected.count < max { selected.append(p.id); Haptic.tap() }
            else { Toast.shared.show("Можно отметить до \(max) вещей — снимите отметку с одной из выбранных") }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Color.clear.aspectRatio(3 / 4, contentMode: .fit)
                    .overlay(ProductImage(path: p.image).opacity(p.active ? 1 : 0.55))
                    .background(Theme.photo)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(on ? Theme.accent : Theme.line, lineWidth: on ? 2 : 1))
                    .overlay(alignment: .topTrailing) {
                        ZStack {
                            Circle().fill(on ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.white.opacity(0.92)))
                            if on { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white) }
                            else { Circle().stroke(Theme.line, lineWidth: 1) }
                        }.frame(width: 28, height: 28).padding(10)
                    }
                    .overlay(alignment: .bottomLeading) {
                        if !p.active { Text("Скрыт").font(Theme.font(11)).foregroundStyle(Theme.muted).padding(.horizontal, 8).padding(.vertical, 3).background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.92))).padding(10) }
                    }
                Text(p.name).font(Theme.font(13.5)).foregroundStyle(Theme.text).lineLimit(2).multilineTextAlignment(.leading)
                Text((p.sku.isEmpty ? "" : p.sku + " · ") + Fmt.rub(p.price)).font(Theme.font(12)).foregroundStyle(Theme.muted)
            }
        }.buttonStyle(Pressable())
    }
}

/// Несколько вариантов галочками (категории акции, товары образа)
struct MultiPick: View {
    let label: String
    let options: [(String, String)]
    @Binding var selected: [String]
    @State private var open = false
    @State private var q = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(Theme.font(14)).foregroundStyle(Theme.muted)
            Button { open = true } label: {
                HStack {
                    Text(selected.isEmpty ? "Не выбрано" : options.filter { selected.contains($0.0) }.map(\.1).joined(separator: ", ")).font(Theme.font(15)).foregroundStyle(Theme.text).lineLimit(2).multilineTextAlignment(.leading)
                    Spacer(); Text("\(selected.count)").font(Theme.font(13)).foregroundStyle(Theme.muted)
                }.padding(.horizontal, 16).frame(minHeight: 50).background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
            }
        }
        .sheet(isPresented: $open) {
            NavigationStack {
                List {
                    ForEach(options.filter { q.isEmpty || $0.1.lowercased().contains(q.lowercased()) }, id: \.0) { o in
                        Button { if let i = selected.firstIndex(of: o.0) { selected.remove(at: i) } else { selected.append(o.0) } } label: {
                            HStack { Text(o.1).font(Theme.font(15)).foregroundStyle(Theme.text); Spacer(); if selected.contains(o.0) { Image(systemName: "checkmark").foregroundStyle(Theme.ink) } }
                        }
                    }
                }
                .searchable(text: $q, placement: .navigationBarDrawer(displayMode: .always))
                .navigationTitle(label).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { open = false } } }
            }
        }
    }
}

/// Дата «ГГГГ-ММ-ДД» или пусто
struct DateField: View {
    let label: String
    @Binding var value: String
    private static let f: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f }()
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(Theme.font(14)).foregroundStyle(Theme.muted)
            HStack {
                if let d = DateField.f.date(from: value) {
                    DatePicker("", selection: Binding(get: { d }, set: { value = DateField.f.string(from: $0) }), displayedComponents: .date)
                        .labelsHidden().environment(\.locale, Locale(identifier: "ru_RU")).tint(Theme.ink)
                    Spacer()
                    Button { value = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.dim) }
                } else {
                    Button { value = DateField.f.string(from: Date()) } label: { Text("Без даты — указать").font(Theme.font(15)).foregroundStyle(Theme.text) }
                    Spacer()
                }
            }.padding(.horizontal, 14).frame(height: 50).background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
        }
    }
}

/// Цвет: кружок выбора + #hex
struct ColorField: View {
    let label: String
    @Binding var hex: String
    var body: some View {
        HStack {
            Text(label).font(Theme.font(14.5))
            Spacer()
            Text(hex).font(Theme.font(13)).foregroundStyle(Theme.muted)
            ColorPicker("", selection: Binding(get: { Color(hex: hex.isEmpty ? "#141414" : hex) }, set: { hex = $0.hexString }), supportsOpacity: false).labelsHidden()
        }.padding(.horizontal, 14).frame(height: 50).background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
    }
}

extension Color {
    var hexString: String {
        let u = UIColor(self); var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        u.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02x%02x%02x", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
}

/// Фото: превью, «Загрузить» (из галереи телефона на сервер), «Убрать»
struct ImageField: View {
    let label: String
    @Binding var value: String
    @State private var item: PhotosPickerItem?
    @State private var busy = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(Theme.font(14)).foregroundStyle(Theme.muted)
            HStack(spacing: 12) {
                RemoteImage(path: value).frame(width: 72, height: 72).background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 8) {
                    PhotosPicker(selection: $item, matching: .images) { Text(busy ? "Загружаю…" : value.isEmpty ? "Загрузить фото" : "Заменить фото").font(Theme.font(14, .medium)).foregroundStyle(Theme.text) }
                    if !value.isEmpty { Button("Убрать") { value = "" }.font(Theme.font(13.5)).foregroundStyle(Theme.danger) }
                }
                Spacer()
            }
        }
        .onChange(of: item) { it in Task { await upload(it) } }
    }
    private func upload(_ it: PhotosPickerItem?) async {
        guard let it else { return }
        busy = true; defer { busy = false; item = nil }
        do { value = try await API.shared.upload(ImageKit.jpeg(try await ImageKit.load(it))) } catch { Toast.shared.show(error.userMessage) }
    }
}

enum ImageKit {
    struct OpenFailed: LocalizedError {
        var errorDescription: String? { "Не получилось открыть фото. Если оно хранится в iCloud — проверьте связь и попробуйте ещё раз." }
    }
    /// Фото из галереи. Раньше сбой (фото в iCloud без связи, неподдерживаемый формат) молча пропускался:
    /// сотрудник выбирал фото, и ничего не происходило (аудит Q-B1). Отмена остаётся отменой — без сообщения
    static func load(_ item: PhotosPickerItem) async throws -> Data {
        let data: Data?
        do { data = try await item.loadTransferable(type: Data.self) }
        catch { throw error.isCancel ? error : OpenFailed() }
        guard let data else { throw OpenFailed() }
        return data
    }
    /// Фото с телефона — в JPEG не больше 2000 px по длинной стороне (сервер принимает до 12 МБ)
    static func jpeg(_ data: Data, max side: CGFloat = 2000) -> Data {
        guard let img = UIImage(data: data) else { return data }
        let k = min(1, side / max(img.size.width, img.size.height))
        let size = CGSize(width: (img.size.width * k).rounded(), height: (img.size.height * k).rounded())
        let r = UIGraphicsImageRenderer(size: size).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
        return r.jpegData(compressionQuality: 0.86) ?? data
    }
}

// MARK: - Стабильные ключи строк списка в панели (аудит IOS-04, IOS-05)

/// Раньше строки списка узнавались по номеру. После удаления поле ввода удалённой строки, теряя фокус,
/// ещё раз отдавало своё значение по старому номеру — и панель падала с «Index out of range».
/// Теперь у каждой строки свой ключ: SwiftUI узнаёт строку по нему, а чтение и запись идут по её текущему месту.
/// Если строки с этим ключом уже нет, запись не выполняется: удалённую строку изменять незачем.
/// Ключи свои, а не поле «id» строк: у меню, соцсетей и преимуществ сервер «id» не проверяет — его уникальность
/// не гарантирована. Ключи живут только в приложении и на сервер не уходят — данные списка не меняются.
struct RowKeys {
    private var keys: [UUID] = []

    /// Ключи для показа списка из count строк. Пока ключи не подстроены (первый показ, список загрузили) — временные
    func displayKeys(count: Int) -> [UUID] { keys.count == count ? keys : (0..<count).map { _ in UUID() } }
    /// Подстроить ключи под число строк: только если список заменили целиком (загрузка, сохранение)
    mutating func match(count: Int) { if keys.count != count { keys = (0..<count).map { _ in UUID() } } }

    /// Строка с этим ключом или nil, если её уже нет
    func row<T>(_ key: UUID, in rows: [T]) -> T? { position(key, in: rows).map { rows[$0] } }
    /// Изменить строку с этим ключом. false — строки уже нет, ничего не изменено
    @discardableResult func update<T>(_ key: UUID, in rows: inout [T], _ change: (inout T) -> Void) -> Bool {
        guard let i = position(key, in: rows) else { return false }
        change(&rows[i]); return true
    }
    mutating func append<T>(_ row: T, to rows: inout [T]) { rows.append(row); keys.append(UUID()) }
    mutating func remove<T>(_ key: UUID, from rows: inout [T]) {
        guard let i = position(key, in: rows) else { return }
        rows.remove(at: i); keys.remove(at: i)
    }
    mutating func move<T>(_ key: UUID, by offset: Int, in rows: inout [T]) {
        guard let i = position(key, in: rows), rows.indices.contains(i + offset) else { return }
        rows.swapAt(i, i + offset); keys.swapAt(i, i + offset)
    }
    /// Текущее место строки с этим ключом; nil — строки нет
    private func position<T>(_ key: UUID, in rows: [T]) -> Int? {
        guard let i = keys.firstIndex(of: key), rows.indices.contains(i) else { return nil }
        return i
    }
}

/// Строки (меню, соцсети, преимущества, способы доставки…): карточка на строку, ↑ ↓ ✕ и «Добавить»
struct RowsEditor: View {
    let label: String
    let cols: [FDef]
    @Binding var rows: [[String: Any]]
    /// Стабильные ключи строк (аудит IOS-04): номер строки меняется при удалении и перестановке
    @State private var keys = RowKeys()
    var body: some View {
        let ids = keys.displayKeys(count: rows.count)
        VStack(alignment: .leading, spacing: 10) {
            Text(label).font(Theme.font(16, .medium))
            ForEach(Array(ids.enumerated()), id: \.element) { i, id in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("\(i + 1)").font(Theme.font(12.5)).foregroundStyle(Theme.muted)
                        Spacer()
                        if i > 0 { tool("arrow.up") { keys.move(id, by: -1, in: &rows) } }
                        if i < ids.count - 1 { tool("arrow.down") { keys.move(id, by: 1, in: &rows) } }
                        tool("xmark") { keys.remove(id, from: &rows) }
                    }
                    let doc = Doc(rows[i])
                    // запись — в строку с этим ключом на её текущем месте; строку уже удалили — записывать некуда
                    RowFields(cols: cols, doc: doc) { v in var r = rows; if keys.update(id, in: &r, { $0 = v }) { rows = r } }
                }.padding(12).background(RoundedRectangle(cornerRadius: 16).fill(.white)).hairline(RoundedRectangle(cornerRadius: 16), 0.09)
            }
            Button { var r: [String: Any] = ["id": uid("r")]; for c in cols { if case .bool = c.kind { r[c.k] = false } else { r[c.k] = "" } }; keys.append(r, to: &rows) } label: {
                Label("Добавить", systemImage: "plus").font(Theme.font(14, .medium)).foregroundStyle(Theme.text).padding(.horizontal, 16).frame(height: 40).background(Capsule().fill(Theme.surface))
            }
        }
        .task(id: rows.count) { keys.match(count: rows.count) }   // первый показ и замена списка целиком
    }
    private func tool(_ i: String, _ a: @escaping () -> Void) -> some View {
        Button { withAnimation { a() } } label: { Image(systemName: i).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.text).frame(width: 30, height: 30).background(Circle().fill(Theme.surface)) }.buttonStyle(.plain)
    }
}

private struct RowFields: View {
    let cols: [FDef]
    @ObservedObject var doc: Doc
    let changed: ([String: Any]) -> Void
    var body: some View {
        DefForm(defs: cols, doc: doc).onChange(of: doc.v.description) { _ in changed(doc.v) }
    }
}

// MARK: - Экран раздела панели: заголовок с точкой, подзаголовок, содержимое, кнопка «Сохранить» внизу

struct AdminPage<C: View>: View {
    let title: String
    var sub = ""
    var saveTitle: String? = nil
    var busy = false
    var error: String? = nil
    var onSave: (() -> Void)? = nil
    @ViewBuilder let content: () -> C
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                DotTitle(text: title, size: 30)
                if !sub.isEmpty { Text(sub).font(Theme.font(14)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true) }
                content()
                if let onSave {
                    ErrorText(text: error)
                    PrimaryButton(title: saveTitle ?? "Сохранить", busy: busy, action: onSave).padding(.top, 6)
                }
            }.padding(Theme.gutter).padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
}

/// Форма на основе настроек магазина (settingsForm на сайте): getObj берёт часть настроек, apply кладёт обратно
struct SettingsForm: View {
    let title: String
    var sub = ""
    let defs: [FDef]
    let getObj: ([String: Any]) -> [String: Any]
    let apply: (inout [String: Any], [String: Any]) -> String?
    var extra: AnyView? = nil
    @ObservedObject private var admin = Admin.shared
    @StateObject private var doc = Doc([:])
    @State private var loaded = false
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        AdminPage(title: title, sub: sub, busy: busy, error: error, onSave: { Task { await save() } }) {
            DefForm(defs: defs, doc: doc).padding(16).softCard(20)
            if let extra { extra }
        }
        .task {
            if !admin.data.exists { await admin.load() }
            if !loaded { doc.v = getObj(admin.data["settings"].dictAny); loaded = true }
        }
    }
    private func save() async {
        error = nil
        var s = admin.data["settings"].dictAny
        if let e = apply(&s, doc.v), !e.isEmpty { error = e; Haptic.error(); return }
        busy = true; defer { busy = false }
        do { try await AdminAPI.saveSettings(s); await AdminAPI.reload(); Haptic.success(); Toast.shared.show("Сохранено") }
        catch { self.error = error.userMessage; Haptic.error() }
    }
}

// MARK: - Коллекции: список и карточка

struct CollectionCfg {
    let key: String, prefix: String, title: String, newTitle: String, addLabel: String
    var sub = ""
    var searchable = false
    let itemTitle: (JSON) -> String
    var itemSub: (JSON) -> String = { _ in "" }
    var thumb: ((JSON) -> AnyView)? = nil
    var sort: ((JSON, JSON) -> Bool)? = nil
    let blank: () -> [String: Any]
    let fields: () -> [FDef]
    /// Дополнительный редактор под формой (таблица сетки, цвета товара…)
    var extra: ((Doc) -> AnyView)? = nil
    var read: ((inout [String: Any]) -> Void)? = nil
    var validate: (([String: Any], [JSON]) -> String)? = nil
    var duplicate: (([String: Any]) -> [String: Any])? = nil
    var canDelete: ((JSON) -> String?)? = nil
    /// Кнопки над списком: (название, значок, куда)
    var tools: [(String, String, Dest)] = []
}

struct CollectionList: View {
    let cfg: CollectionCfg
    @EnvironmentObject private var router: Router
    @ObservedObject private var admin = Admin.shared
    @State private var q = ""
    var body: some View {
        let all = admin.data[cfg.key].array
        let list = (cfg.sort.map { all.sorted(by: $0) } ?? all).filter { x in q.isEmpty || (cfg.itemTitle(x) + " " + cfg.itemSub(x)).lowercased().contains(q.lowercased()) }
        List {
            Section {
                if !cfg.sub.isEmpty { Text(cfg.sub).font(Theme.font(13.5)).foregroundStyle(Theme.muted) }
                Button { router.push(.adminItem(cfg.key, "new"), on: .account) } label: { Label(cfg.addLabel, systemImage: "plus").font(Theme.font(15, .medium)).foregroundStyle(Theme.text) }
                ForEach(Array(cfg.tools.enumerated()), id: \.offset) { _, t in
                    Button { router.push(t.2, on: .account) } label: { Label(t.0, systemImage: t.1).font(Theme.font(15)).foregroundStyle(Theme.text) }
                }
            }
            Section {
                if list.isEmpty { Text("Пока пусто").font(Theme.font(14)).foregroundStyle(Theme.muted) }
                ForEach(Array(list.enumerated()), id: \.offset) { _, x in
                    Button { router.push(.adminItem(cfg.key, x["id"].str), on: .account) } label: {
                        HStack(spacing: 12) {
                            if let t = cfg.thumb { t(x).frame(width: 48, height: 60).clipShape(RoundedRectangle(cornerRadius: 10)) }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(cfg.itemTitle(x).isEmpty ? "Без названия" : cfg.itemTitle(x)).font(Theme.font(15)).foregroundStyle(Theme.text)
                                let s = cfg.itemSub(x); if !s.isEmpty { Text(s).font(Theme.font(12.5)).foregroundStyle(Theme.muted).lineLimit(2) }
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Theme.dim)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $q, placement: .navigationBarDrawer(displayMode: cfg.searchable ? .always : .automatic), prompt: "Поиск")
        .navigationTitle(cfg.title).navigationBarTitleDisplayMode(.inline)
        .task { if !admin.data.exists { await admin.load() } }
        .refreshable { await admin.load() }
    }
}

struct CollectionEdit: View {
    let cfg: CollectionCfg
    let id: String
    @EnvironmentObject private var router: Router
    @ObservedObject private var admin = Admin.shared
    @StateObject private var doc = Doc([:])
    @State private var loaded = false
    @State private var busy = false
    @State private var error: String?
    @State private var confirmDelete = false
    private var isNew: Bool { id == "new" }
    var body: some View {
        AdminPage(title: isNew ? cfg.newTitle : (cfg.itemTitle(JSON(doc.v)).isEmpty ? "Без названия" : cfg.itemTitle(JSON(doc.v))), busy: busy, error: error, onSave: { Task { await save() } }) {
            if loaded {
                DefForm(defs: cfg.fields(), doc: doc).padding(16).softCard(20)
                if let extra = cfg.extra { extra(doc) }
                if !isNew {
                    HStack(spacing: 10) {
                        if cfg.duplicate != nil { GhostButton(title: "Копировать", icon: "doc.on.doc") { Task { await duplicate() } } }
                        GhostButton(title: "Удалить", icon: "trash") { confirmDelete = true }
                    }
                }
            } else { ProgressView().frame(maxWidth: .infinity).padding(40) }
        }
        .task {
            if !admin.data.exists { await admin.load() }
            if !loaded {
                doc.v = isNew ? cfg.blank() : (admin.data[cfg.key].array.first { $0["id"].str == id }?.dictAny ?? [:])
                loaded = true
            }
        }
        .confirmationDialog("Удалить?", isPresented: $confirmDelete, titleVisibility: .visible) { Button("Удалить", role: .destructive) { Task { await remove() } } }
    }
    private func save() async {
        error = nil
        var next = doc.v
        cfg.read?(&next)
        if let p = cfg.validate?(next, admin.data[cfg.key].array), !p.isEmpty { error = p; Haptic.error(); return }
        if (next["id"] as? String ?? "").isEmpty { next["id"] = uid(cfg.prefix) }
        busy = true; defer { busy = false }
        do {
            let r = try await AdminAPI.upsert(cfg.key, next)
            doc.v = next; await AdminAPI.reload(); Haptic.success(); Toast.shared.show(notifyMsg("Сохранено", r["notify"]))
            if isNew { router.pop(on: .account); router.push(.adminItem(cfg.key, next["id"] as? String ?? ""), on: .account) }
        } catch { self.error = error.userMessage; Haptic.error() }
    }
    private func duplicate() async {
        guard let dup = cfg.duplicate else { return }
        let copy = dup(doc.v)
        do { _ = try await AdminAPI.upsert(cfg.key, copy); await AdminAPI.reload(); Toast.shared.show("Создана копия"); router.push(.adminItem(cfg.key, copy["id"] as? String ?? ""), on: .account) }
        catch { Toast.shared.show(error.userMessage) }
    }
    private func remove() async {
        if let why = cfg.canDelete?(JSON(doc.v)) { error = why; return }
        do { try await AdminAPI.delete(cfg.key, id); await AdminAPI.reload(); Toast.shared.show("Удалено"); router.pop(on: .account) }
        catch { self.error = error.userMessage }
    }
}
