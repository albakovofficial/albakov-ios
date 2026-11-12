import SwiftUI

// Шапка, меню, кнопка «Написать нам» и подвал — как на сайте в телефоне.

/// Шапка: ☰, знак ALBAKOV по центру, поиск, избранное, корзина со счётчиком; под ней — разделы
struct SiteHeader: View {
    var tab: Tab
    var genders = true
    @EnvironmentObject private var shop: Shop
    @EnvironmentObject private var router: Router
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                icon("line.3.horizontal") { router.menuOpen = true }
                Spacer()
                Button { router.reset(.home) } label: {
                    HStack(alignment: .top, spacing: 2) {
                        Image("Wordmark").resizable().scaledToFit().frame(width: 140)
                        Text("®").font(.system(size: 6)).foregroundStyle(Theme.ink.opacity(0.85)).offset(y: -2)
                    }
                }.accessibilityLabel("ALBAKOV — на главную")
                Spacer()
                icon("magnifyingglass") { router.push(.search, on: tab == .account || tab == .cart ? .catalog : tab) }
                icon("heart") { router.reset(.favorites) }
                icon("bag", count: shop.cartCount) { router.reset(.cart) }
            }
            .padding(.horizontal, 10).frame(height: 76)
            if genders { GenderTabs() }
        }
        // Линия под шапкой — под содержимым: черта выбранного раздела ложится поверх неё, а не наоборот
        .background(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
        // Белый фон уходит и под часы: иначе там просвечивает прокрученная страница
        .background(Color.white)
    }
    private func icon(_ name: String, count: Int = 0, _ a: @escaping () -> Void) -> some View {
        Button { Haptic.tap(); a() } label: {
            Image(systemName: name).font(.system(size: 17, weight: .light)).foregroundStyle(Theme.text)
                .frame(width: 38, height: 42)
                .overlay(alignment: .topTrailing) {
                    if count > 0 {
                        Text("\(count)").font(Theme.font(10, .semibold)).foregroundStyle(.white).frame(minWidth: 17, minHeight: 17)
                            .background(Circle().fill(Theme.accentGradient)).offset(x: 2, y: 2)
                    }
                }
        }
    }
}

