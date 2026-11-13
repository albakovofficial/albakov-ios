import SwiftUI

// Главная — как на сайте: слайдер, категории, новинки, хиты, «Вы недавно смотрели», бонусная программа,
// акция, «Ателье», «Сервис» и подвал. Какие блоки показывать и их тексты — из панели (настройки главной).
struct HomeView: View {
    @EnvironmentObject private var shop: Shop
    @EnvironmentObject private var router: Router
    private var h: JSON { shop.settings.raw["home"] }
    private func show(_ k: String) -> Bool { !h[k].exists || h[k].bool }
    private var gSub: String? { shop.gender.map { Sections.name($0).lowercased() } }

    var body: some View {
        if shop.closed(shop.gender) { SoonView() } else { content }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 0) {
                if !slides.isEmpty { HeroSlider(slides: slides) } else { hero }
                VStack(spacing: 56) {
                    if show("showCategories") && !shop.visibleCategories.isEmpty {
                        VStack(alignment: .leading, spacing: 22) {
                            SectionTitle(title: "Категории", action: "Весь каталог") { router.reset(.catalog) }
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .top, spacing: 12) {
                                    ForEach(shop.visibleCategories) { c in
                                        Button { router.push(.catalog(cat: c.id, tag: nil, sale: false), on: .home) } label: { CategoryCard(category: c) }.buttonStyle(Pressable())
                                    }
                                }.padding(.horizontal, Theme.gutter).padding(.bottom, 4)
                            }
                        }
                    }
                    if show("showNew"), !newList.isEmpty {
                        VStack(alignment: .leading, spacing: 22) {
                            SectionTitle(title: "Новинки", sub: gSub, action: "Смотреть все") { router.push(.catalog(cat: nil, tag: "new", sale: false), on: .home) }
                            ProductGrid(products: newList, tab: .home)
                        }
                    }
                    if show("showHits"), !shop.hits.isEmpty {
                        VStack(alignment: .leading, spacing: 22) {
                            SectionTitle(title: "Хиты продаж", sub: gSub, action: "Смотреть все") { router.push(.catalog(cat: nil, tag: "hit", sale: false), on: .home) }
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(alignment: .top, spacing: 10) { ForEach(shop.hits) { ProductCard(product: $0, tab: .home).frame(width: 166) } }.padding(.horizontal, Theme.gutter)
                            }
                        }
                    }
                    RecentRow(exceptId: nil, tab: .home)
                    if show("showBonus"), shop.settings.bonusEnabled, shop.settings.bonusPercent > 0 { BonusBand() }
                    if show("showSale"), let ap = shop.activePromos.first { DealBand(promo: ap) }
                    if show("showEditorial"), !h["editorialTitle"].str.isEmpty { AtelierBlock() }
                    if show("showBenefits"), !h["benefits"].array.isEmpty { BenefitsBlock() }
                    Footer()
                }
                .padding(.top, 44)
            }
            .padding(.bottom, 0)
        }
        .refreshable { await shop.load() }
    }

    // Раздел, срок, акция и «кому показывать»: слайд «Зарегистрироваться» вошедшему не показываем
    private var slides: [Slide] { shop.settings.slides.filter { $0.visible(gender: shop.gender, user: shop.user, promos: shop.promotions) }.map { $0.forUser(shop.user) } }
    // Если новинок мало — дополняем последними поступлениями, чтобы ряд не выглядел пустым (как на сайте)
    private var newList: [Product] {
        var n = shop.visibleProducts.filter { $0.tags.contains("new") }
        if n.count < 4 { n = Array((n + shop.visibleProducts.filter { p in !n.contains(p) }.sorted { $0.createdAt > $1.createdAt }).prefix(4)) }
        return Array(n.prefix(8))
    }
    // Без слайдов — обложка из настроек главной
    private var hero: some View {
        HeroSlider(slides: [Slide(JSON(["eyebrow": h["heroEyebrow"].str, "title": h["heroTitle"].str, "text": h["heroText"].str, "image": h["heroImage"].str,
                                        "btn1": ["label": h["heroCta"].str, "link": h["heroLink"].string ?? "#/catalog"]]))])
    }
}

// MARK: - Слайдер (вариант G, 1.0.1): фото в скруглённой карточке, внизу стеклянная панель — заголовок, текст,
// промокод, кнопка и стрелки; по верхнему краю панели полоса времени. Сверху на фото — надзаголовок и номер слайда.

