import SwiftUI

struct RootView: View {
    @EnvironmentObject private var shop: Shop
    @EnvironmentObject private var router: Router
    @Environment(\.scenePhase) private var phase
    @State private var askPush = false
    @State private var update: AppUpdate.Info?
    @State private var checkedAt = Date.distantPast

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            if shop.loaded {
                // Цвет раздела меняется вместе с разделом — экраны перерисовываются (переходы во вкладках хранит Router)
                MainTabs().id(shop.gender ?? "all").transition(.opacity)
            } else if let err = shop.loadError {
                OfflineView(text: err) { Task { await shop.load() } }
            } else {
                SplashView()
            }
            ToastView()
        }
        .animation(.easeOut(duration: 0.35), value: shop.loaded)
        .sheet(isPresented: $askPush) { PushAskSheet().presentationDetents([.medium, .large]) }
        .sheet(item: $update) { UpdateSheet(info: $0).presentationDetents([.medium, .large]) }
        .onChange(of: shop.loaded) { ok in
            guard ok else { return }
            // Проверка на GitHub: приложение запускают с «-screen /catalog» и снимают экраны
            if let screen = UserDefaults.standard.string(forKey: "screen"), !screen.isEmpty { if screen.contains("demo") { shop.demoCart() }; router.open(path: screen) }
            else { Task { let shown = await checkUpdate(); if !shown { scheduleAsk() } } }
        }
        // Вернулись в приложение спустя время — снова проверить, не вышла ли новая версия
        .onChange(of: phase) { p in
            if p == .active, shop.loaded, update == nil, !askPush, Date().timeIntervalSince(checkedAt) > 6 * 3600 { Task { await checkUpdate() } }
        }
    }

    /// Окно «Вышло обновление», если в App Store версия новее установленной
    @discardableResult private func checkUpdate() async -> Bool {
        checkedAt = Date()
        guard let info = await AppUpdate.check() else { return false }
        update = info
        return true
    }

    // Окно «Включите уведомления»: при входе, пока не разрешены; «Не сейчас» — снова через 7 дней, не больше 3 раз
    private func scheduleAsk() {
        let d = UserDefaults.standard
        guard PushManager.shared.status == .notDetermined, d.integer(forKey: "pushAskCount") < 3,
              Date().timeIntervalSince1970 - d.double(forKey: "pushAskAt") > 7 * 86400 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            d.set(d.integer(forKey: "pushAskCount") + 1, forKey: "pushAskCount"); d.set(Date().timeIntervalSince1970, forKey: "pushAskAt")
            askPush = true
        }
    }
}

struct MainTabs: View {
    @EnvironmentObject private var shop: Shop
    @EnvironmentObject private var router: Router

    var body: some View {
        TabView(selection: tabBinding) {
            stack(.home) { HomeView() }.tag(Tab.home)
            stack(.catalog) { CatalogRootView() }.tag(Tab.catalog)
            stack(.favorites) { FavoritesView() }.tag(Tab.favorites)
            stack(.cart) { CartView() }.tag(Tab.cart)
            stack(.account) { AccountView() }.tag(Tab.account)
        }
        .tint(Theme.ink)
        // Своё нижнее меню (13.63): белая капсула, выбранная вкладка — пилюля цвета раздела.
        // Рисуется поверх вкладок, а место под него каждая страница оставляет сама (BarSpace):
        // отступ снаружи TabView до страниц не доходит — кнопки внизу экрана прятались под меню
        .overlay(alignment: .bottom) { AppTabBar(selection: tabBinding) }
        .overlay { drawer }
    }

    // Меню ☰ выезжает слева поверх всего, как на сайте
    private var drawer: some View {
        ZStack(alignment: .leading) {
            if router.menuOpen {
                Color.black.opacity(0.35).ignoresSafeArea().onTapGesture { router.menuOpen = false }.transition(.opacity)
                MenuDrawer().frame(width: min(UIScreen.main.bounds.width * 0.9, 380)).ignoresSafeArea(edges: .bottom)
                    .transition(.move(edge: .leading))
                    .gesture(DragGesture().onEnded { if $0.translation.width < -60 { router.menuOpen = false } })
            }
        }
        .animation(.timingCurve(0.2, 0.7, 0.2, 1, duration: 0.4), value: router.menuOpen)
    }

