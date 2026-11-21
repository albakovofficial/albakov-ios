import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// Товары в панели — как на сайте: все поля, плашки, цвета с фото и остатками по размерам, характеристики,
// мерки для подбора размера, предзаказ, образ; приход товара, массовые изменения, остатки в Excel.
@MainActor
enum AdminProduct {
    @MainActor static var cfg: CollectionCfg {
        CollectionCfg(key: "products", prefix: "p", title: "Товары", newTitle: "Новый товар", addLabel: "Добавить товар",
            sub: "Нажмите на товар, чтобы изменить цены, цвета, фото, размеры и остатки.", searchable: true,
            itemTitle: { $0["name"].str },
            itemSub: { p in
                let st = p["colors"].array.reduce(0) { $0 + $1["sizes"].array.reduce(0) { $0 + ($1["stock"].int ?? 0) } }
                let cat = Admin.shared.data["categories"].array.first { $0["id"].str == p["categoryId"].str }?["name"].str ?? "—"
                return [p["sku"].str, cat, Fmt.rub(p["price"].int ?? 0), "остаток \(st)", (p["active"].exists && !p["active"].bool) ? "скрыт" : ""].filter { !$0.isEmpty }.joined(separator: " · ")
            },
            thumb: { p in
                let c = p["colors"].array.first ?? JSON(nil)
                return AnyView(ProductImage(path: c["images"].array.first?.str ?? "", kind: c["art"]["kind"].string ?? "tee", tone: c["art"]["tone"].string ?? (c["hex"].string ?? "#3a3632")))
            },
            blank: {
                let col: [String: Any] = ["id": uid("col"), "name": "", "hex": "#3a3734", "images": [String](), "sizes": [[String: Any]](), "art": ["kind": "tee", "tone": "#3a3734"]]
                return ["name": "", "slug": "", "gender": "women", "categoryId": Admin.shared.data["categories"].array.first?["id"].str ?? "", "price": 0, "compareAt": 0, "tags": ["new"],
                        "description": "", "composition": "", "care": "", "colors": [col], "active": true, "createdAt": AdminSections.today()]
            },
            fields: { fields },
            extra: { doc in AnyView(ProductExtraEditor(doc: doc)) },
            read: { p in
                p.removeValue(forKey: "color"); p.removeValue(forKey: "images"); p.removeValue(forKey: "sizes"); p.removeValue(forKey: "art")
                let slug = (p["slug"] as? String) ?? ""
                p["slug"] = translit(slug.isEmpty ? (p["name"] as? String ?? "") : slug)
            },
            validate: { p, all in
                let j = JSON(p)
                if j["name"].str.isEmpty { return "Укажите название" }
                if (j["price"].int ?? 0) <= 0 { return "Укажите цену" }
                let cs = j["colors"].array
                if cs.isEmpty { return "Добавьте хотя бы один цвет" }
                if let bad = j["fit"]["rows"].array.first(where: { ($0["hMin"].double ?? 0) > 0 && ($0["hMax"].double ?? 0) > 0 && ($0["hMin"].double ?? 0) > ($0["hMax"].double ?? 0) || ($0["kMin"].double ?? 0) > 0 && ($0["kMax"].double ?? 0) > 0 && ($0["kMin"].double ?? 0) > ($0["kMax"].double ?? 0) }) { return "Мерки, размер \(bad["size"].str): «от» больше, чем «до»" }
                var names = Set<String>()
                for c in cs {
                    if c["name"].str.isEmpty { return "Укажите название для каждого цвета" }
                    if names.contains(c["name"].str.lowercased()) { return "Цвет «\(c["name"].str)» указан дважды" }
                    names.insert(c["name"].str.lowercased())
                    if c["sizes"].array.isEmpty { return "Добавьте размеры для цвета «\(c["name"].str)» (для аксессуаров — «Единый»)" }
                }
                if all.contains(where: { $0["id"].str != j["id"].str && $0["slug"].str == j["slug"].str }) { return "Такой адрес страницы уже занят другим товаром" }
                return ""
            },
            duplicate: { p in
                var x = p; x["id"] = uid("p"); x["sku"] = ""; x["name"] = (p["name"] as? String ?? "") + " (копия)"
                x["slug"] = translit(x["name"] as? String ?? "") + "-" + String(Int.random(in: 100...999), radix: 36); x["active"] = false
                return x
            },
            tools: [("Массовые изменения и остатки в Excel", "checklist", .adminSection("productsBulk"))])
    }

    @MainActor static var fields: [FDef] {
        return [.section("Основное"),
                FDef(k: "name", label: "Название"),
                FDef(k: "sku", label: "Артикул", hint: "Заполнится сам: ALB-0001, ALB-0002… Можно указать свой — латиница, цифры, дефис"),
                FDef(k: "categoryId", label: "Категория", kind: .select(AdminSections.catOpts)),
                FDef(k: "gender", label: "Для кого", kind: .select([("women", "Женщинам"), ("men", "Мужчинам"), ("kids", "Детям"), ("unisex", "Унисекс — женщинам и мужчинам")])),
                FDef(k: "price", label: "Цена, ₽", kind: .number, hint: "Одна для всех цветов"),
                FDef(k: "compareAt", label: "Старая цена, ₽", kind: .number, hint: "Если больше цены — показывается зачёркнутой. 0 — скидки нет"),
                FDef(k: "active", label: "Показывать в магазине", kind: .bool),
                .section("Доставка"),
                FDef(k: "parcel", label: "Посылка для СДЭК", kind: .parcel),
                .section("Описание"),
                FDef(k: "description", label: "Описание", kind: .area(5)),
                FDef(k: "composition", label: "Состав — свой текст", kind: .area(2), hint: "Нужен, только если состава нет среди вариантов в «Характеристиках»"),
                FDef(k: "care", label: "Уход — дополнительно", kind: .area(2), hint: "Основное отмечается значками в «Характеристиках»"),
                .section("Образ и предзаказ"),
                FDef(k: "look", label: "С этим носят — до 4 вещей", kind: .look(4), hint: "В карточке появится «Соберите образ»: покупатель выберет размеры и добавит все вещи одной кнопкой"),
                FDef(k: "preorder", label: "Предзаказ: можно заказать размеры, которых нет в наличии", kind: .bool),
                FDef(k: "preorderShip", label: "Когда отправим по предзаказу", kind: .date),
                FDef(k: "preorderLimit", label: "Мест в партии", kind: .number, hint: "Сколько вещей можно заказать заранее. 0 — без ограничения"),
                .section("Служебное"),
                FDef(k: "slug", label: "Адрес страницы", hint: "Латиницей. Заполнится сам из названия"),
                FDef(k: "createdAt", label: "Дата поступления", kind: .date, hint: "Для сортировки «Сначала новые»")]
    }
}