struct HeroSlider: View {
    let slides: [Slide]
    var preview = false
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var shop: Shop
    @State private var page = 0
    /// Когда начался показ текущего слайда. Полоса времени считается от этой отметки на каждом кадре
    /// (TimelineView), а не анимацией: идёт ровно и не подтормаживает (1.0.1).
    @State private var started = Date()
    static let height: CGFloat = 330
    private var interval: Double { max(3, shop.settings.raw["slider"]["interval"].double ?? 7) }
    private var autoplay: Bool { !preview && !(shop.settings.raw["slider"]["autoplay"].exists && !shop.settings.raw["slider"]["autoplay"].bool) && slides.count > 1 }
    private var cur: Int { slides.isEmpty ? 0 : min(page, slides.count - 1) }

    var body: some View {
        TabView(selection: $page) {
            ForEach(Array(slides.enumerated()), id: \.offset) { i, s in slide(s, i).tag(i) }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: Self.height)
        .background(Theme.tint)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if slides.count > 1 {
                (Text("\(cur + 1)").foregroundColor(Theme.accent) + Text("\u{00A0}/ \(slides.count)").foregroundColor(Theme.text))
                    .font(Theme.font(11, .medium)).kerning(0.6).monospacedDigit()
                    .padding(.horizontal, 10).frame(height: 26).background(Capsule().fill(.ultraThinMaterial)).background(Capsule().fill(.white.opacity(0.5)))
                    .padding(10).allowsHitTesting(false)
            }
        }
        .padding(.horizontal, Theme.gutter).padding(.top, 12)
        .onChange(of: page) { _ in started = Date() }
        .onChange(of: slides.count) { n in if page >= n { page = 0 } }
        .onAppear { started = Date() }
        .task(id: page) {
            guard autoplay else { return }
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            if !Task.isCancelled, !slides.isEmpty { withAnimation(.easeInOut(duration: 0.5)) { page = (cur + 1) % slides.count } }
        }
    }

    private func go(_ d: Int) { guard !slides.isEmpty else { return }; withAnimation(.easeInOut(duration: 0.4)) { page = (cur + d + slides.count) % slides.count } }

    /// Заголовок: со второй строки — цветом раздела
    private func title(_ t: String) -> Text {
        let lines = t.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let first = lines.first else { return Text("") }
        let rest = lines.dropFirst().joined(separator: " ")
        return rest.isEmpty ? Text(first) : Text(first + " ") + Text(rest).foregroundColor(Theme.accent)
    }

    private func slide(_ s: Slide, _ i: Int) -> some View {
        ZStack(alignment: .bottom) {
            ProductImage(path: s.image, kind: "coat", tone: "#3d3d40")
                .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            if !s.eyebrow.isEmpty {
                HStack(spacing: 6) {
                    Circle().fill(Theme.accentGradient).frame(width: 6, height: 6)
                    Text(s.eyebrow.uppercased()).font(Theme.font(10, .medium)).kerning(0.7).foregroundStyle(Theme.text).lineLimit(1)
                }
                .padding(.leading, 9).padding(.trailing, 10).frame(height: 26)
                .background(Capsule().fill(.ultraThinMaterial)).background(Capsule().fill(.white.opacity(0.5)))
                .padding(10).padding(.trailing, slides.count > 1 ? 64 : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            panel(s, i).padding(8)
        }
        .contentShape(Rectangle())
    }

    private func panel(_ s: Slide, _ i: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if autoplay {
                TimelineView(.animation(minimumInterval: 1 / 60, paused: i != cur)) { ctx in
                    let p = i == cur ? CGFloat(min(1, max(0, ctx.date.timeIntervalSince(started) / interval))) : 0
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Theme.ink.opacity(0.08))
                        Rectangle().fill(Theme.accentGradient).scaleEffect(x: p, anchor: .leading)
                    }.frame(height: 2).transaction { $0.animation = nil }
                }.frame(height: 2)
            }
            VStack(alignment: .leading, spacing: 9) {
                title(s.title).font(Theme.font(23, .light)).kerning(-0.8).foregroundColor(Theme.text).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                if !s.text.isEmpty { Text(s.text).font(Theme.font(13)).foregroundStyle(Theme.muted).lineSpacing(1.5).lineLimit(3).fixedSize(horizontal: false, vertical: true) }
                if !s.code.isEmpty {
                    Button {
                        UIPasteboard.general.string = s.code; Haptic.success()
                        Toast.shared.show("Промокод \(s.code) скопирован — вставьте его при оформлении")
                    } label: {
                        HStack(spacing: 10) {
                            Text("Промокод").foregroundStyle(Theme.dim)
                            Text(s.code).font(Theme.font(12, .semibold)).kerning(1).foregroundStyle(Theme.text)
                        }
                        .font(Theme.font(12)).padding(.horizontal, 12).frame(height: 30)
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    }.buttonStyle(Pressable())
                }
                HStack(spacing: 6) {
                    if !s.btn1.0.isEmpty {
                        Button { router.open(path: s.btn1.1) } label: {
                            HStack(spacing: 10) {
                                Text(s.btn1.0).font(Theme.font(13, .medium)).kerning(0.3).lineLimit(1)
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.right").font(.system(size: 11, weight: .medium))
                                    .frame(width: 30, height: 30).background(Circle().fill(.white.opacity(0.18)))
                            }
                            .foregroundStyle(.white).padding(.leading, 16).padding(.trailing, 5).frame(height: 40)
                            .background(Capsule().fill(Theme.accentGradient))
                        }.buttonStyle(Pressable())
                    } else { Spacer(minLength: 0) }
                    if slides.count > 1 {
                        arrow("chevron.left", "Предыдущий слайд") { go(-1) }
                        arrow("chevron.right", "Следующий слайд") { go(1) }
                    }
                }
            }
            .padding(.horizontal, 12).padding(.top, 11).padding(.bottom, 12)
        }
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.white.opacity(0.55)))
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.ultraThinMaterial))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func arrow(_ icon: String, _ label: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Image(systemName: icon).font(.system(size: 12, weight: .regular)).foregroundStyle(Theme.ink)
                .frame(width: 44, height: 40).background(Capsule().fill(.white)).overlay(Capsule().stroke(Theme.ink.opacity(0.12), lineWidth: 1))
        }.buttonStyle(Pressable()).accessibilityLabel(label)
    }
}