    // Повторное нажатие на вкладку — к её началу
    private var tabBinding: Binding<Tab> {
        Binding(get: { router.tab }, set: { t in if t == router.tab { router.reset(t) } else { router.tab = t } })
    }

    private func stack<V: View>(_ t: Tab, @ViewBuilder _ root: () -> V) -> some View {
        NavigationStack(path: router.binding(t)) {
            root()
                .toolbar(.hidden, for: .navigationBar)
                .toolbar(.hidden, for: .tabBar)
                .safeAreaInset(edge: .top, spacing: 0) { SiteHeader(tab: t) }
                .overlay(alignment: .bottomTrailing) { if [.home, .catalog, .favorites].contains(t) { ChatFab().padding(.trailing, 14).padding(.bottom, 14) } }
                .modifier(BarSpace())
                .navigationDestination(for: Dest.self) { DestView(dest: $0).toolbar(.hidden, for: .tabBar).modifier(BarSpace()) }
        }
    }
}

/// Место под нижнее меню: содержимое прокручивается под ним, а кнопки внизу экрана стоят над ним
private struct BarSpace: ViewModifier {
    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: AppTabBar.height).allowsHitTesting(false) }
    }
}

/// Нижнее меню (вариант A): значки тонкие; выбранная вкладка — пилюля цвета раздела с подписью; счётчик корзины и ответов поддержки
struct AppTabBar: View {
    /// Высота меню вместе с отступом снизу: пилюля 46 + поля 6 + 6 + 4
    static let height: CGFloat = 62
    @Binding var selection: Tab
    @EnvironmentObject private var shop: Shop
    private let items: [(Tab, String, String)] = [(.home, "Главная", "house"), (.catalog, "Каталог", "square.grid.2x2"), (.favorites, "Избранное", "heart"), (.cart, "Корзина", "bag"), (.account, "Кабинет", "person")]
    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.0) { it in
                let on = selection == it.0
                let n = it.0 == .cart ? shop.cartCount : it.0 == .account ? (shop.user?.supportUnread ?? 0) : 0
                Button { Haptic.tap(); selection = it.0 } label: {
                    HStack(spacing: 7) {
                        Image(systemName: it.2).font(.system(size: 19, weight: .light))
                        if on { Text(it.1).font(Theme.font(13, .medium)).lineLimit(1) }
                    }
                    .foregroundStyle(on ? .white : Theme.text)
                    .padding(.horizontal, on ? 16 : 0).frame(minWidth: 46).frame(height: 46)
                    // Выбранная пилюля всегда по ширине подписи — подпись не вылезает за край
                    .fixedSize()
                    .background(Capsule().fill(on ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.clear)))
                    .overlay(alignment: .topTrailing) {
                        if n > 0 {
                            Text("\(n)").font(Theme.font(10, .semibold)).foregroundStyle(.white).padding(.horizontal, 4).frame(minWidth: 17, minHeight: 17)
                                .background(Capsule().fill(Theme.accentGradient)).overlay(Capsule().strokeBorder(.white, lineWidth: 1.5)).offset(x: on ? 0 : 4, y: -2)
                        }
                    }
                    .frame(maxWidth: on ? nil : .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .layoutPriority(on ? 1 : 0)
                .accessibilityLabel(it.1)
            }
        }
        .padding(6)
        .background(Capsule().fill(.white))
        .overlay(Capsule().strokeBorder(Theme.ink.opacity(0.07), lineWidth: 1))
        .padding(.horizontal, 12).padding(.bottom, 4)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: selection)
    }
}