/// Под формой товара: плашки, цвета (фото, размеры, остатки), характеристики, мерки, приход товара
struct ProductExtraEditor: View {
    @ObservedObject var doc: Doc
    @ObservedObject private var admin = Admin.shared
    @State private var receive = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !(doc.v["id"] as? String ?? "").isEmpty {
                GhostButton(title: "Приход товара", icon: "shippingbox.and.arrow.backward") { receive = true }
                WaitingForProduct(productId: doc.v["id"] as? String ?? "")
            }
            BadgesEditor(doc: doc).padding(16).softCard(20)
            ColorsEditor(doc: doc).padding(16).softCard(20)
            SpecsEditor(doc: doc).padding(16).softCard(20)
            FitEditor(doc: doc).padding(16).softCard(20)
        }
        .sheet(isPresented: $receive) { ReceiveSheet(productId: doc.v["id"] as? String ?? "") }
    }
}

/// Плашки: «Новинка», «Скидка», «Хит продаж» — включить и свой текст
struct BadgesEditor: View {
    @ObservedObject var doc: Doc
    @ObservedObject private var admin = Admin.shared
    var body: some View {
        let conf = admin.data["settings"]["badges"]
        let rows = [("new", "Новинка", "Товар также появится в разделе «Новинки»."), ("sale", "Скидка", "Видна, только если у товара есть скидка. {n} заменится на размер скидки."), ("hit", "Хит продаж", "Товар попадёт в «Хиты продаж».")]
        VStack(alignment: .leading, spacing: 14) {
            Text("Плашки на карточке").font(Theme.font(18, .light))
            ForEach(rows, id: \.0) { r in
                let on = r.0 == "sale" ? !arr("badgeOff").contains("sale") : arr("tags").contains(r.0)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Toggle(isOn: Binding(get: { on }, set: { v in setOn(r.0, v) })) {
                            Badge(text: own(r.0).isEmpty ? (conf[r.0]["text"].string ?? r.1) : own(r.0), color: conf[r.0]["color"].string ?? "#141414", filled: r.0 == "sale").opacity(on ? 1 : 0.4)
                        }.tint(Theme.ink)
                    }
                    TextField(conf[r.0]["text"].string ?? r.1, text: Binding(get: { own(r.0) }, set: { setOwn(r.0, $0) })).font(Theme.font(15)).padding(.horizontal, 14).frame(height: 44).background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
                    Text(r.2).font(Theme.font(12)).foregroundStyle(Theme.muted)
                }
            }
            Text("Пустое поле — общий текст из «Настроек». Там же меняются цвета плашек.").font(Theme.font(12.5)).foregroundStyle(Theme.muted)
        }
    }
    private func arr(_ k: String) -> [String] { doc.arr(k).compactMap { $0 as? String } }
    private func own(_ k: String) -> String { (doc.v["badgeText"] as? [String: Any])?[k] as? String ?? "" }
    private func setOwn(_ k: String, _ t: String) { var b = (doc.v["badgeText"] as? [String: Any]) ?? [:]; if t.isEmpty { b.removeValue(forKey: k) } else { b[k] = t }; doc.v["badgeText"] = b }
    private func setOn(_ k: String, _ on: Bool) {
        if k == "sale" { doc.v["badgeOff"] = on ? [String]() : ["sale"]; return }
        var t = arr("tags").filter { $0 != k }; if on { t.append(k) }; doc.v["tags"] = t
    }
}

/// Цвета: название и оттенок, фото (загрузка, порядок, удаление), размеры с остатками.
/// Цвета и размеры узнаются по стабильным ключам (Q-2), а не по номеру: после удаления строки поле,
/// которое было в фокусе, не пишет в соседнюю. Ключи только в приложении — формат товара для сервера прежний
struct ColorsEditor: View {
    @ObservedObject var doc: Doc
    @State private var keys = RowKeys()
    private var colors: [[String: Any]] { (doc.v["colors"] as? [[String: Any]]) ?? [] }
    var body: some View {
        let ids = keys.displayKeys(count: colors.count)
        VStack(alignment: .leading, spacing: 14) {
            Text("Цвета, фото и остатки").font(Theme.font(18, .light))
            Text("Все цвета — в одной карточке товара. У каждого цвета свои фото и остатки по размерам. Покупатель сначала выбирает цвет, потом размер.").font(Theme.font(13)).foregroundStyle(Theme.muted)
            ForEach(Array(ids.enumerated()), id: \.element) { i, id in
                ColorCard(color: colors[i], index: i, first: colors[0], canRemove: colors.count > 1,
                          update: { change in edit { k, cs in k.update(id, in: &cs, change) } },
                          moveUp: { edit { k, cs in k.move(id, by: -1, in: &cs) } },
                          remove: { edit { k, cs in k.remove(id, from: &cs) } })
            }
            Button {
                let cs = colors
                var c: [String: Any] = ["id": uid("col"), "name": "", "hex": "#777777", "images": [String](), "art": ["kind": JSON(cs.first?["art"])["kind"].string ?? "tee", "tone": "#777777"]]
                c["sizes"] = (cs.first?["sizes"] as? [[String: Any]] ?? []).map { ["size": $0["size"] ?? "", "stock": 0] }
                edit { k, cs in k.append(c, to: &cs) }
            } label: { Label("Добавить цвет", systemImage: "plus").font(Theme.font(14, .medium)).foregroundStyle(Theme.text).padding(.horizontal, 16).frame(height: 40).background(Capsule().fill(Theme.surface)) }
        }
        .task(id: colors.count) { keys.match(count: colors.count) }   // первый показ и замена списка целиком
    }
    /// Цвета и их ключи меняются вместе
    private func edit(_ change: (inout RowKeys, inout [[String: Any]]) -> Void) {
        var cs = colors
        change(&keys, &cs)
        doc.v["colors"] = cs
    }
}

