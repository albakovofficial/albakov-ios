import SwiftUI

// Каталог как на сайте: «хлебные крошки», плашка раздела, заголовок с точкой, число товаров,
// «Фильтры» и сортировка, выбранные фильтры капсулами и сетка карточек.

struct CatalogRootView: View {
    var body: some View { CatalogPage(cat: nil, tag: nil, sale: false, root: true) }
}

struct CatalogView: View {
    let cat: String?, tag: String?, sale: Bool
    var body: some View { CatalogPage(cat: cat, tag: tag, sale: sale, root: false) }
}

struct CatalogFilter: Equatable {
    var cat: String? = nil
    var tag: String? = nil
    var sale = false
    var sizes: Set<String> = []
    var colors: Set<String> = []
    var min = ""
    var max = ""
    var q = ""
}

struct CatalogPage: View {
    let root: Bool
    @EnvironmentObject private var shop: Shop
    @EnvironmentObject private var router: Router
    @State private var f: CatalogFilter
    @State private var sort = "popular"
    @State private var showFilters = false

    init(cat: String?, tag: String?, sale: Bool, root: Bool, q: String = "") {
        self.root = root
        _f = State(initialValue: CatalogFilter(cat: cat, tag: tag, sale: sale, q: q))
    }

    private var category: Category? { f.cat.flatMap { shop.category($0) } }
    private var title: String {
        if !f.q.isEmpty { return "Поиск: " + f.q }
        if let c = category { return c.name }
        if f.tag == "new" { return "Новинки" }
        if f.tag == "hit" { return "Хиты продаж" }
        if f.sale { return "Акции" }
        return "Каталог"
    }
    private var list: [Product] {
        let words = f.q.lowercased().split(separator: " ").map(String.init)
        var l = shop.visibleProducts.filter { p in
            let pr = shop.price(p).price
            return (category == nil || p.categoryId == category!.id)
                && (f.tag == nil || p.tags.contains(f.tag!) || (f.tag == "hit" && shop.hitIds.contains(p.id)))
                && (!f.sale || shop.price(p).oldPrice > 0)
                && (f.sizes.isEmpty || p.colors.contains { c in c.sizes.contains { f.sizes.contains($0.size) && $0.stock > 0 } })
                && (f.colors.isEmpty || p.colors.contains { f.colors.contains($0.name.lowercased()) })
                && (Int(f.min).map { pr >= $0 } ?? true) && (Int(f.max).map { pr <= $0 } ?? true)
                && (words.isEmpty || words.allSatisfy { w in (p.name + " " + (shop.category(p.categoryId)?.name ?? "") + " " + p.colors.map(\.name).joined(separator: " ") + " " + p.sku).lowercased().contains(w) })
        }
        if f.tag == "hit" && sort == "popular" { l = shop.hits.filter { h in l.contains(h) } + l.filter { !shop.hits.contains($0) } }
        switch sort {
        case "new": l.sort { $0.createdAt > $1.createdAt }
        case "cheap": l.sort { shop.price($0).price < shop.price($1).price }
        case "expensive": l.sort { shop.price($0).price > shop.price($1).price }
        default: break
        }
        return l.filter { $0.stock > 0 || $0.preorderLeft > 0 } + l.filter { !($0.stock > 0 || $0.preorderLeft > 0) }
    }
    private static let sorts = [("popular", "По умолчанию"), ("new", "Сначала новые"), ("cheap", "Сначала дешевле"), ("expensive", "Сначала дороже")]