struct DestView: View {
    let dest: Dest
    var body: some View {
        switch dest {
        case .product(let id): ProductView(id: id)
        case .catalog(let cat, let tag, let sale): CatalogView(cat: cat, tag: tag, sale: sale)
        case .search: SearchView()
        case .page(let slug): PageView(slug: slug)
        case .sizes: SizesView()
        case .gift: GiftView()
        case .track: TrackView()
        case .checkout: CheckoutView()
        case .orders: OrdersView()
        case .order(let id): OrderView(id: id)
        case .support: SupportListView()
        case .ticket(let id): TicketView(id: id)
        case .bonus: BonusView()
        case .profile: ProfileView()
        case .notifications: NotificationsView()
        case .admin: AdminHomeView()
        case .adminOrders: AdminOrdersView()
        case .adminOrder(let id): AdminOrderView(id: id)
        case .adminSupport: AdminSupportView()
        case .adminTicket(let id): AdminTicketView(id: id)
        case .adminProducts: CollectionList(cfg: AdminProduct.cfg)
        case .adminProduct(let id): CollectionEdit(cfg: AdminProduct.cfg, id: id)
        case .adminPush: AdminPushView()
        case .adminAudit: AdminAuditView()
        case .adminCustomers: AdminCustomersView()
        case .adminSection(let k): AdminSections.view(k)
        case .adminItem(let k, let id): AdminSections.item(k, id)
        }
    }
}

// Заставка: знак AV и ALBAKOV, как в шапке сайта, под ними тонкая линия загрузки
struct BrandMark: View {
    var body: some View {
        VStack(spacing: 22) {
            Image("Logo").resizable().scaledToFit().frame(width: 84, height: 84)
            HStack(alignment: .top, spacing: 2) {
                Image("Wordmark").resizable().scaledToFit().frame(width: 150)
                Text("®").font(.system(size: 6)).foregroundStyle(Theme.ink.opacity(0.85)).offset(y: -3)
            }
        }
    }
}

struct SplashView: View {
    @State private var progress: CGFloat = 0
    var body: some View {
        VStack(spacing: 28) {
            BrandMark()
            ZStack(alignment: .leading) {
                Rectangle().fill(Theme.ink.opacity(0.12))
                Rectangle().fill(Theme.ink).frame(width: 150 * progress)
            }.frame(width: 150, height: 1)
        }
        .onAppear { withAnimation(.timingCurve(0.25, 0.7, 0.3, 1, duration: 2.6)) { progress = 0.82 } }
    }
}

struct OfflineView: View {
    let text: String
    let retry: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.slash").font(.system(size: 30, weight: .light)).frame(width: 80, height: 80).background(Circle().fill(Theme.surface))
            Text("Нет соединения").font(Theme.font(22, .light))
            Text(text).font(Theme.font(14)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            PrimaryButton(title: "Повторить", action: retry).frame(maxWidth: 260).padding(.top, 8)
        }.padding(32)
    }
}

struct PushAskSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var shop: Shop
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            NotificationMock(title: shop.isStaff ? "Новый заказ № 1042 · 5 798 ₽" : "Заказ ждёт в пункте выдачи",
                             text: shop.isStaff ? "Анна Смирнова, Москва\nФутболка AV, чёрная, L" : "Пункт СДЭК · Тверская, 1. Можно примерить на месте")
            Text("Включите уведомления").font(Theme.font(26, .light))
            VStack(alignment: .leading, spacing: 10) {
                ForEach(shop.isStaff ? ["Новые заказы и оплаты — сразу", "Вопросы покупателей и заявки на обмен", "Заканчиваются размеры, итоги дня"]
                                     : ["Заказ в пути и ждёт в пункте выдачи", "Ответы поддержки и обмен размера", "Без рекламы — акции только по желанию"], id: \.self) { t in
                    HStack(alignment: .top, spacing: 10) { Image(systemName: "checkmark").font(.system(size: 13, weight: .medium)).padding(.top, 2); Text(t).font(Theme.font(15)).foregroundStyle(Theme.muted) }
                }
            }
            Spacer(minLength: 0)
            PrimaryButton(title: "Включить уведомления") { Task { await PushManager.shared.request(); dismiss() } }
            GhostButton(title: "Не сейчас") { dismiss() }
        }
        .padding(20)
    }
}