/// Один цвет: оттенок, название, фото и размеры с остатками. Свои ключи размеров (Q-2)
private struct ColorCard: View {
    let color: [String: Any]
    let index: Int
    let first: [String: Any]
    let canRemove: Bool
    /// Изменить этот цвет (по его ключу; цвета уже нет — ничего не меняется)
    let update: ((inout [String: Any]) -> Void) -> Void
    let moveUp: () -> Void
    let remove: () -> Void
    @State private var sizeKeys = RowKeys()
    private var sizes: [[String: Any]] { (color["sizes"] as? [[String: Any]]) ?? [] }
    var body: some View {
        let c = JSON(color)
        let ids = sizeKeys.displayKeys(count: sizes.count)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ColorPicker("", selection: Binding(get: { Color(hex: c["hex"].string ?? "#777777") }, set: { v in update { $0["hex"] = v.hexString; var a = ($0["art"] as? [String: Any]) ?? ["kind": "tee"]; a["tone"] = v.hexString; $0["art"] = a } }), supportsOpacity: false).labelsHidden()
                TextField("Название цвета, например «Графит»", text: Binding(get: { c["name"].str }, set: { v in update { $0["name"] = v } }))
                    .font(Theme.font(15)).padding(.horizontal, 12).frame(height: 44).background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
                if index > 0 { tool("arrow.up", moveUp) }
                if canRemove { tool("xmark", remove) }
            }
            ColorPhotos(images: Binding(get: { c["images"].array.map(\.str) }, set: { v in update { $0["images"] = v } }),
                        add: { url in update { $0["images"] = JSON($0["images"]).array.map(\.str) + [url] } })
            VStack(spacing: 6) {
                ForEach(Array(ids.enumerated()), id: \.element) { k, id in
                    let z = JSON(sizes[k])
                    HStack(spacing: 8) {
                        TextField("Размер", text: Binding(get: { z["size"].str }, set: { v in editSizes { $0.update(id, in: &$1) { $0["size"] = v } } })).font(Theme.font(15)).padding(.horizontal, 12).frame(height: 42).background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
                        TextField("Остаток", text: Binding(get: { String(z["stock"].int ?? 0) }, set: { v in editSizes { $0.update(id, in: &$1) { $0["stock"] = max(0, Int(v.filter(\.isNumber)) ?? 0) } } }))
                            .keyboardType(.numberPad).font(Theme.font(15)).padding(.horizontal, 12).frame(width: 96, height: 42).background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
                        Text("шт.").font(Theme.font(12.5)).foregroundStyle(Theme.muted)
                        tool("xmark") { editSizes { $0.remove(id, from: &$1) } }
                    }
                }
            }
            FlowRow(spacing: 8) {
                small("+ Размер") { editSizes { $0.append(["size": "", "stock": 0], to: &$1) } }
                if index > 0 { small("Размеры как у «\(JSON(first)["name"].string.flatMap { $0.isEmpty ? nil : $0 } ?? "первого цвета")»") {
                    let names = ((first["sizes"] as? [[String: Any]]) ?? []).map { $0["size"] as? String ?? "" }
                    editSizes { k, s in for n in names where !s.contains(where: { ($0["size"] as? String) == n }) { k.append(["size": n, "stock": 0], to: &s) } }
                } }
            }
        }
        .padding(14).background(RoundedRectangle(cornerRadius: 16).fill(.white)).hairline(RoundedRectangle(cornerRadius: 16), 0.1)
        .task(id: sizes.count) { sizeKeys.match(count: sizes.count) }   // первый показ и замена размеров целиком
    }
    /// Размеры этого цвета и их ключи меняются вместе
    private func editSizes(_ change: (inout RowKeys, inout [[String: Any]]) -> Void) {
        update { c in
            var s = (c["sizes"] as? [[String: Any]]) ?? []
            change(&sizeKeys, &s)
            c["sizes"] = s
        }
    }
    private func tool(_ i: String, _ a: @escaping () -> Void) -> some View {
        Button { withAnimation { a() } } label: { Image(systemName: i).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.text).frame(width: 30, height: 30).background(Circle().fill(Theme.surface)) }.buttonStyle(.plain)
    }
    private func small(_ t: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) { Text(t).font(Theme.font(13, .medium)).foregroundStyle(Theme.text).padding(.horizontal, 12).frame(height: 34).background(Capsule().strokeBorder(Theme.lineStrong)) }.buttonStyle(.plain)
    }
}