    var body: some View {
        let items = list
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Crumbs(items: [("Главная", { router.reset(.home) }), ("Каталог", root ? nil : { router.reset(.catalog) })] + (category.map { [($0.name, nil)] } ?? []))
                    .padding(.top, 18)
                Eyebrow(text: shop.gender == "women" ? "Женщинам" : shop.gender == "men" ? "Мужчинам" : "Вся коллекция").padding(.horizontal, Theme.gutter).padding(.top, 18)
                DotTitle(text: title, size: 32).padding(.horizontal, Theme.gutter).padding(.top, 14)
                Text("\(items.count) \(Fmt.plural(items.count, "товар", "товара", "товаров"))").font(Theme.font(14)).foregroundStyle(Theme.muted)
                    .padding(.horizontal, Theme.gutter).padding(.top, 18)
                HStack(spacing: 8) {
                    Button { showFilters = true } label: {
                        Text("Фильтры" + (activeCount > 0 ? " · \(activeCount)" : "")).font(Theme.font(14, .medium)).kerning(0.5).foregroundStyle(Theme.text)
                            .padding(.horizontal, 18).frame(height: 40).background(Capsule().fill(.white.opacity(0.7))).overlay(Capsule().strokeBorder(Theme.lineStrong))
                    }
                    Menu {
                        Picker("Сортировка", selection: $sort) { ForEach(CatalogPage.sorts, id: \.0) { Text($0.1).tag($0.0) } }
                    } label: {
                        HStack(spacing: 14) { Text(CatalogPage.sorts.first { $0.0 == sort }?.1 ?? "").font(Theme.font(15)); Image(systemName: "chevron.down").font(.system(size: 11, weight: .medium)) }
                            .foregroundStyle(Theme.text).padding(.horizontal, 14).frame(height: 40)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
                    }
                }.padding(.horizontal, Theme.gutter).padding(.top, 16)
                if !pills.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(pills.enumerated()), id: \.offset) { _, p in
                                Button { withAnimation { p.1() } } label: {
                                    HStack(spacing: 8) { Text(p.0).font(Theme.font(13.5)); Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)) }
                                        .foregroundStyle(Theme.text).padding(.horizontal, 12).frame(height: 34).background(Capsule().fill(.white)).overlay(Capsule().strokeBorder(Theme.lineStrong))
                                }
                            }
                        }.padding(.horizontal, Theme.gutter)
                    }.padding(.top, 14)
                }
                Group {
                    if items.isEmpty {
                        EmptyState(icon: "square.grid.2x2", title: "Ничего не нашлось", text: "Попробуйте другой размер или уберите фильтры", button: "Сбросить фильтры") { withAnimation { f = CatalogFilter() } }
                    } else {
                        ProductGrid(products: items, tab: router.tab, bag: true)
                    }
                }.padding(.top, 22).padding(.bottom, 40)
            }
        }
        .navigationTitle(root ? "" : title).navigationBarTitleDisplayMode(.inline)
        .refreshable { await shop.load() }
        .sheet(isPresented: $showFilters) { FilterSheet(f: $f, count: items.count).presentationDetents([.large]) }
    }

    private var activeCount: Int { (f.cat != nil ? 1 : 0) + f.sizes.count + f.colors.count + (f.min.isEmpty && f.max.isEmpty ? 0 : 1) + (f.sale ? 1 : 0) + (f.tag != nil ? 1 : 0) }
    private var pills: [(String, () -> Void)] {
        var out: [(String, () -> Void)] = []
        if let c = category { out.append((c.name, { f.cat = nil })) }
        if f.tag == "new" { out.append(("Новинки", { f.tag = nil })) }
        if f.tag == "hit" { out.append(("Хиты продаж", { f.tag = nil })) }
        if f.sale { out.append(("Со скидкой", { f.sale = false })) }
        for s in f.sizes.sorted() { out.append(("Размер " + s, { f.sizes.remove(s) })) }
        for c in f.colors.sorted() { out.append((c.prefix(1).uppercased() + c.dropFirst(), { f.colors.remove(c) })) }
        if !f.min.isEmpty || !f.max.isEmpty { out.append(([f.min.isEmpty ? "" : "от " + f.min, f.max.isEmpty ? "" : "до " + f.max].filter { !$0.isEmpty }.joined(separator: " ") + " ₽", { f.min = ""; f.max = "" })) }
        if !f.q.isEmpty { out.append(("«" + f.q + "»", { f.q = "" })) }
        return out
    }
}