// MARK: - Категории: фото в мягкой подложке 24, название и кружок со стрелкой

struct CategoryImage: View {
    let category: Category
    @EnvironmentObject private var shop: Shop
    var body: some View {
        let p = shop.visibleProducts.first { $0.categoryId == category.id }
        if !category.image.isEmpty { RemoteImage(path: category.image) }
        else if let p, !p.image.isEmpty { RemoteImage(path: p.image) }
        else { ArtView(kind: category.artKind, tone: category.artTone) }
    }
}

struct CategoryCard: View {
    let category: Category
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CategoryImage(category: category).frame(width: 159, height: 212)
                .background(Theme.photo).clipShape(RoundedRectangle(cornerRadius: 24)).hairline(RoundedRectangle(cornerRadius: 24))
            HStack(alignment: .top) {
                Text(category.name).font(Theme.font(15.5)).foregroundStyle(Theme.text).lineLimit(2).multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                Image(systemName: "arrow.right").font(.system(size: 12, weight: .light)).foregroundStyle(Theme.text)
                    .frame(width: 32, height: 32).background(Circle().fill(Theme.surface)).hairline(Circle())
            }.padding(.top, 14).padding(.horizontal, 4)
        }.frame(width: 159)
    }
}

// MARK: - Карточка товара (.card): фото в подложке 16, плашка с точкой, сердечко, название, раздел·цвет, кружки цветов, цена, бонусы

struct ProductCard: View {
    let product: Product
    var tab: Tab? = nil
    var bag = false
    @EnvironmentObject private var shop: Shop
    @EnvironmentObject private var router: Router
    @State private var colorId: String?