/// Фото цвета: первое — главное; ← сделать раньше, ✕ удалить, «+ Фото» — несколько сразу
struct ColorPhotos: View {
    @Binding var images: [String]
    /// Добавить загруженное фото к текущим фото цвета. Загрузка идёт дольше одной перерисовки, а images — снимок
    /// с прошлой отрисовки: images.append добавлял каждое фото к одному и тому же старому списку, и из нескольких
    /// выбранных у цвета оставалось только последнее, остальные лежали на сервере ни к чему не привязанными (аудит M-1)
    let add: (String) -> Void
    @State private var picks: [PhotosPickerItem] = []
    @StateObject private var uploads = PhotoBatchUpload()
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(images.enumerated()), id: \.offset) { k, src in
                    RemoteImage(path: src).frame(width: 78, height: 104).clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(alignment: .topTrailing) {
                            HStack(spacing: 4) {
                                if k > 0 { mini("arrow.left") { images.swapAt(k, k - 1) } }
                                mini("xmark") { images.remove(at: k) }
                            }.padding(4)
                        }
                        .overlay(alignment: .bottomLeading) { if k == 0 { Text("Главное").font(Theme.font(9.5, .semibold)).padding(.horizontal, 6).padding(.vertical, 3).background(Capsule().fill(.white)).padding(4) } }
                }
                // Метка PhotosPicker в SDK — @Sendable, вложенный VStack наследует её неизолированность: в метку передаётся значение
                // busy (Bool), а не вся View (этап L.2.24, как в L.2.22–L.2.23). Метка не escaping — вызывается сразу, в том же
                // пересчёте body, поэтому значение всегда текущее
                PhotosPicker(selection: $picks, maxSelectionCount: 10, matching: .images) { [busy = uploads.busy] in
                    VStack(spacing: 6) { if busy { ProgressView() } else { Image(systemName: "plus") }; Text("Фото этого цвета").font(Theme.font(10.5)).multilineTextAlignment(.center) }
                        .foregroundStyle(Theme.muted).frame(width: 78, height: 104).background(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.lineStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                }
            }
        }
        // пока фото цвета грузятся, «Сохранить» недоступна (этап L.2.29, как ImageField в L.2.28): иначе карточка товара
        // сохранилась бы без них. busy держится, пока идёт хоть одна загрузка этого цвета
        .preference(key: PhotoUploadingKey.self, value: uploads.busy)
        .onChange(of: picks) { items in
            guard !items.isEmpty else { return }
            // выбор принят сразу: следующий выбор во время загрузки — новые фото, а не этот же выбор ещё раз
            // (раньше выбор очищался только в конце загрузки и открытый снова PhotosPicker показывал его отмеченным)
            picks = []
            uploads.start(items, { try await API.shared.upload(try await ImageKit.jpeg(try await ImageKit.load($0))) },
                          add: { add($0) }, fail: { Toast.shared.show($0.userMessage) })
        }
    }
    private func mini(_ i: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) { Image(systemName: i).font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.text).frame(width: 22, height: 22).background(Circle().fill(.white)) }.buttonStyle(.plain)
    }
}

/// Загрузка фото цвета (ColorPhotos, этап L.2.29). Выбранные фото загружаются по очереди и каждое добавляется к фото цвета,
/// ошибка одного не останавливает остальные. Пока выбор не догрузился, можно выбрать ещё — это отдельная загрузка, она идёт
/// параллельно и тоже добавляет фото (здесь все выбранные фото нужны, устаревших нет — не как в PhotoUpload). busy
/// («Загружаю…» и блокировка «Сохранить») держится, пока идёт хоть одна: раньше один флаг на все загрузки, и конец первой
/// гасил его, хотя вторая ещё шла. Последнее фото добавляется и счётчик уменьшается в одном шаге главного актора —
/// «Сохранить» становится доступна, когда все фото уже в карточке
@MainActor final class PhotoBatchUpload: ObservableObject {
    @Published private(set) var running = 0
    var busy: Bool { running > 0 }
    /// work — получить, обработать и отправить одно фото (тяжёлая часть — вне главного актора, в ImageKit.jpeg);
    /// add — добавить загруженное, fail — показать ошибку этого фото
    func start<T: Sendable>(_ items: [T], _ work: @escaping @MainActor (T) async throws -> String, add: @escaping @MainActor (String) -> Void, fail: @escaping @MainActor (any Error) -> Void) {
        guard !items.isEmpty else { return }
        running += 1
        Task {
            for it in items {
                do { add(try await work(it)) } catch { fail(error) }
            }
            self.running -= 1
        }
    }
}

/// Характеристики: варианты капсулами (одна или несколько), свой вариант, значки ухода
struct SpecsEditor: View {
    @ObservedObject var doc: Doc
    private var specs: [String: Any] { (doc.v["specs"] as? [String: Any]) ?? [:] }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Характеристики").font(Theme.font(18, .light))
            Text("Отметьте подходящее — в карточке товара появится блок «Характеристики», а поисковики увидят их в описании товара.").font(Theme.font(13)).foregroundStyle(Theme.muted)
            ForEach(Specs.groups, id: \.title) { g in
                VStack(alignment: .leading, spacing: 12) {
                    Text(g.title).font(Theme.font(15, .medium))
                    ForEach(g.items, id: \.k) { it in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(it.label + (it.multi ? " · можно несколько" : "")).font(Theme.font(13)).foregroundStyle(Theme.muted)
                            FlowRow(spacing: 6) { ForEach(it.options, id: \.0) { o in chip(o.1, on: isOn(it, o.0)) { toggle(it, o.0) } } }
                            if let ph = it.custom {
                                TextField(ph, text: Binding(get: { let v = specs[it.k] as? String ?? ""; return v.hasPrefix("custom:") ? String(v.dropFirst(7)) : "" },
                                                            set: { v in var s = specs; if v.isEmpty { s.removeValue(forKey: it.k) } else { s[it.k] = "custom:" + v }; doc.v["specs"] = s }))
                                    .font(Theme.font(14)).padding(.horizontal, 12).frame(height: 40).background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface))
                            }
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Уход — значки на этикетке · можно несколько").font(Theme.font(13)).foregroundStyle(Theme.muted)
                FlowRow(spacing: 6) {
                    ForEach(Specs.care, id: \.0) { c in
                        let on = (specs["care"] as? [String] ?? []).contains(c.0)
                        chip(c.1, on: on, icon: Specs.careIcon[c.0]) {
                            var s = specs; var a = s["care"] as? [String] ?? []
                            if on { a.removeAll { $0 == c.0 } } else { a.append(c.0) }
                            if a.isEmpty { s.removeValue(forKey: "care") } else { s["care"] = a }; doc.v["specs"] = s
                        }
                    }
                }
            }
        }
    }
    private func isOn(_ it: Specs.Item, _ v: String) -> Bool { it.multi ? (specs[it.k] as? [String] ?? []).contains(v) : (specs[it.k] as? String) == v }
    private func toggle(_ it: Specs.Item, _ v: String) {
        var s = specs
        if it.multi { var a = s[it.k] as? [String] ?? []; if a.contains(v) { a.removeAll { $0 == v } } else { a.append(v) }; if a.isEmpty { s.removeValue(forKey: it.k) } else { s[it.k] = a } }
        else { if (s[it.k] as? String) == v { s.removeValue(forKey: it.k) } else { s[it.k] = v } }
        doc.v["specs"] = s
    }
    private func chip(_ t: String, on: Bool, icon: String? = nil, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            HStack(spacing: 5) { if let icon { Image(systemName: icon).font(.system(size: 11)) }; Text(t).font(Theme.font(12.5)) }
                .foregroundStyle(on ? .white : Theme.text).padding(.horizontal, 11).frame(height: 32).background(Capsule().fill(on ? Theme.accent : Theme.surface))
        }.buttonStyle(.plain)
    }
}