/// Новая версия в App Store: номер последней версии Apple отдаёт по Bundle ID (TestFlight сюда не попадает)
enum AppUpdate {
    struct Info: Identifiable { let version: String, notes: String, url: URL; var id: String { version } }
    static var installed: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

    static func check() async -> Info? {
        guard let id = Bundle.main.bundleIdentifier, let u = URL(string: "https://itunes.apple.com/lookup?bundleId=\(id)&country=ru") else { return nil }
        let req = URLRequest(url: u, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        guard let res = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: res.0) as? [String: Any],
              let r = (json["results"] as? [[String: Any]])?.first,
              let v = r["version"] as? String, newer(v, than: installed),
              let link = (r["trackViewUrl"] as? String).flatMap({ URL(string: $0) }) else { return nil }
        return Info(version: v, notes: ((r["releaseNotes"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines), url: link)
    }

    /// 2.1.10 новее 2.1.9: сравниваем числа по порядку
    static func newer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }
}

/// Окно «Вышло обновление»: значок приложения, номер версии, что нового, кнопка в App Store
struct UpdateSheet: View {
    let info: AppUpdate.Info
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image("AppIconSmall").resizable().frame(width: 62, height: 62).clipShape(RoundedRectangle(cornerRadius: 15))
                VStack(alignment: .leading, spacing: 4) {
                    Text("ALBAKOV").font(Theme.font(12, .medium)).kerning(1.6).foregroundStyle(Theme.muted)
                    Text("Версия \(info.version)").font(Theme.font(13, .medium)).foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4).background(Capsule().fill(Theme.accentGradient))
                }
            }
            Text("Вышло обновление").font(Theme.font(26, .light))
            Text("Обновите приложение, чтобы всё работало как надо.\nНовая версия уже в App Store.").font(Theme.font(15)).foregroundStyle(Theme.muted)
            if !info.notes.isEmpty {
                ScrollView {
                    Text(info.notes).font(Theme.font(14)).foregroundStyle(Theme.text).frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 140).padding(14)
                .background(RoundedRectangle(cornerRadius: 18).fill(Theme.surface)).hairline(RoundedRectangle(cornerRadius: 18), 0.06)
            }
            Spacer(minLength: 0)
            PrimaryButton(title: "Обновить") { UIApplication.shared.open(info.url) }
            GhostButton(title: "Позже") { dismiss() }
        }
        .padding(20)
    }
}

/// Пример уведомления на «экране телефона»
struct NotificationMock: View {
    let title: String, text: String
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "#2a3036"), Color(hex: "#0d0e10")], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Theme.accentSoft.opacity(0.38), .clear], center: .topTrailing, startRadius: 0, endRadius: 220)
            VStack(spacing: 14) {
                Text(Date(), style: .time).font(.system(size: 44, weight: .light)).foregroundStyle(.white.opacity(0.92))
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image("AppIconSmall").resizable().frame(width: 20, height: 20).clipShape(RoundedRectangle(cornerRadius: 5))
                        Text("ALBAKOV").font(.system(size: 11, weight: .semibold)).kerning(1.4)
                        Spacer(); Text("сейчас").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Text(title).font(.system(size: 14, weight: .semibold))
                    Text(text).font(.system(size: 13.5)).foregroundStyle(Color(hex: "#2d3238")).lineLimit(3)
                }
                .padding(14).background(RoundedRectangle(cornerRadius: 20).fill(.ultraThinMaterial))
                .background(RoundedRectangle(cornerRadius: 20).fill(.white.opacity(0.55)))
            }.padding(16)
        }
        .frame(height: 200).clipShape(RoundedRectangle(cornerRadius: 24))
    }
}