    var body: some View {
        let c = product.color(colorId ?? product.colors.first(where: { $0.stock > 0 })?.id)
        let pr = shop.price(product)
        Button { router.push(.product(product.id + (colorId.map { "?color=" + $0 } ?? "")), on: tab) } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    Color.clear.aspectRatio(177 / 235, contentMode: .fit)
                        .overlay(ProductImage(path: c.images.first ?? "", kind: c.artKind, tone: c.artTone))
                        .background(Theme.photo)
                        .clipShape(RoundedRectangle(cornerRadius: 16)).hairline(RoundedRectangle(cornerRadius: 16), 0.04)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(shop.badges(product).prefix(2).enumerated()), id: \.offset) { _, b in Badge(text: b.text, color: b.color, filled: b.text.contains("%") || b.text.lowercased().contains("скидк")) }
                    }.padding(10)
                    if !product.available {
                        Text("Нет в наличии").font(Theme.font(10.5, .semibold)).foregroundStyle(Theme.text).padding(.horizontal, 9).padding(.vertical, 4)
                            .background(Capsule().fill(.white.opacity(0.9))).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).padding(10)
                    }
                }
                .overlay(alignment: .topTrailing) { FavCircle(on: shop.isFavorite(product.id)) { shop.toggleFavorite(product.id) }.padding(8) }
                .overlay(alignment: .bottomTrailing) {
                    if bag && product.available {
                        Button { router.push(.product(product.id), on: tab) } label: {
                            Image(systemName: "bag").font(.system(size: 13)).foregroundStyle(Theme.text).frame(width: 32, height: 32).background(Circle().fill(.white.opacity(0.94))).hairline(Circle())
                        }.padding(10)
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(product.name).font(Theme.font(13.5, .medium)).foregroundStyle(Theme.text).lineLimit(2).multilineTextAlignment(.leading).lineSpacing(1).padding(.top, 14)
                    Text([shop.category(product.categoryId)?.name ?? "", product.colors.count == 1 ? c.name : ""].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(Theme.font(12.5)).foregroundStyle(Theme.muted).lineLimit(1).padding(.top, 6)
                    if product.colors.count > 1 {
                        HStack(spacing: 8) {
                            ForEach(product.colors.prefix(5)) { col in
                                Button { withAnimation(.easeOut(duration: 0.2)) { colorId = col.id } } label: {
                                    Circle().fill(Color(hex: col.hex.isEmpty ? "#cccccc" : col.hex)).frame(width: 12, height: 12)
                                        .overlay(Circle().strokeBorder(Color(red: 20 / 255, green: 20 / 255, blue: 22 / 255).opacity(0.16)))
                                        .padding(2).overlay(Circle().strokeBorder(col.id == c.id ? Theme.ink : .clear, lineWidth: 1))
                                }.buttonStyle(.plain)
                            }
                        }.padding(.top, 10)
                    }
                    PriceView(price: pr, size: 14).padding(.top, 12)
                    if shop.bonusFor(pr.price) > 0 { BonusPill(amount: shop.bonusFor(pr.price)).padding(.top, 10) }
                }.padding(.horizontal, 4)
            }
        }
        .buttonStyle(Pressable())
    }
}

/// Две колонки карточек, как сетка сайта на телефоне
struct ProductGrid: View {
    let products: [Product]
    var tab: Tab? = nil
    var bag = false
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8, alignment: .top), GridItem(.flexible(), spacing: 8, alignment: .top)], spacing: 28) {
            ForEach(products) { ProductCard(product: $0, tab: tab, bag: bag) }
        }.padding(.horizontal, Theme.gutter)
    }
}

// MARK: - «Вы недавно смотрели»

struct RecentRow: View {
    var exceptId: String?
    var tab: Tab? = nil
    @EnvironmentObject private var shop: Shop
    var body: some View {
        let list = shop.recentIds.filter { $0 != exceptId }.compactMap { id in shop.products.first { $0.id == id } }.prefix(10)
        if list.count >= (exceptId == nil ? 2 : 1) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    DotTitle(text: "Вы недавно смотрели", size: 26)
                    Spacer()
                    Button { withAnimation { shop.clearRecent() } } label: { Text("Очистить").font(Theme.font(13)).foregroundStyle(Theme.muted) }
                }.padding(.horizontal, Theme.gutter)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 10) { ForEach(Array(list)) { ProductCard(product: $0, tab: tab).frame(width: 140) } }.padding(.horizontal, Theme.gutter)
                }
            }
        }
    }
}

// MARK: - Бонусная программа: тёмная карта, заголовок, три шага и кнопка