/// Таблица размеров товара (1.0.1): своя у каждого товара — мерки на каждый размер, свои столбцы, подсказка;
/// рост и вес — для «Подобрать размер»; размер и рост модели. Покупатель видит её в карточке товара
struct FitEditor: View {
    @ObservedObject var doc: Doc
    private static let base = [("w", "Ширина"), ("l", "Длина"), ("sl", "Рукав")]
    private static let body2 = [("hMin", "Рост от"), ("hMax", "Рост до"), ("kMin", "Вес от"), ("kMax", "Вес до")]
    private var fit: [String: Any] { (doc.v["fit"] as? [String: Any]) ?? [:] }
    private var rows: [[String: Any]] { (fit["rows"] as? [[String: Any]]) ?? [] }
    private var cols: [String] { (fit["cols"] as? [String]) ?? [] }
    private var sizes: [String] { var out: [String] = []; for c in (doc.v["colors"] as? [[String: Any]] ?? []) { for s in (c["sizes"] as? [[String: Any]] ?? []) { let n = s["size"] as? String ?? ""; if !n.isEmpty && !out.contains(n) { out.append(n) } } }; return out }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Таблица размеров").font(Theme.font(18, .light))
            Text("Своя у каждого товара — покупатель видит её в карточке товара. Мерки готовой вещи в сантиметрах: ширина — от шва до шва под рукавами, длина — от плеча до низа. Нужен другой замер — добавьте свой столбец. Рост и вес — на кого рассчитан размер.").font(Theme.font(13)).foregroundStyle(Theme.muted)
            if sizes.isEmpty { Text("Сначала добавьте размеры в цвета товара").font(Theme.font(13.5)).foregroundStyle(Theme.muted) }
            ScrollView(.horizontal, showsIndicators: true) {
                Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 6) {
                    GridRow {
                        Text("Размер").font(Theme.font(11.5)).foregroundStyle(Theme.muted)
                        ForEach(FitEditor.base, id: \.0) { Text($0.1 + ", см").font(Theme.font(11.5)).foregroundStyle(Theme.muted) }
                        ForEach(cols.indices, id: \.self) { i in
                            HStack(spacing: 2) {
                                TextField("Название", text: Binding(get: { cols.indices.contains(i) ? cols[i] : "" }, set: { setCol(i, $0) })).font(Theme.font(11.5)).frame(width: 74)
                                Button { removeCol(i) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.muted) }.accessibilityLabel("Удалить столбец")
                            }
                        }
                        ForEach(FitEditor.body2, id: \.0) { Text($0.1 + ($0.0.hasPrefix("k") ? ", кг" : ", см")).font(Theme.font(11.5)).foregroundStyle(Theme.muted) }
                    }
                    ForEach(sizes, id: \.self) { sz in
                        GridRow {
                            Text(sz).font(Theme.font(14, .medium))
                            ForEach(FitEditor.base, id: \.0) { c in numField(sz, c.0) }
                            ForEach(cols.indices, id: \.self) { i in
                                TextField("", text: Binding(get: { xVal(sz, i) }, set: { setX(sz, i, $0) }))
                                    .font(Theme.font(14)).multilineTextAlignment(.center).frame(width: 90, height: 38).background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
                            }
                            ForEach(FitEditor.body2, id: \.0) { c in numField(sz, c.0) }
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                Button("+ Свой столбец") { addCol() }.font(Theme.font(13, .medium)).foregroundStyle(Theme.text).buttonStyle(.bordered).tint(Theme.ink)
                Button("Рост и вес — типовые") { fillTypical() }.font(Theme.font(13, .medium)).foregroundStyle(Theme.text).buttonStyle(.bordered).tint(Theme.ink)
            }
            Field(label: "Подсказка над таблицей", text: Binding(get: { fit["note"] as? String ?? "" }, set: { var f = fit; f["note"] = String($0.prefix(300)); doc.v["fit"] = f }), placeholder: "Например: длина брюк — по внутреннему шву")
            HStack(spacing: 10) {
                Field(label: "На модели размер", text: Binding(get: { fit["modelSize"] as? String ?? "" }, set: { var f = fit; f["modelSize"] = String($0.prefix(10)); doc.v["fit"] = f }), placeholder: "например, L")
                Field(label: "Рост модели, см", text: Binding(get: { (fit["modelHeight"] as? NSNumber).map { "\($0.intValue)" } ?? "" }, set: { var f = fit; f["modelHeight"] = Int($0) ?? ""; doc.v["fit"] = f }), keyboard: .numberPad)
            }
        }
    }
    private func numField(_ sz: String, _ k: String) -> some View {
        TextField("", text: Binding(get: { let v = (rows.first { ($0["size"] as? String) == sz }?[k] as? NSNumber)?.doubleValue ?? 0; return v > 0 ? String(format: "%g", v) : "" },
                                    set: { setVal(sz, k, $0) }))
            .keyboardType(.decimalPad).font(Theme.font(14)).multilineTextAlignment(.center).frame(width: 62, height: 38).background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
    }
    private func xVal(_ sz: String, _ i: Int) -> String {
        let x = (rows.first { ($0["size"] as? String) == sz }?["x"] as? [String]) ?? []
        return i < x.count ? x[i] : ""
    }
    private func setX(_ sz: String, _ i: Int, _ t: String) {
        var f = fit, r = rows
        let idx: Int
        if let k = r.firstIndex(where: { ($0["size"] as? String) == sz }) { idx = k } else { r.append(["size": sz]); idx = r.count - 1 }
        var x = (r[idx]["x"] as? [String]) ?? []
        while x.count <= i { x.append("") }
        x[i] = String(t.prefix(30))
        if x.contains(where: { !$0.isEmpty }) { r[idx]["x"] = x } else { r[idx].removeValue(forKey: "x") }
        f["rows"] = r.filter { $0.count > 1 }; doc.v["fit"] = f
    }
    private func setCol(_ i: Int, _ t: String) { var f = fit, c = cols; guard c.indices.contains(i) else { return }; c[i] = String(t.prefix(40)); f["cols"] = c; doc.v["fit"] = f }
    private func addCol() {
        guard cols.count < 6 else { Toast.shared.show("Не больше 6 своих столбцов"); return }
        var f = fit; f["cols"] = cols + ["Мерка"]; doc.v["fit"] = f
    }
    private func removeCol(_ i: Int) {
        var f = fit, c = cols; guard c.indices.contains(i) else { return }
        c.remove(at: i); f["cols"] = c
        f["rows"] = rows.map { r -> [String: Any] in
            var r = r
            if var x = r["x"] as? [String], i < x.count { x.remove(at: i); if x.contains(where: { !$0.isEmpty }) { r["x"] = x } else { r.removeValue(forKey: "x") } }
            return r
        }.filter { $0.count > 1 }
        doc.v["fit"] = f
    }
    private func setVal(_ sz: String, _ k: String, _ t: String) {
        var f = fit, r = rows
        let v = Double(t.replacingOccurrences(of: ",", with: ".")) ?? 0
        if let i = r.firstIndex(where: { ($0["size"] as? String) == sz }) { if v > 0 { r[i][k] = v } else { r[i].removeValue(forKey: k) } }
        else if v > 0 { r.append(["size": sz, k: v]) }
        f["rows"] = r.filter { $0.count > 1 }; doc.v["fit"] = f
    }
    private func fillTypical() {
        var n = 0
        for sz in sizes { guard let t = Fit.typicalTable[sz.uppercased()] else { continue }
            for (i, k) in ["hMin", "hMax", "kMin", "kMax"].enumerated() where ((rows.first { ($0["size"] as? String) == sz }?[k] as? NSNumber)?.doubleValue ?? 0) == 0 { setVal(sz, k, String(t[i])); n += 1 } }
        Toast.shared.show(n > 0 ? "Заполнено — проверьте и поправьте под свои лекала" : "Нечего заполнять: типовые значения есть для XS–3XL")
    }
}