/// Разделы под шапкой и в меню: выбранный — цветом раздела. Закрытые разделы не показываются, пока их не откроют в панели (1.0.0);
/// открыт один раздел — переключателя нет. Повторное нажатие — вся коллекция
struct GenderTabs: View {
    var drawer = false
    @EnvironmentObject private var shop: Shop
    @EnvironmentObject private var router: Router
    var body: some View {
        let shown = Sections.all.filter { !shop.closed($0.key) }
        if shown.count > 1 {
            if drawer {
                HStack(spacing: 3) {
                    ForEach(shown, id: \.key) { g in
                        let on = shop.gender == g.key
                        Button { pick(g.key) } label: {
                            Text(g.name).font(Theme.font(13.5, on ? .medium : .regular)).foregroundStyle(on ? .white : Theme.muted)
                                .frame(maxWidth: .infinity).frame(height: 44)
                                .background(Capsule().fill(on ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.clear)))
                        }.buttonStyle(.plain)
                    }
                }.padding(4).background(Capsule().fill(Theme.surface))
            } else {
                HStack(spacing: 0) {
                    ForEach(shown, id: \.key) { g in
                        let on = shop.gender == g.key
                        Button { pick(g.key) } label: {
                            Text(g.name).font(Theme.font(14)).kerning(0.4).foregroundStyle(on ? Theme.accent : Theme.muted)
                                .padding(.vertical, 12)
                                .overlay(alignment: .bottom) { Capsule().fill(Theme.accent).frame(height: 2).scaleEffect(x: on ? 1 : 0, anchor: .leading) }
                                .frame(maxWidth: .infinity)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.gutter)
            }
        }
    }
    private func pick(_ g: String) {
        Haptic.tap()
        router.menuOpen = false
        withAnimation(.easeInOut(duration: 0.25)) { shop.gender = shop.gender == g ? nil : g }
    }
}

/// Меню ☰: выезжает слева. Панель для сотрудников, раздел, быстрые кнопки, плитки разделов, соцсети, документы
struct MenuDrawer: View {
    @EnvironmentObject private var shop: Shop
    @EnvironmentObject private var router: Router
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    HStack(alignment: .top, spacing: 2) {
                        Image("Wordmark").resizable().scaledToFit().frame(width: 150)
                        Text("®").font(.system(size: 6)).offset(y: -2)
                    }
                    Spacer()
                    Button { router.menuOpen = false } label: { Image(systemName: "xmark").font(.system(size: 16, weight: .light)).foregroundStyle(Theme.text).frame(width: 40, height: 40) }
                }.padding(.top, 6)
                if shop.isStaff {
                    Button { go { router.reset(.account, to: [.admin]) } } label: {
                        HStack(spacing: 12) {
                            IconTile(icon: "square.grid.2x2", size: 40, fill: .white)
                            VStack(alignment: .leading, spacing: 1) { Text("Панель управления").font(Theme.font(15, .medium)); Text("Заказы, товары, финансы").font(Theme.font(12)).foregroundStyle(Theme.dim) }
                            Spacer(); Image(systemName: "arrow.right").font(.system(size: 13))
                        }.foregroundStyle(Theme.text).padding(12)
                        .background(RoundedRectangle(cornerRadius: 20).fill(Theme.tile)).hairline(RoundedRectangle(cornerRadius: 20), 0.06)
                    }.buttonStyle(Pressable())
                }
                GenderTabs(drawer: true)
                HStack(spacing: 10) {
                    quick("person", "Кабинет") { router.reset(.account) }
                    quick("heart", "Избранное", count: shop.favorites.count) { router.reset(.favorites) }
                    quick("shippingbox", "Мой заказ") { router.push(.track, on: .account) }
                }
                tiles
                if !shop.settings.socials.isEmpty {
                    HStack(spacing: 10) {
                        ForEach(shop.settings.socials) { s in if let u = URL(string: s.url) { Link(destination: u) { SocialIcon(name: s.name, url: s.url, size: 34) } } }
                        Spacer()
                        Text("Мы в соцсетях").font(Theme.font(13)).foregroundStyle(Theme.muted)
                    }
                    Divider1()
                }
                let docs = shop.pages.filter { $0.group == "legal" && $0.inFooter }
                if !docs.isEmpty {
                    Text("ДОКУМЕНТЫ").font(Theme.font(11.5, .medium)).kerning(1.2).foregroundStyle(Theme.muted)
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(docs.prefix(3)) { p in
                            let d = MenuDrawer.doc(p)
                            Button { go { router.push(.page(p.slug), on: .home) } } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    IconTile(icon: d.icon, size: 36, fill: .white)
                                    Spacer(minLength: 10)
                                    Text(d.title).font(Theme.font(14.5, .medium)).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.8)
                                    Text(d.sub).font(Theme.font(11.5)).foregroundStyle(Theme.muted).lineLimit(2).multilineTextAlignment(.leading)
                                }.padding(12).frame(maxWidth: .infinity, minHeight: 122, alignment: .topLeading)
                                .background(RoundedRectangle(cornerRadius: 18).fill(Theme.tile).overlay(RoundedRectangle(cornerRadius: 18).fill(RadialGradient(colors: [Theme.accent.opacity(0.10), .clear], center: .topTrailing, startRadius: 0, endRadius: 90))))
                            }.buttonStyle(Pressable())
                        }
                    }
                }
                Text("© \(Calendar.current.component(.year, from: Date())) \(shop.settings.storeName)®. Все права защищены. \(shop.settings.storeName) — зарегистрированный товарный знак")
                    .font(Theme.font(11.5)).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 20).padding(.bottom, 40)
        }
        .background(Color.white)
    }

    // Пункты меню плитками: первые четыре — квадратами по два, остальные — на всю ширину; «Акции» — плитка цвета раздела
    private var tiles: some View {
        var items = shop.settings.nav.map { (label: $0.label, link: $0.link) }
        if shop.giftEnabled { items.append((label: "Подарочные сертификаты", link: "#/gift")) }
        var sq = min(4, items.count); if sq % 2 == 1 { sq -= 1 }
        let squares = Array(items.prefix(sq)), wide = Array(items.dropFirst(sq))
        return VStack(spacing: 10) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Array(squares.enumerated()), id: \.offset) { _, it in tile(it.label, it.link, wide: false) }
            }
            ForEach(Array(wide.enumerated()), id: \.offset) { _, it in tile(it.label, it.link, wide: true) }
        }
    }
    private func tile(_ label: String, _ link: String, wide: Bool) -> some View {
        let sale = link.hasPrefix("#/sale") || link.hasPrefix("/sale")
        return Button { go { router.open(path: link) } } label: {
            Group {
                if wide {
                    HStack(spacing: 16) { Image(systemName: MenuDrawer.icon(link)).font(.system(size: 19, weight: .light)); Text(label).font(Theme.font(16)); Spacer() }
                        .padding(.horizontal, 18).frame(height: 62)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        if sale { IconTile(icon: MenuDrawer.icon(link), size: 34, fill: .white.opacity(0.16), tint: .white) }
                        else { Image(systemName: MenuDrawer.icon(link)).font(.system(size: 19, weight: .light)) }
                        Spacer()
                        Text(label).font(Theme.font(16, sale ? .medium : .regular))
                        if sale { Text("Скидки на коллекцию").font(Theme.font(11.5)).opacity(0.85) }
                    }
                    .padding(16).frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
                }
            }
            .foregroundStyle(sale ? .white : Theme.text)
            .background(RoundedRectangle(cornerRadius: 22).fill(sale ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.tile)))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(sale ? .clear : Theme.ink.opacity(0.06), lineWidth: 1))
        }.buttonStyle(Pressable())
    }
    private func quick(_ icon: String, _ t: String, count: Int = 0, _ a: @escaping () -> Void) -> some View {
        Button { go(a) } label: {
            VStack(spacing: 8) { Image(systemName: icon).font(.system(size: 18, weight: .light)); Text(t).font(Theme.font(13)) }
                .foregroundStyle(Theme.text).frame(maxWidth: .infinity).frame(height: 76)
                .background(RoundedRectangle(cornerRadius: 18).fill(.white)).hairline(RoundedRectangle(cornerRadius: 18), 0.09)
                .overlay(alignment: .topTrailing) { if count > 0 { Text("\(count)").font(Theme.font(10, .semibold)).foregroundStyle(.white).frame(minWidth: 18, minHeight: 18).background(Circle().fill(Theme.accentGradient)).padding(8) } }
        }.buttonStyle(Pressable())
    }
    private func go(_ a: () -> Void) { router.menuOpen = false; a() }

    static func icon(_ link: String) -> String {
        if link.contains("tag=new") { return "star" }
        if link.contains("sale") { return "tag" }
        if link.contains("sizes") { return "ruler" }
        if link.contains("catalog") { return "square.grid.2x2" }
        if link.contains("about") { return "info.circle" }
        if link.contains("gift") { return "gift" }
        if link.contains("track") { return "shippingbox" }
        return "doc.text"
    }
    static func doc(_ p: Page) -> (title: String, sub: String, icon: String) {
        switch p.slug {
        case "offer": return ("Оферта", "Условия покупки", "doc.text")
        case "privacy": return ("Политика", "Ваши данные", "lock.shield")
        case "consent": return ("Согласие", "На обработку данных", "checkmark.seal")
        default: return (p.title, "", "doc.text")
        }
    }
}