struct BonusBand: View {
    @EnvironmentObject private var shop: Shop
    @EnvironmentObject private var router: Router
    var body: some View {
        let h = shop.settings.raw["home"], pct = shop.settings.bonusPercent
        let creditDone = shop.settings.raw["bonus"]["creditOn"].str == "done"
        let title = Fmt.plain((h["bonusTitle"].string ?? "Возвращаем бонусами").replacingOccurrences(of: "{n}", with: "\(pct)"))
        let steps = [("bag", "Покупайте", "\(pct)% от суммы заказа возвращаем бонусами"),
                     ("cylinder.split.1x2", "Копите", "Бонусы приходят на счёт " + (creditDone ? "после получения заказа" : "после оплаты заказа")),
                     ("creditcard", "Оплачивайте", "Тратьте на следующие покупки, хоть все сразу")]
        VStack(alignment: .leading, spacing: 22) {
            LoyalCard().padding(.horizontal, 4).padding(.top, 8)
            if !h["bonusEyebrow"].str.isEmpty { Eyebrow(text: h["bonusEyebrow"].str) }
            Text(title).font(Theme.font(44, .light)).kerning(-1.6).lineSpacing(-6).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
            if !h["bonusText"].str.isEmpty {
                HStack(spacing: 10) { Rectangle().fill(Theme.muted).frame(width: 16, height: 1); Text(h["bonusText"].str).font(Theme.font(15)).foregroundStyle(Theme.muted) }
            }
            VStack(spacing: 10) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: s.0).font(.system(size: 16, weight: .light)).foregroundStyle(.white)
                            .frame(width: 40, height: 40).background(RoundedRectangle(cornerRadius: 12).fill(i == 0 ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.dark)))
                        VStack(alignment: .leading, spacing: 3) { Text(s.1).font(Theme.font(15.5, .medium)); Text(s.2).font(Theme.font(13.5)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true) }
                        Spacer(minLength: 0)
                        Text("\(i + 1)").font(Theme.font(11)).foregroundStyle(Theme.dim)
                    }
                    .padding(16).background(RoundedRectangle(cornerRadius: 18).fill(.white)).hairline(RoundedRectangle(cornerRadius: 18))
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                if shop.user != nil {
                    PrimaryButton(title: "Открыть бонусный счёт", arrow: true) { router.reset(.account, to: [.bonus]) }
                } else {
                    PrimaryButton(title: "Присоединиться", arrow: true) { router.reset(.account) }
                    Text("Регистрация займёт минуту").font(Theme.font(13.5)).foregroundStyle(Theme.muted)
                }
            }
        }
        .padding(18).padding(.bottom, 6)
        .background(RoundedRectangle(cornerRadius: 26).fill(LinearGradient(colors: [Color(hex: "#fbf7f4"), Theme.surface], startPoint: .top, endPoint: .bottom)))
        .hairline(RoundedRectangle(cornerRadius: 26), 0.06)
        .padding(.horizontal, Theme.gutter)
    }
}

/// Бонусная карта: тёмная, с отблеском, процент или баланс, имя владельца
struct LoyalCard: View {
    @EnvironmentObject private var shop: Shop
    var body: some View {
        let u = shop.user, pct = shop.settings.bonusPercent
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(hex: "#2a2f36"), Color(hex: "#0d0e10")], startPoint: .topLeading, endPoint: .bottomTrailing)
            LinearGradient(colors: [.white.opacity(0.12), .clear, .white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading) {
                HStack { Image("Logo").resizable().scaledToFit().frame(width: 26).colorInvert(); Spacer(); Text("Бонусный счёт").font(Theme.font(12.5)).foregroundStyle(.white.opacity(0.6)) }
                Spacer()
                // Процент — того же размера и цвета, что и число, вплотную к нему
                Text("\(pct)%").font(Theme.font(64, .light)).foregroundStyle(.white)
                Spacer()
                HStack {
                    Text(u.map { $0.name } ?? "Ваше имя").font(Theme.font(13.5)).foregroundStyle(.white.opacity(0.75))
                    Spacer()
                    Text("\(u?.bonus ?? 0) \(Fmt.plural(u?.bonus ?? 0, "бонус", "бонуса", "бонусов"))").font(Theme.font(13.5, .medium)).foregroundStyle(.white.opacity(0.85))
                }
            }.padding(20)
        }
        .frame(height: 200).clipShape(RoundedRectangle(cornerRadius: 22))
        .rotationEffect(.degrees(-2))
    }
}

// MARK: - Акция: тёмная карточка со скидкой, сроком и кнопкой