/// «Сообщить о поступлении» по этому товару: сколько человек ждёт
struct WaitingForProduct: View {
    let productId: String
    @ObservedObject private var admin = Admin.shared
    var body: some View {
        let w = admin.data["waitlist"].array.filter { $0["productId"].str == productId && ($0["status"].str == "waiting" || $0["status"].str == "failed") }
        if !w.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "bell").font(.system(size: 14, weight: .light))
                Text("Ждут поступления: \(w.count) \(Fmt.plural(w.count, "человек", "человека", "человек")). Как только остаток станет больше нуля, им уйдёт письмо.").font(Theme.font(13.5))
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 14).fill(Theme.tint))
        }
    }
}

/// Приход товара: сколько штук каждого цвета и размера пришло и почём; остатки растут сразу, закупка — в «Финансы»
struct ReceiveSheet: View {
    let productId: String
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var admin = Admin.shared
    @State private var pid = ""
    @State private var date = Date()
    @State private var qty: [String: String] = [:]
    @State private var unit = ""
    @State private var cat = ""
    @State private var mode = "avg"
    @State private var note = ""
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        let prods = admin.data["products"].array.sorted { $0["name"].str < $1["name"].str }
        let p = prods.first { $0["id"].str == pid } ?? prods.first ?? JSON(nil)
        let cats = admin.data["finance"]["categories"].array.filter { $0["kind"].str == "purchase" }
        let cost0 = admin.data["finance"]["costs"][p["id"].str].int ?? 0
        let lines = p["colors"].array.flatMap { c in c["sizes"].array.map { (c["id"].str, $0["size"].str) } }.compactMap { k -> [String: Any]? in let q = Int(qty[k.0 + "|" + k.1] ?? "") ?? 0; return q > 0 ? ["colorId": k.0, "size": k.1, "qty": q] : nil }
        let total = lines.reduce(0) { $0 + ($1["qty"] as? Int ?? 0) }, u = Int(unit) ?? 0
        let units0 = p["colors"].array.reduce(0) { $0 + $1["sizes"].array.reduce(0) { $0 + max(0, $1["stock"].int ?? 0) } }
        let c1 = u == 0 || mode == "keep" ? cost0 : mode == "set" || cost0 == 0 || units0 == 0 ? u : Int((Double(units0 * cost0 + total * u) / Double(units0 + total)).rounded())
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Остатки увеличатся сразу, покупатели из списка «Сообщить о поступлении» получат письмо, сумма закупки попадёт в «Финансы».").font(Theme.font(13.5)).foregroundStyle(Theme.muted)
                    Menu { Picker("Товар", selection: $pid) { ForEach(prods.indices, id: \.self) { i in Text(prods[i]["name"].str).tag(prods[i]["id"].str) } } } label: {
                        HStack { Text(p["name"].str).font(Theme.font(15.5)).foregroundStyle(Theme.text); Spacer(); Image(systemName: "chevron.up.chevron.down").font(.system(size: 11)) }.padding(.horizontal, 16).frame(height: 50).background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
                    }
                    DatePicker("Дата", selection: $date, displayedComponents: .date).font(Theme.font(15)).environment(\.locale, Locale(identifier: "ru_RU"))
                    ForEach(p["colors"].array.indices, id: \.self) { ci in
                        let c = p["colors"].array[ci]
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) { Circle().fill(Color(hex: c["hex"].string ?? "#ccc")).frame(width: 14, height: 14); Text(c["name"].string ?? "Цвет").font(Theme.font(15, .medium)) }
                            FlowRow(spacing: 8) {
                                ForEach(c["sizes"].array.indices, id: \.self) { zi in
                                    let z = c["sizes"].array[zi], key = c["id"].str + "|" + z["size"].str
                                    VStack(spacing: 2) {
                                        Text(z["size"].str).font(Theme.font(12.5, .medium))
                                        TextField("0", text: Binding(get: { qty[key] ?? "" }, set: { qty[key] = $0.filter(\.isNumber) })).keyboardType(.numberPad).multilineTextAlignment(.center).font(Theme.font(15)).frame(width: 60, height: 36).background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
                                        Text("было \(z["stock"].int ?? 0)").font(Theme.font(10.5)).foregroundStyle(Theme.muted)
                                    }
                                }
                            }
                        }
                    }
                    Text("Сейчас себестоимость: " + (cost0 > 0 ? Fmt.rub(cost0) : "не указана")).font(Theme.font(13)).foregroundStyle(Theme.muted)
                    Field(label: "Цена одной вещи, ₽ — пошив, ткань, фурнитура", text: $unit, placeholder: "Например, 1200", keyboard: .numberPad)
                    if !cats.isEmpty {
                        Menu { Picker("Категория", selection: $cat) { ForEach(cats.indices, id: \.self) { i in Text(cats[i]["name"].str).tag(cats[i]["id"].str) } } } label: {
                            HStack { Text("Категория в «Финансах»: " + (cats.first { $0["id"].str == cat }?["name"].str ?? cats[0]["name"].str)).font(Theme.font(14.5)).foregroundStyle(Theme.text); Spacer(); Image(systemName: "chevron.up.chevron.down").font(.system(size: 11)) }.padding(.horizontal, 16).frame(height: 50).background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Себестоимость").font(Theme.font(14)).foregroundStyle(Theme.muted)
                        Option(selected: mode == "avg", title: "Средняя по складу", sub: "старые и новые вещи вместе", trailing: nil) { mode = "avg" }
                        Option(selected: mode == "set", title: "Новая цена", sub: "себестоимость = цена этой партии", trailing: nil) { mode = "set" }
                        Option(selected: mode == "keep", title: "Не менять", sub: "оставить текущую себестоимость", trailing: nil) { mode = "keep" }
                    }
                    Field(label: "Комментарий — необязательно", text: $note, placeholder: "Например, партия от швейного цеха «Нить»")
                    HStack(spacing: 8) { AdminStat(title: "Штук", value: "\(total)"); AdminStat(title: "Сумма закупки", value: Fmt.rub(total * u)); AdminStat(title: "Себестоимость станет", value: c1 > 0 ? Fmt.rub(c1) : "—") }
                    ErrorText(text: error)
                    PrimaryButton(title: total > 0 ? "Принять на склад · \(total) шт." : "Принять на склад", busy: busy) { Task { await go(p["id"].str, lines, cats) } }
                    let recent = Array(admin.data["receipts"].array.reversed().prefix(5))
                    if !recent.isEmpty {
                        Text("Последние приходы").font(Theme.font(15, .medium)).padding(.top, 10)
                        ForEach(recent.indices, id: \.self) { i in
                            let r = recent[i]
                            HStack {
                                VStack(alignment: .leading, spacing: 2) { Text(r["name"].str).font(Theme.font(14)); Text(r["date"].str + " · \(r["qty"].int ?? 0) шт." + ((r["total"].int ?? 0) > 0 ? " · " + Fmt.rub(r["total"].int ?? 0) : "")).font(Theme.font(12)).foregroundStyle(Theme.muted) }
                                Spacer()
                                Button("Отменить") { Task { await cancel(r["id"].str) } }.font(Theme.font(13)).foregroundStyle(Theme.danger)
                            }.padding(.vertical, 6)
                        }
                    }
                }.padding(20)
            }
            .navigationTitle("Приход товара").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
            .onAppear { if pid.isEmpty { pid = productId.isEmpty ? (prods.first?["id"].str ?? "") : productId }; if cat.isEmpty { cat = cats.first?["id"].str ?? "" } }
        }
    }
    private func go(_ pid: String, _ lines: [[String: Any]], _ cats: [JSON]) async {
        error = nil
        if lines.isEmpty { error = "Укажите, сколько штук пришло"; return }
        if cats.isEmpty && (Int(unit) ?? 0) > 0 { error = "В «Финансах» нет категории закупки"; return }
        busy = true; defer { busy = false }
        do {
            let r = try await AdminAPI.post("finance/receive", ["productId": pid, "date": ISO.ymd.string(from: date), "lines": lines, "unitCost": unit, "categoryId": cat, "costMode": mode, "note": note])
            await AdminAPI.reload(); Haptic.success()
            Toast.shared.show("Принято на склад: \(r["receipt"]["qty"].int ?? 0) шт." + ((r["receipt"]["total"].int ?? 0) > 0 ? ", закупка \(Fmt.rub(r["receipt"]["total"].int ?? 0)) записана в «Финансы»" : ""))
            dismiss()
        } catch { self.error = error.userMessage }
    }
    private func cancel(_ id: String) async {
        do { _ = try await API.shared.raw("DELETE", "admin/finance/receive/\(id)"); await AdminAPI.reload(); Toast.shared.show("Приход отменён: остатки и закупка возвращены") }
        catch { self.error = error.userMessage }
    }
}

