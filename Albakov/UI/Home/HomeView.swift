import SwiftUI

// Главная: строка объявлений, слайдер, разделы женщинам/мужчинам, категории, новинки, хиты, скидки
struct HomeView: View {
    @EnvironmentObject private var shop: Shop
    @EnvironmentObject private var router: Router

    var body: some View {
        ScrollView {
            VStack(spacing: 34) {
                VStack(spacing: 0) {
                    if !shop.settings.announcement.isEmpty { Announcement(text: shop.settings.announcement) }
                    GenderSwitch()
                    if !slides.isEmpty { HeroSlider(slides: slides) }
                }
                if !shop.visibleCategories.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionTitle(title: "Категории", action: "Весь каталог") { router.reset(.catalog) }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(shop.visibleCategories) { c in
                                    Button { router.push(.catalog(cat: c.id, tag: nil, sale: false), on: .home) } label: { CategoryCard(category: c) }.buttonStyle(Pressable())
                                }
                            }.padding(.horizontal, Theme.gutter)
                        }
                    }
                }
                row("Новинки", shop.newProducts, tag: "new")
                row("Хиты продаж", shop.hits, tag: "hit")
                row("Скидки", Array(shop.saleProducts.prefix(10)), sale: true)
                Footer()
            }
            .padding(.bottom, 24)
        }
        .refreshable { await shop.load() }
        .toolbar {
            ToolbarItem(placement: .principal) { Image("Wordmark").resizable().scaledToFit().frame(width: 118) }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { router.push(.search, on: .home) } label: { Image(systemName: "magnifyingglass") }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var slides: [Slide] { shop.settings.slides.filter { $0.gender.isEmpty || shop.gender == nil || $0.gender == shop.gender } }

    @ViewBuilder
    private func row(_ title: String, _ list: [Product], tag: String? = nil, sale: Bool = false) -> some View {
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                SectionTitle(title: title, action: "Все") { router.push(.catalog(cat: nil, tag: tag, sale: sale), on: .home) }
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(list) { p in ProductCard(product: p, tab: .home).frame(width: 172) }
                    }.padding(.horizontal, Theme.gutter)
                }
            }
        }
    }
}

struct Announcement: View {
    let text: String
    @State private var i = 0
    private var parts: [String] { text.components(separatedBy: " · ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
    var body: some View {
        let list = parts.isEmpty ? [text] : parts
        Text(list[i % list.count])
            .font(Theme.font(12)).kerning(0.3).foregroundStyle(.white.opacity(0.82)).lineLimit(1)
            .frame(maxWidth: .infinity).padding(.vertical, 10).padding(.horizontal, 12)
            .background(Theme.ink)
            .id(i).transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 6)), removal: .opacity))
            .animation(.easeInOut(duration: 0.45), value: i)
            .task { while list.count > 1 { try? await Task.sleep(nanoseconds: 3_500_000_000); i += 1 } }
    }
}