/// Значок соцсети в фирменном цвете — круглый логотип без белой подложки (как на сайте)
struct SocialIcon: View {
    let name: String, url: String
    var size: CGFloat = 36
    private var kind: String {
        let s = (name + " " + url).lowercased()
        if s.contains("t.me") || s.contains("telegram") { return "tg" }
        if s.contains("vk.") || s.contains("вконтакте") || s.contains("vk ") { return "vk" }
        if s.contains("instagram") { return "ig" }
        if s.contains("youtube") { return "yt" }
        if s.contains("dzen") || s.contains("дзен") { return "dz" }
        return "web"
    }
    var body: some View {
        ZStack {
            switch kind {
            case "tg": Circle().fill(Color(hex: "#2aabee")); Image(systemName: "paperplane.fill").font(.system(size: size * 0.42)).foregroundStyle(.white).offset(x: -size * 0.03)
            case "vk": Circle().fill(Color(hex: "#0077ff")); Text("VK").font(.system(size: size * 0.34, weight: .bold)).foregroundStyle(.white)
            case "ig":
                Circle()
                    .fill(RadialGradient(stops: [.init(color: Color(hex: "#fdf497"), location: 0.05), .init(color: Color(hex: "#fd5949"), location: 0.45),
                                                 .init(color: Color(hex: "#d6249f"), location: 0.6), .init(color: Color(hex: "#285aeb"), location: 0.9)],
                                         center: UnitPoint(x: 0.3, y: 1.07), startRadius: 0, endRadius: size * 1.5))
                // Камера Instagram: рамка, объектив, точка вспышки — тонкие белые линии
                RoundedRectangle(cornerRadius: size * 0.13).strokeBorder(.white, lineWidth: size * 0.06).frame(width: size * 0.48, height: size * 0.48)
                Circle().strokeBorder(.white, lineWidth: size * 0.06).frame(width: size * 0.24, height: size * 0.24)
                Circle().fill(.white).frame(width: size * 0.075, height: size * 0.075).offset(x: size * 0.14, y: -size * 0.14)
            case "yt": Circle().fill(Color(hex: "#ff0000")); Image(systemName: "play.fill").font(.system(size: size * 0.38)).foregroundStyle(.white)
            default: Circle().fill(Theme.ink); Image(systemName: "globe").font(.system(size: size * 0.46)).foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Круглая кнопка «Написать нам» цвета раздела в правом нижнем углу — как на сайте
struct ChatFab: View {
    @EnvironmentObject private var shop: Shop
    @EnvironmentObject private var router: Router
    var body: some View {
        Button { Haptic.tap(); router.reset(.account, to: shop.user == nil ? [] : [.support]) } label: {
            Image(systemName: "text.bubble").font(.system(size: 18, weight: .light)).foregroundStyle(.white)
                .frame(width: 50, height: 50).background(Circle().fill(Theme.accentGradient))
                .overlay(alignment: .topTrailing) {
                    if let n = shop.user?.supportUnread, n > 0 { Circle().fill(Color.white).frame(width: 12, height: 12).overlay(Circle().strokeBorder(Theme.accent, lineWidth: 3)) }
                }
        }.buttonStyle(Pressable()).accessibilityLabel("Написать нам")
    }
}

/// Подвал как на сайте: тёмная карточка с тёплым свечением, знак, «Написать нам», почта, разделы, контакты, соцсети, продавец, документы
struct Footer: View {
    @EnvironmentObject private var shop: Shop
    @EnvironmentObject private var router: Router
    @State private var open: Set<String> = []
    var body: some View {
        let s = shop.settings, c = s.raw["contacts"]
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 2) { Image("Wordmark").resizable().scaledToFit().frame(width: 220).colorInvert(); Text("®").font(.system(size: 8)).foregroundStyle(.white.opacity(0.8)) }
                if !s.tagline.isEmpty { Text(s.tagline).font(Theme.font(15)).foregroundStyle(.white.opacity(0.72)) }
            }
            VStack(spacing: 10) {
                pill(icon: "text.bubble", title: "Написать нам", sub: "Ответим ежедневно с 10:00 до 22:00", main: true) { router.reset(.account, to: shop.user == nil ? [] : [.support]) }
                if !c["email"].str.isEmpty, let u = URL(string: "mailto:" + c["email"].str) { pill(icon: "envelope", title: c["email"].str, sub: "Почта для вопросов") { UIApplication.shared.open(u) } }
            }
            VStack(spacing: 0) {
                Rectangle().fill(.white.opacity(0.1)).frame(height: 1)
                col("Магазин", shop.visibleCategories.map { c in (c.name, { router.reset(.catalog, to: [.catalog(cat: c.id, tag: nil, sale: false)]) }) }
                    + [("Новинки", { router.reset(.catalog, to: [.catalog(cat: nil, tag: "new", sale: false)]) }), ("Акции", { router.reset(.catalog, to: [.catalog(cat: nil, tag: nil, sale: true)]) })]
                    + (shop.giftEnabled ? [("Подарочные сертификаты", { router.push(.gift, on: .home) })] : []))
                col("Покупателям", [("Где мой заказ", { router.push(.track, on: .home) })]
                    + shop.pages.filter { $0.inFooter && ($0.group.isEmpty || $0.group == "help") }.map { p in (p.title, { router.push(.page(p.slug), on: .home) }) }
                    + [("Таблица размеров", { router.push(.sizes, on: .home) })]
                    + shop.pages.filter { $0.inFooter && $0.group == "brand" }.map { p in (p.title, { router.push(.page(p.slug), on: .home) }) })
                col("Личный кабинет", [("Мои заказы", { router.reset(.account, to: [.orders]) }), ("Избранное", { router.reset(.favorites) })]
                    + (s.bonusEnabled ? [("Бонусы", { router.reset(.account, to: [.bonus]) })] : []) + [("Поддержка", { router.reset(.account, to: [.support]) })])
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("КОНТАКТЫ").font(Theme.font(12, .medium)).kerning(1.6).foregroundStyle(.white.opacity(0.55))
                if !c["phone"].str.isEmpty { contact("phone", c["phone"].str) { if let u = URL(string: "tel:" + c["phone"].str.filter { $0.isNumber || $0 == "+" }) { UIApplication.shared.open(u) } } }
                if !c["email"].str.isEmpty { contact("envelope", c["email"].str) { if let u = URL(string: "mailto:" + c["email"].str) { UIApplication.shared.open(u) } } }
                if !c["address"].str.isEmpty { contact("mappin", c["address"].str, nil) }
                if !c["hours"].str.isEmpty { contact("clock", c["hours"].str, nil) }
            }
            if !s.socials.isEmpty {
                FlowRow(spacing: 8) {
                    ForEach(s.socials) { x in
                        if let u = URL(string: x.url) {
                            Link(destination: u) {
                                HStack(spacing: 8) { SocialIcon(name: x.name, url: x.url, size: 26); Text(x.name).font(Theme.font(14)).foregroundStyle(.white) }
                                    .padding(.leading, 6).padding(.trailing, 14).padding(.vertical, 6)
                                    .background(Capsule().fill(.white.opacity(0.06))).overlay(Capsule().strokeBorder(.white.opacity(0.12)))
                            }
                        }
                    }
                }
            }
            let legal = s.raw["legal"].str.components(separatedBy: CharacterSet(charactersIn: ",;")).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if !legal.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ПРОДАВЕЦ").font(Theme.font(11, .medium)).kerning(1.2).foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 9).padding(.vertical, 4).background(Capsule().fill(.white.opacity(0.08)))
                    ForEach(legal, id: \.self) { Text($0).font(Theme.font(13.5)).foregroundStyle(.white.opacity(0.6)) }
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.03))).overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.1)))
            }
            Text("© \(Calendar.current.component(.year, from: Date())) \(s.storeName)®. Все права защищены. \(s.storeName) — зарегистрированный товарный знак")
                .font(Theme.font(13)).foregroundStyle(.white.opacity(0.45)).lineSpacing(3)
            FlowRow(spacing: 8) {
                ForEach(shop.pages.filter { $0.group == "legal" && $0.inFooter }) { p in
                    Button { router.push(.page(p.slug), on: .home) } label: {
                        Text(p.title).font(Theme.font(12)).foregroundStyle(.white.opacity(0.6)).padding(.horizontal, 12).padding(.vertical, 7).background(Capsule().fill(.white.opacity(0.06)))
                    }
                }
            }
        }
        .padding(.horizontal, 18).padding(.top, 30).padding(.bottom, 36)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                Theme.night
                RadialGradient(colors: [Theme.accentSoft.opacity(0.22), .clear], center: .topLeading, startRadius: 0, endRadius: 320)
                RadialGradient(colors: [Color(hex: "#3a4250").opacity(0.35), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 360)
            }
        )
        .clipShape(TopRounded(radius: 22))
        .padding(.horizontal, 6)
    }
    private func pill(icon: String, title: String, sub: String, main: Bool = false, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 16, weight: .light)).foregroundStyle(.white).frame(width: 44, height: 44)
                    .background(Circle().fill(main ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.white.opacity(0.1))))
                VStack(alignment: .leading, spacing: 2) { Text(title).font(Theme.font(15.5, .medium)).foregroundStyle(.white); Text(sub).font(Theme.font(12.5)).foregroundStyle(.white.opacity(0.55)) }
                Spacer()
            }.padding(8).padding(.trailing, 8)
            .background(Capsule().fill(.white.opacity(0.05))).overlay(Capsule().strokeBorder(.white.opacity(0.12)))
        }.buttonStyle(Pressable())
    }
    private func col(_ title: String, _ items: [(String, () -> Void)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.easeOut(duration: 0.25)) { if open.contains(title) { open.remove(title) } else { open.insert(title) } } } label: {
                HStack {
                    Text(title.uppercased()).font(Theme.font(12.5, .medium)).kerning(1.6).foregroundStyle(.white.opacity(0.62))
                    Spacer()
                    Image(systemName: open.contains(title) ? "minus" : "plus").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 28, height: 28).background(Circle().fill(.white.opacity(0.1)))
                }.padding(.vertical, 18).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if open.contains(title) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, it in Button(action: it.1) { Text(it.0).font(Theme.font(15)).foregroundStyle(.white.opacity(0.82)) } }
                }.padding(.bottom, 18)
            }
            Rectangle().fill(.white.opacity(0.1)).frame(height: 1)
        }
    }
    private func contact(_ icon: String, _ text: String, _ a: (() -> Void)?) -> some View {
        Button { a?() } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 13, weight: .light)).foregroundStyle(.white.opacity(0.75)).frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 9).fill(.white.opacity(0.08)))
                Text(text).font(Theme.font(15)).foregroundStyle(.white.opacity(0.88)).multilineTextAlignment(.leading)
            }
        }.disabled(a == nil)
    }
}

/// Перенос элементов по строкам (для капсул соцсетей и документов)
struct FlowRow: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 360
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > w, x > 0 { x = 0; y += row + spacing; row = 0 }
            x += sz.width + spacing; row = max(row, sz.height)
        }
        return CGSize(width: w, height: y + row)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = b.minX, y = b.minY, row: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > b.maxX, x > b.minX { x = b.minX; y += row + spacing; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing; row = max(row, sz.height)
        }
    }
}

/// Скругление только сверху (iOS 16: без UnevenRoundedRectangle)
struct TopRounded: Shape {
    var radius: CGFloat
    func path(in r: CGRect) -> Path {
        Path(UIBezierPath(roundedRect: r, byRoundingCorners: [.topLeft, .topRight], cornerRadii: CGSize(width: radius, height: radius)).cgPath)
    }
}