/// Фильтры: раздел, категория, размер (буквенный, цифровой, другие), цвет, цена, скидки и новинки
struct FilterSheet: View {
    @Binding var f: CatalogFilter
    let count: Int
    @EnvironmentObject private var shop: Shop
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    group("Раздел") {
                        item("Вся коллекция", shop.products.count, on: shop.gender == nil) { shop.gender = nil }
                        ForEach([("women", "Женщинам"), ("men", "Мужчинам")], id: \.0) { g in
                            item(g.1, shop.products.filter { $0.forGender(g.0) }.count, on: shop.gender == g.0) { shop.gender = g.0 }
                        }
                    }
                    group("Категория") {
                        item("Все товары", shop.visibleProducts.count, on: f.cat == nil) { f.cat = nil }
                        ForEach(shop.visibleCategories) { c in
                            item(c.name, shop.visibleProducts.filter { $0.categoryId == c.id }.count, on: f.cat == c.id || f.cat == c.slug) { f.cat = c.id }
                        }
                    }
                    let groups = sizeGroups
                    if !groups.isEmpty {
                        group("Размер") {
                            ForEach(groups, id: \.0) { g in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(g.0).font(Theme.font(12.5)).foregroundStyle(Theme.muted)
                                    FlowRow(spacing: 8) {
                                        ForEach(g.1, id: \.self) { s in Chip(title: s, on: f.sizes.contains(s), height: 40) { if f.sizes.contains(s) { f.sizes.remove(s) } else { f.sizes.insert(s) } } }
                                    }
                                }
                            }
                        }
                    }
                    let cs = colors
                    if cs.count > 1 {
                        group("Цвет") {
                            FlowRow(spacing: 8) {
                                ForEach(cs, id: \.name) { c in
                                    let k = c.name.lowercased(), on = f.colors.contains(k)
                                    Button { if on { f.colors.remove(k) } else { f.colors.insert(k) } } label: {
                                        HStack(spacing: 8) { Circle().fill(Color(hex: c.hex.isEmpty ? "#cccccc" : c.hex)).frame(width: 16, height: 16).overlay(Circle().strokeBorder(Theme.ink.opacity(0.15))); Text(c.name).font(Theme.font(13.5)) }
                                            .foregroundStyle(Theme.text).padding(.horizontal, 12).frame(height: 38)
                                            .background(Capsule().fill(on ? .white : Theme.surface)).overlay(Capsule().strokeBorder(on ? Theme.ink : .clear))
                                    }
                                }
                            }
                        }
                    }
                    group("Цена, ₽") {
                        HStack(spacing: 10) { Field(label: "", text: $f.min, placeholder: "от", keyboard: .numberPad); Field(label: "", text: $f.max, placeholder: "до", keyboard: .numberPad) }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Только со скидкой", isOn: $f.sale).font(Theme.font(15)).tint(Theme.ink)
                        Toggle("Только новинки", isOn: Binding(get: { f.tag == "new" }, set: { f.tag = $0 ? "new" : nil })).font(Theme.font(15)).tint(Theme.ink)
                    }
                    Button { f = CatalogFilter() } label: { Text("Сбросить фильтры").font(Theme.font(14)).foregroundStyle(Theme.muted).underline() }
                }.padding(Theme.gutter).padding(.bottom, 90)
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(title: "Показать \(count) \(Fmt.plural(count, "товар", "товара", "товаров"))") { dismiss() }
                    .padding(.horizontal, Theme.gutter).padding(.vertical, 10).background(.ultraThinMaterial)
            }
            .navigationTitle("Фильтры").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 14, weight: .light)) } } }
        }
    }
    private var colors: [PColor] {
        var out: [PColor] = []
        for p in shop.visibleProducts { for c in p.colors where !out.contains(where: { $0.name.lowercased() == c.name.lowercased() }) { out.append(c) } }
        return out
    }
    private var sizeGroups: [(String, [String])] {
        let order = ["XXS", "XS", "S", "M", "L", "XL", "XXL", "2XL", "3XL", "XXXL", "4XL"]
        var all: [String] = []
        for p in shop.visibleProducts { for c in p.colors { for s in c.sizes where !all.contains(s.size) { all.append(s.size) } } }
        all.sort { (order.firstIndex(of: $0.uppercased()) ?? 99, Double($0) ?? 999, $0) < (order.firstIndex(of: $1.uppercased()) ?? 99, Double($1) ?? 999, $1) }
        let letter = all.filter { $0.range(of: #"^\d*X*[SML]$"#, options: [.regularExpression, .caseInsensitive]) != nil }
        let digit = all.filter { $0.range(of: #"^\d+([.,/-]\d+)?$"#, options: .regularExpression) != nil }
        let other = all.filter { !letter.contains($0) && !digit.contains($0) }
        return [("Буквенный", letter), ("Цифровой", digit), ("Другие", other)].filter { !$0.1.isEmpty }
    }
    private func group<C: View>(_ t: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) { Text(t).font(Theme.font(16, .medium)); c() }
    }
    private func item(_ t: String, _ n: Int, on: Bool, _ a: @escaping () -> Void) -> some View {
        Button { withAnimation(.easeOut(duration: 0.15)) { a() } } label: {
            HStack {
                Rectangle().fill(on ? Theme.accent : .clear).frame(width: 2, height: 18)
                Text(t).font(Theme.font(15)); Spacer(); Text("\(n)").font(Theme.font(13)).foregroundStyle(Theme.dim)
            }
            .foregroundStyle(Theme.text).padding(.horizontal, 10).frame(height: 42)
            .background(RoundedRectangle(cornerRadius: 12).fill(on ? Theme.surface : .clear))
        }
    }
}

/// Поиск как на сайте: заголовок «Поиск», поле «Название, цвет или артикул», ниже — найденные вещи
struct SearchView: View {
    @EnvironmentObject private var shop: Shop
    @State private var q = ""
    @FocusState private var focus: Bool
    private var results: [Product] {
        let t = q.lowercased().trimmingCharacters(in: .whitespaces)
        guard t.count >= 2 else { return [] }
        let words = t.split(separator: " ").map(String.init)
        return shop.products.filter { p in
            let hay = (p.name + " " + (shop.category(p.categoryId)?.name ?? "") + " " + p.colors.map(\.name).joined(separator: " ") + " " + p.sku).lowercased()
            return words.allSatisfy { hay.contains($0) }
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DotTitle(text: "Поиск", size: 34, dot: false).padding(.horizontal, Theme.gutter)
                HStack(spacing: 10) {
                    TextField("Название, цвет или артикул", text: $q).font(Theme.font(16)).focused($focus).submitLabel(.search)
                    if !q.isEmpty { Button { q = "" } label: { Image(systemName: "xmark").font(.system(size: 13, weight: .light)).foregroundStyle(Theme.muted) } }
                }
                .padding(.horizontal, 16).frame(height: 52)
                .background(RoundedRectangle(cornerRadius: 14).fill(.white))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.ink, lineWidth: 1))
                .shadow(color: Theme.accent.opacity(0.12), radius: 0, x: 0, y: 0).padding(.horizontal, Theme.gutter)
                if q.count >= 2 && results.isEmpty {
                    EmptyState(icon: "magnifyingglass", title: "Ничего не нашлось", text: "Проверьте написание или поищите по-другому")
                } else if !results.isEmpty {
                    Text("Найдено: \(results.count)").font(Theme.font(14)).foregroundStyle(Theme.muted).padding(.horizontal, Theme.gutter)
                    ProductGrid(products: results, tab: nil, bag: true)
                }
            }.padding(.vertical, 18)
        }
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
        .onAppear { focus = true }
    }
}