struct GenderSwitch: View {
    @EnvironmentObject private var shop: Shop
    var body: some View {
        let open = shop.settings.gendersOpen
        if open.count > 1 {
            HStack(spacing: 0) {
                ForEach([("women", "Женщинам"), ("men", "Мужчинам")], id: \.0) { g in
                    let on = shop.gender == g.0
                    Button { withAnimation(.easeInOut(duration: 0.25)) { shop.gender = on ? nil : g.0 } } label: {
                        VStack(spacing: 10) {
                            HStack(alignment: .top, spacing: 3) {
                                Text(g.1).font(Theme.font(15, on ? .medium : .regular)).foregroundStyle(on ? Theme.text : Theme.muted)
                                if open[g.0] == false { Text("скоро").font(Theme.font(10)).foregroundStyle(Theme.dim) }
                            }
                            Rectangle().fill(on ? Theme.ink : .clear).frame(height: 1.5)
                        }.padding(.top, 14)
                    }.frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .overlay(alignment: .bottom) { Divider1() }
        }
    }
}

struct HeroSlider: View {
    let slides: [Slide]
    @EnvironmentObject private var router: Router
    @State private var page = 0

    var body: some View {
        TabView(selection: $page) {
            ForEach(Array(slides.enumerated()), id: \.offset) { i, s in
                ZStack(alignment: .bottomLeading) {
                    RemoteImage(path: s.image)
                    LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .center, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 14) {
                        if !s.eyebrow.isEmpty { Eyebrow(text: s.eyebrow) }
                        Text(s.title).font(Theme.font(34, .light)).kerning(-1).foregroundStyle(.white).lineSpacing(-4)
                        HStack(spacing: 14) {
                            if !s.btn1.0.isEmpty {
                                Button { router.open(path: s.btn1.1) } label: {
                                    HStack(spacing: 10) { Text(s.btn1.0).font(Theme.font(14, .medium)); Image(systemName: "arrow.right").font(.system(size: 12, weight: .medium)) }
                                        .foregroundStyle(Theme.ink).padding(.horizontal, 18).frame(height: 46).background(Capsule().fill(.white))
                                }.buttonStyle(Pressable())
                            }
                            if !s.btn2.0.isEmpty {
                                Button { router.open(path: s.btn2.1) } label: { Text(s.btn2.0).font(Theme.font(14, .medium)).foregroundStyle(.white).underline() }
                            }
                        }
                    }
                    .padding(20).padding(.bottom, 26)
                }
                .tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 470)
        .overlay(alignment: .bottom) {
            HStack(spacing: 6) {
                ForEach(slides.indices, id: \.self) { i in Capsule().fill(.white.opacity(i == page ? 1 : 0.4)).frame(width: i == page ? 22 : 6, height: 3) }
            }.padding(.bottom, 14).animation(.easeOut, value: page)
        }
        .task { while slides.count > 1 { try? await Task.sleep(nanoseconds: 7_000_000_000); withAnimation(.easeInOut(duration: 0.6)) { page = (page + 1) % slides.count } } }
    }
}

struct CategoryCard: View {
    let category: Category
    @EnvironmentObject private var shop: Shop
    var body: some View {
        let img = category.image.isEmpty ? (shop.visibleProducts.first { $0.categoryId == category.id }?.image ?? "") : category.image
        ZStack(alignment: .bottomLeading) {
            RemoteImage(path: img)
            LinearGradient(colors: [.clear, .black.opacity(0.4)], startPoint: .center, endPoint: .bottom)
            Text(category.name).font(Theme.font(16, .medium)).foregroundStyle(.white).padding(14)
        }
        .frame(width: 150, height: 196).clipShape(RoundedRectangle(cornerRadius: 22))
    }
}

/// Карточка товара: фото, плашки, сердечко, название, цена
struct ProductCard: View {
    let product: Product
    var tab: Tab? = nil
    @EnvironmentObject private var shop: Shop
    @EnvironmentObject private var router: Router

    var body: some View {
        Button { router.push(.product(product.id), on: tab) } label: {
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .topLeading) {
                    Color.clear.aspectRatio(3 / 4, contentMode: .fit)
                        .overlay(RemoteImage(path: product.image))
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    VStack(alignment: .leading, spacing: 4) { ForEach(Array(shop.badges(product).enumerated()), id: \.offset) { Badge(text: $1.text, color: $1.color) } }.padding(10)
                    if !product.available {
                        Text("Нет в наличии").font(Theme.font(11, .medium)).padding(.horizontal, 9).padding(.vertical, 5)
                            .background(Capsule().fill(.white.opacity(0.92))).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).padding(10)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    Button { shop.toggleFavorite(product.id) } label: {
                        Image(systemName: shop.isFavorite(product.id) ? "heart.fill" : "heart").font(.system(size: 15))
                            .foregroundStyle(shop.isFavorite(product.id) ? Theme.danger : Theme.text)
                            .frame(width: 34, height: 34).background(Circle().fill(.white.opacity(0.9)))
                    }.padding(8)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(product.name).font(Theme.font(13.5)).foregroundStyle(Theme.text).lineLimit(2).multilineTextAlignment(.leading)
                    PriceView(price: shop.price(product), size: 14)
                    if product.colors.count > 1 {
                        HStack(spacing: 4) { ForEach(product.colors.prefix(5)) { c in Circle().fill(Color(hex: c.hex.isEmpty ? "#ccc" : c.hex)).frame(width: 10, height: 10).overlay(Circle().strokeBorder(Theme.line)) } }
                    }
                }
            }
        }
        .buttonStyle(Pressable())
    }
}

struct Footer: View {
    @EnvironmentObject private var shop: Shop
    @EnvironmentObject private var router: Router
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image("Wordmark").resizable().scaledToFit().frame(width: 120).colorInvert()
            if !shop.settings.tagline.isEmpty { Text(shop.settings.tagline).font(Theme.font(13)).foregroundStyle(.white.opacity(0.7)) }
            VStack(alignment: .leading, spacing: 12) {
                ForEach(shop.pages.filter { $0.group != "legal" }) { p in
                    Button { router.push(.page(p.slug), on: .home) } label: { Text(p.title).font(Theme.font(14)).foregroundStyle(.white.opacity(0.85)) }
                }
                Button { router.push(.sizes, on: .home) } label: { Text("Таблица размеров").font(Theme.font(14)).foregroundStyle(.white.opacity(0.85)) }
            }
            if !shop.settings.socials.isEmpty {
                HStack(spacing: 10) {
                    ForEach(shop.settings.socials) { s in
                        Link(destination: URL(string: s.url)!) { Text(s.name).font(Theme.font(12.5, .medium)).foregroundStyle(.white).padding(.horizontal, 12).padding(.vertical, 8).background(Capsule().strokeBorder(.white.opacity(0.25))) }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(shop.pages.filter { $0.group == "legal" }) { p in
                    Button { router.push(.page(p.slug), on: .home) } label: { Text(p.title).font(Theme.font(12)).foregroundStyle(.white.opacity(0.55)) }
                }
                Text("© \(Calendar.current.component(.year, from: Date())) \(shop.settings.storeName)®").font(Theme.font(12)).foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(24).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.ink)
        .clipShape(RoundedRectangle(cornerRadius: 28)).padding(.horizontal, 10)
    }
}
