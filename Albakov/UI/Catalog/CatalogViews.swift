import SwiftUI

// Каталог: разделы, сетка товаров с сортировкой и фильтром по размеру, поиск, избранное
struct CatalogRootView: View {
    @EnvironmentObject private var shop: Shop
    @EnvironmentObject private var router: Router
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                GenderSwitch()
                Button { router.push(.search, on: .catalog) } label: {
                    HStack(spacing: 10) { Image(systemName: "magnifyingglass"); Text("Поиск по каталогу").font(Theme.font(15)); Spacer() }
                        .foregroundStyle(Theme.muted).padding(.horizontal, 16).frame(height: 48)
                        .background(Capsule().fill(Theme.surface))
                }.padding(Theme.gutter)
                VStack(spacing: 0) {
                    row("Вся коллекция", count: shop.visibleProducts.count) { router.push(.catalog(cat: nil, tag: nil, sale: false), on: .catalog) }
                    if shop.visibleProducts.contains(where: { $0.tags.contains("new") }) { row("Новинки", count: shop.visibleProducts.filter { $0.tags.contains("new") }.count) { router.push(.catalog(cat: nil, tag: "new", sale: false), on: .catalog) } }
                    ForEach(shop.visibleCategories) { c in
                        row(c.name, count: shop.visibleProducts.filter { $0.categoryId == c.id }.count) { router.push(.catalog(cat: c.id, tag: nil, sale: false), on: .catalog) }
                    }
                    if !shop.saleProducts.isEmpty { row("Скидки", count: shop.saleProducts.count, accent: true) { router.push(.catalog(cat: nil, tag: nil, sale: true), on: .catalog) } }
                }
                .padding(.horizontal, Theme.gutter)
            }
        }
        .navigationTitle("Каталог")
        .refreshable { await shop.load() }
    }
    private func row(_ title: String, count: Int, accent: Bool = false, _ go: @escaping () -> Void) -> some View {
        Button(action: go) {
            HStack {
                Text(title).font(Theme.font(19, .light)).foregroundStyle(accent ? Theme.danger : Theme.text)
                Spacer()
                Text("\(count)").font(Theme.font(13)).foregroundStyle(Theme.dim)
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Theme.dim)
            }
            .padding(.vertical, 18).overlay(alignment: .bottom) { Divider1() }
        }
    }
}

struct CatalogView: View {
    let cat: String?, tag: String?, sale: Bool
    @EnvironmentObject private var shop: Shop
    @State private var sort = "default"
    @State private var size: String?
    @State private var inStock = false

    private var title: String {
        if sale { return "Скидки" }
        if tag == "new" { return "Новинки" }
        if tag == "hit" { return "Хиты продаж" }
        return cat.flatMap { shop.category($0)?.name } ?? "Вся коллекция"
    }
    private var base: [Product] {
        shop.visibleProducts.filter { p in
            (cat == nil || p.categoryId == shop.category(cat!)?.id) && (tag == nil || p.tags.contains(tag!) || (tag == "hit" && shop.hitIds.contains(p.id))) && (!sale || shop.price(p).oldPrice > 0)
        }
    }
    private var sizes: [String] {
        var seen: [String] = []
        for p in base { for c in p.colors { for s in c.sizes where !seen.contains(s.size) { seen.append(s.size) } } }
        return seen
    }
    private var list: [Product] {
        var l = base.filter { p in
            (size == nil || p.colors.contains { $0.sizes.contains { $0.size == size && $0.stock > 0 } }) && (!inStock || p.stock > 0)
        }
        switch sort {
        case "cheap": l.sort { shop.price($0).price < shop.price($1).price }
        case "expensive": l.sort { shop.price($0).price > shop.price($1).price }
        case "new": l.sort { $0.createdAt > $1.createdAt }
        default: l.sort { ($0.available ? 0 : 1) < ($1.available ? 0 : 1) }
        }
        return l
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Menu {
                            Picker("Сортировка", selection: $sort) {
                                Text("По умолчанию").tag("default"); Text("Сначала новые").tag("new")
                                Text("Сначала дешевле").tag("cheap"); Text("Сначала дороже").tag("expensive")
                            }
                        } label: { Chip(text: sort == "default" ? "Сортировка" : sortName, icon: "arrow.up.arrow.down", on: sort != "default") }
                        Chip(text: "В наличии", on: inStock).onTapGesture { withAnimation { inStock.toggle() } }
                        ForEach(sizes, id: \.self) { s in
                            Chip(text: s, on: size == s).onTapGesture { withAnimation { size = size == s ? nil : s } }
                        }
                    }.padding(.horizontal, Theme.gutter)
                }
                Text("\(list.count) \(Fmt.plural(list.count, "товар", "товара", "товаров"))").font(Theme.font(13)).foregroundStyle(Theme.dim).padding(.horizontal, Theme.gutter)
                if list.isEmpty {
                    EmptyState(icon: "square.grid.2x2", title: "Ничего не нашлось", text: "Попробуйте другой размер или уберите фильтры")
                } else {
                    ProductGrid(products: list)
                }
            }.padding(.vertical, 12)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
    }
    private var sortName: String { ["new": "Сначала новые", "cheap": "Сначала дешевле", "expensive": "Сначала дороже"][sort] ?? "Сортировка" }
}