/// Массовые изменения выбранных товаров: цена, ±%, скидка, показать/скрыть, удалить; остатки в Excel
struct ProductsBulkView: View {
    @ObservedObject private var admin = Admin.shared
    @State private var picked = Set<String>()
    @State private var action = ""
    @State private var value = ""
    @State private var busy = false
    @State private var confirmDelete = false
    @State private var importing = false
    @State private var preview = JSON(nil)
    @State private var csvText = ""
    /// Выгруженный файл остатков. Сбрасывается, когда остатки или список товаров изменились здесь же (загрузка файла,
    /// удаление): иначе «Поделиться» отдал бы прежний файл (аудит K, K-M2). Массовые изменения его не сбрасывают —
    /// цена, скидка и видимость в файл не входят (товар, цвет, размер, артикул, остаток, ID)
    @State private var exportURL: URL?
    /// Растёт при каждом изменении, сбрасывающем файл: выгрузка, начатая до изменения, свой файл не ставит
    @State private var changes = 0
    private static let actions = [("price", "Цена, ₽", "Новая цена"), ("percent", "Цена ±%", "Например, 10 или −10"), ("discount", "Скидка %", "От 1 до 94"), ("nodiscount", "Убрать скидку", ""), ("show", "Показать на сайте", ""), ("hide", "Скрыть с сайта", "")]
    var body: some View {
        let prods = admin.data["products"].array
        List {
            Section("Остатки в Excel") {
                Text("Выгрузите остатки, поменяйте числа в Excel и загрузите файл обратно — сначала покажем, что изменится.").font(Theme.font(13)).foregroundStyle(Theme.muted)
                if let u = exportURL { ShareLink(item: u) { Label("Поделиться файлом остатков", systemImage: "square.and.arrow.up") } }
                else { Button { Task { await export() } } label: { Label("Выгрузить остатки", systemImage: "arrow.down.doc") } }
                Button { importing = true } label: { Label("Загрузить остатки", systemImage: "arrow.up.doc") }
                if preview.exists {
                    let ch = preview["changes"].array, er = preview["errors"].array
                    Text(ch.isEmpty ? "Изменений нет" : "Изменится: \(ch.count)").font(Theme.font(14, .medium))
                    ForEach(Array(ch.prefix(30).enumerated()), id: \.offset) { _, c in Text("\(c["name"].str) · \(c["color"].str) · \(c["size"].str): \(c["from"].int ?? 0) → \(c["to"].int ?? 0)").font(Theme.font(12.5)) }
                    ForEach(Array(er.prefix(10).enumerated()), id: \.offset) { _, e in Text(e.str).font(Theme.font(12.5)).foregroundStyle(Theme.danger) }
                    if !ch.isEmpty { Button("Применить изменения") { Task { await applyCsv() } }.font(Theme.font(15, .medium)) }
                }
            }
            Section("Выбрано: \(picked.count)") {
                Button(picked.count == prods.count ? "Снять выбор" : "Выбрать все (\(prods.count))") { picked = picked.count == prods.count ? [] : Set(prods.map { $0["id"].str }) }
                Picker("Что сделать", selection: $action) { Text("Изменить…").tag(""); ForEach(ProductsBulkView.actions, id: \.0) { Text($0.1).tag($0.0) } }
                if let a = ProductsBulkView.actions.first(where: { $0.0 == action }), !a.2.isEmpty { TextField(a.2, text: $value).keyboardType(.numbersAndPunctuation) }
                Button("Применить к выбранным") { Task { await bulk() } }.disabled(picked.isEmpty || action.isEmpty || busy)
                Button("Удалить выбранные", role: .destructive) { confirmDelete = true }.disabled(picked.isEmpty)
            }
            Section {
                ForEach(Array(prods.enumerated()), id: \.offset) { _, p in
                    Button { let id = p["id"].str; if picked.contains(id) { picked.remove(id) } else { picked.insert(id) } } label: {
                        HStack { Image(systemName: picked.contains(p["id"].str) ? "checkmark.circle.fill" : "circle").foregroundStyle(Theme.ink); Text(p["name"].str).foregroundStyle(Theme.text); Spacer(); Text(Fmt.rub(p["price"].int ?? 0)).foregroundStyle(Theme.muted) }.font(Theme.font(14.5))
                    }
                }
            }
        }
        .navigationTitle("Массовые изменения").navigationBarTitleDisplayMode(.inline)
        .task { if !admin.data.exists { await admin.load() } }   // открыт сразу по ссылке — минуя список товаров (этап K.2)
        .confirmationDialog("Удалить \(picked.count) \(Fmt.plural(picked.count, "товар", "товара", "товаров"))?", isPresented: $confirmDelete, titleVisibility: .visible) { Button("Удалить", role: .destructive) { Task { await deleteMany() } } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .plainText, .text]) { r in Task { await importCsv(r) } }
    }
    private func bulk() async {
        busy = true; defer { busy = false }
        let v = Double(value.replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: ",", with: ".")) ?? 0
        do { let r = try await AdminAPI.post("products/bulk", ["ids": Array(picked), "action": action, "value": v]); await AdminAPI.reload(); Toast.shared.show(notifyMsg("Изменено: \(r["changed"].int ?? 0)", r["notify"])) }
        catch { Toast.shared.show(error.userMessage) }
    }
    private func deleteMany() async {
        do { let r = try await AdminAPI.post("products/delete-many", ["ids": Array(picked)]); picked = []; exportURL = nil; changes += 1; await AdminAPI.reload(); Toast.shared.show("Удалено: \(r["deleted"].int ?? 0)") }
        catch { Toast.shared.show(error.userMessage) }
    }
    private func export() async {
        let n = changes
        do {
            let d = try await API.shared.raw("GET", "admin/products/stock.csv")
            guard n == changes else { return }   // пока файл шёл, остатки или товары изменились — нужен новый
            let u = FileManager.default.temporaryDirectory.appendingPathComponent("ostatki.csv"); try d.write(to: u); exportURL = u
        } catch { Toast.shared.show(error.userMessage) }
    }
    /// Файл, который не открылся (не скачан из iCloud, нет доступа), раньше молча пропускался (аудит Q-B1).
    /// Текст нового файла заменяет прежний только вместе с его проверкой: иначе при сбое проверки на экране
    /// остался бы список изменений прежнего файла, а «Применить» отправил бы новый, которого никто не видел (ревью этапа C)
    private func importCsv(_ r: Result<URL, Error>) async {
        do {
            let u = try r.get()
            let ok = u.startAccessingSecurityScopedResource(); defer { if ok { u.stopAccessingSecurityScopedResource() } }
            let d = try Data(contentsOf: u)
            let text = String(data: d, encoding: .utf8) ?? String(data: d, encoding: .windowsCP1251) ?? ""
            preview = try await AdminAPI.post("products/stock", ["csv": text, "dry": true])
            csvText = text
        } catch { Toast.shared.show(error.userMessage) }
    }
    private func applyCsv() async {
        do { let r = try await AdminAPI.post("products/stock", ["csv": csvText]); preview = JSON(nil); exportURL = nil; changes += 1; await AdminAPI.reload(); Toast.shared.show(notifyMsg("Остатки обновлены: \(r["changed"].int ?? 0)", r["notify"])) }
        catch { Toast.shared.show(error.userMessage) }
    }
}