/// Избранное: «Сохранённые вещи», заголовок, сетка или пустой экран с сердцем
struct FavoritesView: View {
    @EnvironmentObject private var shop: Shop
    @EnvironmentObject private var router: Router
    var body: some View {
        let list = shop.favorites.compactMap { id in shop.products.first { $0.id == id } }
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Eyebrow(text: "Сохранённые вещи").padding(.horizontal, Theme.gutter)
                DotTitle(text: "Избранное", size: 34).padding(.horizontal, Theme.gutter)
                if list.isEmpty {
                    EmptyState(icon: "heart", title: "Здесь пока пусто", text: "Нажимайте на сердечко у понравившихся вещей — они соберутся здесь, и к ним легко вернуться.", button: "Перейти в каталог") { router.reset(.catalog) }
                } else {
                    Text("\(list.count) \(Fmt.plural(list.count, "вещь", "вещи", "вещей"))").font(Theme.font(14)).foregroundStyle(Theme.muted).padding(.horizontal, Theme.gutter)
                    ProductGrid(products: list, tab: .favorites, bag: true)
                }
            }.padding(.vertical, 22).padding(.bottom, 40)
        }
    }
}

// Страница из панели: доставка, возврат, о бренде, документы — заголовок с точкой и текст
struct PageView: View {
    let slug: String
    @EnvironmentObject private var shop: Shop
    var body: some View {
        ScrollView {
            if let p = shop.page(slug) {
                VStack(alignment: .leading, spacing: 16) {
                    Eyebrow(text: p.group == "legal" ? "Документы" : shop.settings.storeName)
                    DotTitle(text: p.title, size: 32)
                    MarkdownText(text: p.body).padding(.top, 6)
                }.padding(Theme.gutter).padding(.bottom, 40)
            } else { EmptyState(icon: "doc", title: "Страница не найдена", text: "").padding(.top, 40) }
        }
        .navigationTitle(shop.page(slug)?.title ?? "").navigationBarTitleDisplayMode(.inline)
    }
}