struct DealBand: View {
    let promo: Promotion
    @EnvironmentObject private var shop: Shop
    @EnvironmentObject private var router: Router
    var body: some View {
        let off = promo.type == "percent" ? "−\(Int(promo.value))%" : "−" + Fmt.rub(Int(promo.value))
        let cats = promo.scope == "categories" ? promo.categoryIds.compactMap { shop.category($0)?.name } : []
        let scope = promo.scope == "all" ? "Весь каталог" : !cats.isEmpty ? cats.joined(separator: ", ") : "Избранные модели"
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("АКЦИЯ").font(Theme.font(11, .medium)).kerning(1.2).foregroundStyle(.white.opacity(0.7))
                Spacer()
                if !promo.endsAt.isEmpty { Text("до " + Fmt.date(ISO.date(promo.endsAt + "T12:00:00Z"))).font(Theme.font(12.5)).foregroundStyle(.white.opacity(0.7)) }
            }
            Text(off).font(Theme.font(72, .light)).kerning(-3).foregroundStyle(LinearGradient(colors: [.white, .white.opacity(0.6)], startPoint: .top, endPoint: .bottom)) // на тёмной карточке — белым: цвет раздела «мужчинам» сливается с фоном
            Text(promo.title).font(Theme.font(24, .light)).foregroundStyle(.white)
            Text(scope).font(Theme.font(14)).foregroundStyle(.white.opacity(0.65))
            Button { router.push(.catalog(cat: nil, tag: nil, sale: true), on: .home) } label: {
                HStack(spacing: 12) { Text("Смотреть товары").font(Theme.font(14, .medium)); ArrowDot(size: 34, dark: true) }
                    .foregroundStyle(Theme.text).padding(.leading, 20).padding(.trailing, 7).frame(height: 48).background(Capsule().fill(.white))
            }.buttonStyle(Pressable()).padding(.top, 6)
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background(ZStack { Theme.dark; RadialGradient(colors: [Theme.accent.opacity(0.28), .clear], center: .topTrailing, startRadius: 0, endRadius: 260) })
        .clipShape(RoundedRectangle(cornerRadius: 26))
        .padding(.horizontal, Theme.gutter)
    }
}

// MARK: - «Ателье»: фото в рамке с пунктиром, заголовок, текст и «О бренде»

struct AtelierBlock: View {
    @EnvironmentObject private var shop: Shop
    @EnvironmentObject private var router: Router
    var body: some View {
        let h = shop.settings.raw["home"]
        VStack(alignment: .leading, spacing: 20) {
            ProductImage(path: h["editorialImage"].str, kind: h["editorialArt"]["kind"].string ?? "knit", tone: h["editorialArt"]["tone"].string ?? "#3a3a3d")
                .frame(height: 450).clipShape(RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.85), style: StrokeStyle(lineWidth: 1, dash: [5, 4])).padding(12))
                .hairline(RoundedRectangle(cornerRadius: 22), 0.06)
            if !h["editorialEyebrow"].str.isEmpty { Eyebrow(text: h["editorialEyebrow"].str) }
            Text(h["editorialTitle"].str).font(Theme.font(40, .light)).kerning(-1.4).lineSpacing(-4).fixedSize(horizontal: false, vertical: true)
            if !h["editorialText"].str.isEmpty { Text(h["editorialText"].str).font(Theme.font(16)).foregroundStyle(Theme.muted).lineSpacing(7) }
            if shop.page("about") != nil {
                Button { router.push(.page("about"), on: .home) } label: {
                    HStack(spacing: 10) { Text("О бренде").font(Theme.font(15)); Image(systemName: "arrow.right").font(.system(size: 12, weight: .light)) }
                        .foregroundStyle(Theme.text).padding(.horizontal, 20).frame(height: 46).background(Capsule().fill(Theme.surface)).hairline(Capsule(), 0.08)
                }.buttonStyle(Pressable())
            }
        }.padding(.horizontal, Theme.gutter)
    }
}

// MARK: - «Сервис»: карточки с цветным свечением и значком