struct ProductGrid: View {
    let products: [Product]
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 22) {
            ForEach(products) { ProductCard(product: $0) }
        }.padding(.horizontal, Theme.gutter)
    }
}

struct Chip: View {
    let text: String
    var icon: String? = nil
    var on = false
    var body: some View {
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon).font(.system(size: 11)) }
            Text(text).font(Theme.font(13.5, on ? .medium : .regular))
        }
        .foregroundStyle(on ? .white : Theme.text)
        .padding(.horizontal, 14).frame(height: 36)
        .background(Capsule().fill(on ? Theme.ink : .white))
        .overlay(Capsule().strokeBorder(on ? Theme.ink : Theme.line))
    }
}

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
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                    TextField("Пальто, футболка, чёрный…", text: $q).font(Theme.font(16)).focused($focus).submitLabel(.search)
                    if !q.isEmpty { Button { q = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.dim) } }
                }
                .padding(.horizontal, 16).frame(height: 50).background(Capsule().fill(Theme.surface)).padding(.horizontal, Theme.gutter)
                if q.count >= 2 && results.isEmpty {
                    EmptyState(icon: "magnifyingglass", title: "Ничего не нашлось", text: "Проверьте написание или поищите по-другому")
                } else { ProductGrid(products: results) }
            }.padding(.vertical, 12)
        }
        .navigationTitle("Поиск").navigationBarTitleDisplayMode(.inline)
        .onAppear { focus = true }
    }
}

struct FavoritesView: View {
    @EnvironmentObject private var shop: Shop
    @EnvironmentObject private var router: Router
    var body: some View {
        let list = shop.favorites.compactMap { shop.product($0) }
        ScrollView {
            if list.isEmpty {
                EmptyState(icon: "heart", title: "Пока пусто", text: "Нажимайте на сердечко у товаров — они сохранятся здесь", button: "В каталог") { router.reset(.catalog) }.padding(.top, 60)
            } else { ProductGrid(products: list).padding(.vertical, 12) }
        }
        .navigationTitle("Избранное")
    }
}

// Страница из панели: доставка, возврат, документы
struct PageView: View {
    let slug: String
    @EnvironmentObject private var shop: Shop
    var body: some View {
        ScrollView {
            if let p = shop.page(slug) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(p.body.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, par in
                        let t = par.trimmingCharacters(in: .whitespacesAndNewlines)
                        if t.hasPrefix("## ") { Text(t.dropFirst(3)).font(Theme.font(20, .medium)).padding(.top, 8) }
                        else if t.hasPrefix("# ") { Text(t.dropFirst(2)).font(Theme.font(24, .light)) }
                        else if !t.isEmpty { Text((try? AttributedString(markdown: t, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(t)).font(Theme.font(15)).foregroundStyle(Theme.text).lineSpacing(4) }
                    }
                }.padding(Theme.gutter)
                .navigationTitle(p.title)
            } else { EmptyState(icon: "doc", title: "Страница не найдена", text: "") }
        }
    }
}

struct SizesView: View {
    @EnvironmentObject private var shop: Shop
    var body: some View {
        ScrollView { VStack(spacing: 28) { ForEach(shop.sizeCharts) { SizeChartTable(chart: $0) } }.padding(Theme.gutter) }
            .navigationTitle("Таблица размеров")
    }
}

struct SizeChartTable: View {
    let chart: SizeChart
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(chart.name).font(Theme.font(18, .medium))
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 0) {
                    GridRow { ForEach(chart.columns, id: \.self) { Text($0).font(Theme.font(12, .medium)).foregroundStyle(Theme.muted).padding(.vertical, 10) } }
                    ForEach(Array(chart.rows.enumerated()), id: \.offset) { _, r in
                        Divider1().gridCellUnsizedAxes(.horizontal)
                        GridRow { ForEach(Array(r.enumerated()), id: \.offset) { i, v in Text(v).font(Theme.font(14, i == 0 ? .medium : .regular)).padding(.vertical, 10) } }
                    }
                }
            }
            if !chart.note.isEmpty { Text(chart.note).font(Theme.font(13)).foregroundStyle(Theme.muted) }
        }
    }
}