/// Текст страницы: заголовки «#», «##», списки «- » и выделение **жирным**, [ссылки](…)
struct MarkdownText: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(text.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, par in
                let t = par.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.hasPrefix("## ") { Text(t.dropFirst(3)).font(Theme.font(21, .light)).padding(.top, 10) }
                else if t.hasPrefix("# ") { Text(t.dropFirst(2)).font(Theme.font(26, .light)).padding(.top, 10) }
                else if t.hasPrefix("- ") || t.hasPrefix("• ") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(t.components(separatedBy: "\n").enumerated()), id: \.offset) { _, l in
                            HStack(alignment: .top, spacing: 10) {
                                Circle().fill(Theme.accentGradient).frame(width: 5, height: 5).padding(.top, 9)
                                inline(String(l.dropFirst(2)))
                            }
                        }
                    }
                } else if !t.isEmpty { inline(t) }
            }
        }
    }
    private func inline(_ s: String) -> some View {
        Text((try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s))
            .font(Theme.font(15.5)).foregroundStyle(Theme.muted).lineSpacing(6).tint(Theme.text)
    }
}

/// «Таблица размеров» как на сайте: заголовок, таблицы в мягких карточках
struct SizesView: View {
    @EnvironmentObject private var shop: Shop
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Eyebrow(text: "Как выбрать размер")
                DotTitle(text: "Таблица размеров", size: 32)
                ForEach(shop.sizeCharts) { SizeChartTable(chart: $0) }
            }.padding(Theme.gutter).padding(.bottom, 40)
        }
        .navigationTitle("Таблица размеров").navigationBarTitleDisplayMode(.inline)
    }
}

struct SizeChartTable: View {
    let chart: SizeChart
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(chart.name).font(Theme.font(20, .light))
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 0) {
                    GridRow { ForEach(chart.columns, id: \.self) { Text($0).font(Theme.font(12.5)).foregroundStyle(Theme.muted).padding(.vertical, 10) } }
                    ForEach(Array(chart.rows.enumerated()), id: \.offset) { _, r in
                        Divider1().gridCellUnsizedAxes(.horizontal)
                        GridRow { ForEach(Array(r.enumerated()), id: \.offset) { i, v in Text(v).font(Theme.font(14.5, i == 0 ? .medium : .regular)).padding(.vertical, 11) } }
                    }
                }.padding(.horizontal, 16).padding(.vertical, 6)
            }
            .background(RoundedRectangle(cornerRadius: 18).fill(.white)).hairline(RoundedRectangle(cornerRadius: 18), 0.08)
            if !chart.note.isEmpty { Text(chart.note).font(Theme.font(13.5)).foregroundStyle(Theme.muted) }
        }
    }
}