struct BenefitsBlock: View {
    @EnvironmentObject private var shop: Shop
    @EnvironmentObject private var router: Router
    static let colors = ["delivery": "#1ab248", "quality": "#e8b84a", "fabric": "#c9925e", "fitting": "#ff8b74", "return": "#7b61ff", "payment": "#16b5a5", "gift": "#f0587c", "cash": "#22b45a", "pin": "#ff8b74", "style": "#c9925e", "gem": "#7b61ff", "spool": "#ff8b74", "mail": "#3e6bf0", "chat": "#16b5a5", "phone": "#1ab248"]
    static let words: [(String, String)] = [("доставк|курьер|сдэк|отправ", "delivery"), ("качеств|гаранти|провер", "quality"), ("ткан|материал|шерст|кашемир|хлоп|шёлк|шелк|лён|трикотаж|пряж", "fabric"),
                                            ("примерк|подош|примерить", "fitting"), ("возврат|обмен|вернуть", "return"), ("оплат|карт|рассроч|сплит|долям", "payment"), ("подар|упаков", "gift")]
    static func icon(_ b: JSON) -> String {
        let ic = b["icon"].str
        if ic == "none" { return "" }
        if colors[ic] != nil { return ic }
        for t in [b["title"].str, b["text"].str] { for w in words where t.lowercased().range(of: w.0, options: .regularExpression) != nil { return w.1 } }
        return ""
    }
    var body: some View {
        let h = shop.settings.raw["home"]
        VStack(alignment: .leading, spacing: 18) {
            if !h["benefitsTitle"].str.isEmpty {
                if !h["benefitsEyebrow"].str.isEmpty { Eyebrow(text: h["benefitsEyebrow"].str) }
                DotTitle(text: h["benefitsTitle"].str, size: 30)
            }
            VStack(spacing: 10) {
                ForEach(Array(h["benefits"].array.enumerated()), id: \.offset) { _, b in
                    let ic = BenefitsBlock.icon(b)
                    HStack(alignment: .top, spacing: 16) {
                        if !ic.isEmpty { RemoteImage(path: "img/benefits/\(ic).webp", contentMode: .fit).frame(width: 84, height: 84) }
                        VStack(alignment: .leading, spacing: 8) {
                            Text(b["title"].str).font(Theme.font(20, .light)).fixedSize(horizontal: false, vertical: true)
                            if !b["text"].str.isEmpty { Text(b["text"].str).font(Theme.font(14.5)).foregroundStyle(Theme.muted).lineSpacing(4) }
                            if !b["link"].str.isEmpty { Button { router.open(path: b["link"].str) } label: { Text((b["linkText"].string ?? "Подробнее") + " →").font(Theme.font(14)).foregroundStyle(Theme.text) } }
                        }.padding(.vertical, 4)
                        Spacer(minLength: 0)
                    }
                    .padding(18)
                    .background(ZStack {
                        RoundedRectangle(cornerRadius: 22).fill(LinearGradient(colors: [.white, Theme.surface], startPoint: .top, endPoint: .bottom))
                        if !ic.isEmpty { RoundedRectangle(cornerRadius: 22).fill(RadialGradient(colors: [Color(hex: BenefitsBlock.colors[ic] ?? "#cccccc").opacity(0.22), .clear], center: .leading, startRadius: 0, endRadius: 140)) }
                    })
                    .hairline(RoundedRectangle(cornerRadius: 22), 0.07)
                }
            }
        }.padding(.horizontal, Theme.gutter)
    }
}

// MARK: - Раздел закрыт: «…коллекция скоро появится» (как soonPage на сайте)

struct SoonView: View {
    @EnvironmentObject private var shop: Shop
    var body: some View {
        let g = shop.gender ?? ""
        let c = shop.settings.raw["genders"][g]
        let title = (c["title"].string ?? "\(Sections.name(g)) — скоро").replacingOccurrences(of: "*", with: "")
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ProductImage(path: c["image"].str, kind: g == "women" ? "dress" : g == "kids" ? "tee" : "coat", tone: g == "kids" ? "#5aa6e6" : "#3d3d40")
                    .frame(height: 300).frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 26))
                Eyebrow(text: Sections.name(g)).padding(.top, 6)
                Text(title).font(Theme.font(34, .light)).kerning(-1.2).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                if !c["text"].str.isEmpty { Text(c["text"].str).font(Theme.font(15)).foregroundStyle(Theme.muted).lineSpacing(4) }
                ForEach(Sections.all.filter { $0.key != g && !shop.closed($0.key) }, id: \.key) { x in
                    PrimaryButton(title: "Смотреть «\(x.name)»", arrow: true) { withAnimation { shop.gender = x.key } }
                }
                LinkButton(title: "Вся коллекция") { withAnimation { shop.gender = nil } }
            }
            .padding(.horizontal, Theme.gutter).padding(.top, 20).padding(.bottom, 40)
            Footer()
        }
        .refreshable { await shop.load() }
    }
}
