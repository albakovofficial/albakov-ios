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
            case .rows(let cols):
                RowsEditor(label: d.label, cols: cols, rows: Binding(get: { (doc.v[d.k] as? [[String: Any]]) ?? [] }, set: { doc.v[d.k] = $0 }))
            }
            if !d.hint.isEmpty { Text(d.hint).font(Theme.font(12.5)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true) }
        }
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
        guard let it, let data = try? await it.loadTransferable(type: Data.self) else { return }
        busy = true; defer { busy = false; item = nil }
        do { value = try await API.shared.upload(ImageKit.jpeg(data)) } catch { Toast.shared.show(error.localizedDescription) }
    }
}

enum ImageKit {
    /// Фото с телефона — в JPEG не больше 2000 px по длинной стороне (сервер принимает до 12 МБ)
    static func jpeg(_ data: Data, max side: CGFloat = 2000) -> Data {
        guard let img = UIImage(data: data) else { return data }
        let k = min(1, side / max(img.size.width, img.size.height))
        let size = CGSize(width: (img.size.width * k).rounded(), height: (img.size.height * k).rounded())
        let r = UIGraphicsImageRenderer(size: size).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
        return r.jpegData(compressionQuality: 0.86) ?? data
    }
}

/// Строки (меню, соцсети, преимущества, способы доставки…): карточка на строку, ↑ ↓ ✕ и «Добавить»
struct RowsEditor: View {
    let label: String
    let cols: [FDef]
    @Binding var rows: [[String: Any]]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label).font(Theme.font(16, .medium))
            ForEach(Array(rows.indices), id: \.self) { i in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("\(i + 1)").font(Theme.font(12.5)).foregroundStyle(Theme.muted)
                        Spacer()
                        if i > 0 { tool("arrow.up") { rows.swapAt(i, i - 1) } }
                        if i < rows.count - 1 { tool("arrow.down") { rows.swapAt(i, i + 1) } }
                        tool("xmark") { rows.remove(at: i) }
                    }
                    let doc = Doc(rows[i])
                    RowFields(cols: cols, doc: doc) { rows[i] = $0 }
                }.padding(12).background(RoundedRectangle(cornerRadius: 16).fill(.white)).hairline(RoundedRectangle(cornerRadius: 16), 0.09)
            }
            Button { var r: [String: Any] = ["id": uid("r")]; for c in cols { if case .bool = c.kind { r[c.k] = false } else { r[c.k] = "" } }; rows.append(r) } label: {
                Label("Добавить", systemImage: "plus").font(Theme.font(14, .medium)).foregroundStyle(Theme.text).padding(.horizontal, 16).frame(height: 40).background(Capsule().fill(Theme.surface))
            }
        }
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
        catch { self.error = error.localizedDescription; Haptic.error() }
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
        } catch { self.error = error.localizedDescription; Haptic.error() }
    }
    private func duplicate() async {
        guard let dup = cfg.duplicate else { return }
        let copy = dup(doc.v)
        do { _ = try await AdminAPI.upsert(cfg.key, copy); await AdminAPI.reload(); Toast.shared.show("Создана копия"); router.push(.adminItem(cfg.key, copy["id"] as? String ?? ""), on: .account) }
        catch { Toast.shared.show(error.localizedDescription) }
    }
    private func remove() async {
        if let why = cfg.canDelete?(JSON(doc.v)) { error = why; return }
        do { try await AdminAPI.delete(cfg.key, id); await AdminAPI.reload(); Toast.shared.show("Удалено"); router.pop(on: .account) }
        catch { self.error = error.localizedDescription }
    }
}
