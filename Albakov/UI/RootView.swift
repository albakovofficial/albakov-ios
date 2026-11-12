import SwiftUI

struct RootView: View {
    @EnvironmentObject private var shop: Shop
    @EnvironmentObject private var router: Router
    @State private var askPush = false

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            if shop.loaded {
                MainTabs().transition(.opacity)
            } else if let err = shop.loadError {
                OfflineView(text: err) { Task { await shop.load() } }
            } else {
                SplashView()
            }
            ToastView()
        }
        .animation(.easeOut(duration: 0.35), value: shop.loaded)
        .sheet(isPresented: $askPush) { PushAskSheet().presentationDetents([.medium, .large]) }
        .onChange(of: shop.loaded) { ok in if ok { scheduleAsk() } }
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
            stack(.home) { HomeView() }
                .tabItem { Label("Главная", systemImage: "house") }.tag(Tab.home)
            stack(.catalog) { CatalogRootView() }
                .tabItem { Label("Каталог", systemImage: "square.grid.2x2") }.tag(Tab.catalog)
            stack(.favorites) { FavoritesView() }
                .tabItem { Label("Избранное", systemImage: "heart") }.tag(Tab.favorites)
            stack(.cart) { CartView() }
                .tabItem { Label("Корзина", systemImage: "bag") }.tag(Tab.cart)
                .badge(shop.cartCount)
            stack(.account) { AccountView() }
                .tabItem { Label("Кабинет", systemImage: "person") }.tag(Tab.account)
                .badge(shop.user?.supportUnread ?? 0)
        }
        .tint(Theme.ink)
    }

    // Повторное нажатие на вкладку — к её началу
    private var tabBinding: Binding<Tab> {
        Binding(get: { router.tab }, set: { t in if t == router.tab { router.reset(t) } else { router.tab = t } })
    }

    private func stack<V: View>(_ t: Tab, @ViewBuilder _ root: () -> V) -> some View {
        NavigationStack(path: router.binding(t)) {
            root().navigationDestination(for: Dest.self) { DestView(dest: $0) }
        }
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
        case .adminProducts: AdminProductsView()
        case .adminProduct(let id): AdminProductView(id: id)
        case .adminPush: AdminPushView()
        case .adminAudit: AdminAuditView()
        case .adminCustomers: AdminCustomersView()
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

/// Пример уведомления на «экране телефона»
struct NotificationMock: View {
    let title: String, text: String
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "#2a3036"), Color(hex: "#0d0e10")], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color(hex: "#ff9a5c").opacity(0.38), .clear], center: .topTrailing, startRadius: 0, endRadius: 220)
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
