import SwiftUI

struct RootView: View {
    @EnvironmentObject private var shop: Shop
    @EnvironmentObject private var router: Router
    @Environment(\.scenePhase) private var phase
    @State private var askPush = false
    @State private var update: AppUpdate.Info?
    @State private var checkedAt = Date.distantPast
    // Заставка: главная раскрывается кругом от знака, когда каталог загружен и заставка показана не меньше 1,2 с
    @State private var splashShown = false
    @State private var reveal: CGFloat = 0
    @State private var splashDone = false

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            if !splashDone { SplashView(slow: !shop.loaded && shop.loadError == nil) }
            if shop.loaded {
                // Цвет раздела меняется вместе с разделом — экраны перерисовываются (переходы во вкладках хранит Router)
                MainTabs().id(shop.gender ?? "all").mask(CircleReveal(progress: reveal))
            } else if let err = shop.loadError {
                OfflineView(text: err) { Task { await shop.load() } }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.white.ignoresSafeArea())
            }
            ToastView()
        }
        .background(KeyboardDismisser())
        .task { try? await Task.sleep(nanoseconds: 1_200_000_000); splashShown = true; revealIfReady() }
        .sheet(isPresented: $askPush) { PushAskSheet().presentationDetents([.medium, .large]) }
        .fullScreenCover(item: $update) { UpdateView(info: $0) }
        .onChange(of: shop.loaded) { ok in
            guard ok else { return }
            revealIfReady()
            #if DEBUG
            // Проверка на GitHub: приложение запускают с «-screen /catalog» и снимают экраны (только сборка Debug)
            if let screen = UserDefaults.standard.string(forKey: "screen"), !screen.isEmpty {
                if screen.contains("demo") { shop.demoCart() }; router.open(path: screen)
                // Снимок окна «Вышло обновление»: «-screen "/?update=1"»
                if screen.contains("update=1") { update = AppUpdate.Info(version: "1.0.1", notes: "Новое:\n— поддержка с номером обращения и фото\n— у каждой вещи своя таблица размеров\n— раздел «О бренде»\nИсправили: мелкие недочёты — всё работает стабильно", url: URL(string: "https://apps.apple.com/ru/")!) }
                return
            }
            #endif
            Task { let shown = await checkUpdate(); if !shown { scheduleAsk() } }
        }
        // Вернулись в приложение спустя время — снова проверить, не вышла ли новая версия
        .onChange(of: phase) { p in
            if p == .active, shop.loaded, update == nil, !askPush, Date().timeIntervalSince(checkedAt) > 6 * 3600 { Task { await checkUpdate() } }
            // цены и остатки могли измениться, пока приложение было свёрнуто (1.0.2)
            if p == .active, shop.loaded, Date().timeIntervalSince(shop.loadedAt) > 600 { Task { await shop.load() } }
        }
    }

    private func revealIfReady() {
        guard shop.loaded, splashShown, reveal == 0 else { return }
        withAnimation(.timingCurve(0.6, 0, 0.2, 1, duration: 0.75)) { reveal = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { splashDone = true }
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
    @State private var keyboard = false

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
        // Пока открыта клавиатура, нижнее меню прячется — иначе оно едет вверх вместе с ней
        .overlay(alignment: .bottom) { if !keyboard { AppTabBar(selection: tabBinding).transition(.opacity) } }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in withAnimation(.easeOut(duration: 0.2)) { keyboard = true } }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in withAnimation(.easeOut(duration: 0.2)) { keyboard = false } }
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

/// Нажатие мимо поля ввода закрывает клавиатуру (1.0.0): один распознаватель на всё окно, нажатия кнопок он не перехватывает
private struct KeyboardDismisser: UIViewRepresentable {
    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ uiView: Probe, context: Context) {}
    final class Probe: UIView, UIGestureRecognizerDelegate {
        private weak var installed: UIWindow?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let w = window, installed !== w else { return }
            let tap = UITapGestureRecognizer(target: self, action: #selector(hide))
            tap.cancelsTouchesInView = false
            tap.delegate = self
            w.addGestureRecognizer(tap); installed = w
        }
        @objc private func hide() { window?.endEditing(true) }
        // Нажатие в само поле (или в другое поле) клавиатуру не закрывает
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var v = touch.view
            while let x = v { if x is UITextField || x is UITextView { return false }; v = x.superview }
            return true
        }
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
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
                // панель вкладок не растёт с крупным системным шрифтом — иначе не помещается на узком экране (аудит 16.11, M-7)
                .dynamicTypeSize(...DynamicTypeSize.xLarge)
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
/// Фон в цветах значка: бордо слева сверху, синий справа снизу, графит посередине (заставка, окно «Вышло обновление»)
struct BrandBackground: View {
    var body: some View {
        ZStack {
            Color(hex: "#121419")
            RadialGradient(colors: [Color(hex: "#821f35").opacity(0.95), .clear], center: UnitPoint(x: -0.1, y: -0.05), startRadius: 0, endRadius: 420)
            RadialGradient(colors: [Color(hex: "#3a78b7").opacity(0.75), .clear], center: UnitPoint(x: 1.1, y: 1.05), startRadius: 0, endRadius: 460)
        }
        .ignoresSafeArea()
    }
}

/// Заставка при входе (вариант B, 14.11): знак проступает из размытия и вспыхивает, надпись ALBAKOV выезжает слева
struct SplashView: View {
    /// Каталог ещё грузится — через 4 секунды показываем «Загружаем каталог…», чтобы не было ощущения зависания (аудит 16.11, L-14)
    var slow = false
    @State private var long = false
    @State private var mark = false
    @State private var word = false
    @State private var glow = false
    var body: some View {
        ZStack {
            BrandBackground()
            VStack(spacing: 26) {
                Image("Logo").resizable().scaledToFit().frame(width: 96, height: 96).colorInvert()
                    .shadow(color: .white.opacity(glow ? 0.45 : 0), radius: glow ? 22 : 0)
                    .blur(radius: mark ? 0 : 14).scaleEffect(mark ? 1 : 1.18).opacity(mark ? 1 : 0)
                Image("Wordmark").resizable().scaledToFit().frame(width: 170).colorInvert()
                    .mask(Rectangle().scaleEffect(x: word ? 1 : 0.001, anchor: .leading))
                    .opacity(word ? 1 : 0)
            }
            .offset(y: -20)
            if slow && long {
                VStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text("Загружаем каталог…").font(Theme.font(13)).foregroundStyle(.white.opacity(0.8))
                }
                .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 70)
                .transition(.opacity)
            }
        }
        .task { try? await Task.sleep(nanoseconds: 4_000_000_000); withAnimation(.easeOut(duration: 0.4)) { long = true } }
        .onAppear {
            withAnimation(.timingCurve(0.2, 0.7, 0.2, 1, duration: 0.9)) { mark = true }
            withAnimation(.timingCurve(0.3, 0.7, 0.2, 1, duration: 0.7).delay(0.35)) { word = true }
            withAnimation(.easeInOut(duration: 0.7).delay(0.7)) { glow = true }
        }
    }
}

/// Маска «круг из центра знака»: 0 — ничего не видно, 1 — весь экран
struct CircleReveal: View {
    let progress: CGFloat
    var body: some View {
        GeometryReader { g in
            let d = hypot(g.size.width, g.size.height) * 1.15 * progress
            Circle().frame(width: d, height: d).position(x: g.size.width / 2, y: g.size.height * 0.46)
        }
        .ignoresSafeArea()
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

/// Окно «Вышло обновление» (1.0.1, вариант A): весь экран в цветах значка, светящийся знак, номер версии,
/// «Что нового» из App Store на стеклянной карточке; строки «Новое: …» и «Исправили: …» — отдельными пунктами
struct UpdateView: View {
    let info: AppUpdate.Info
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Знак, заголовок и список — посередине между верхом экрана и кнопками
            Spacer(minLength: 24)
            Image("Logo").resizable().scaledToFit().frame(width: 84).colorInvert()
                .shadow(color: .white.opacity(0.35), radius: 16)
            Text("ВЕРСИЯ \(info.version)").font(Theme.font(12.5, .semibold)).kerning(2.5)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Capsule().fill(.white.opacity(0.1))).overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
                .padding(.top, 24)
            Text("Вышло обновление").font(Theme.font(36, .light)).kerning(-0.8).multilineTextAlignment(.center).padding(.top, 18)
            Text("Обновите приложение, чтобы всё работало как надо. Новая версия уже в App Store.")
                .font(Theme.font(14.5)).foregroundStyle(.white.opacity(0.66)).multilineTextAlignment(.center).lineSpacing(3).padding(.top, 12)
            let items = Self.items(info.notes)
            if !items.isEmpty {
                // Короткий список — карточка по высоте текста, длинный — листается внутри карточки
                ViewThatFits(in: .vertical) {
                    card(items)
                    ScrollView(showsIndicators: false) { card(items) }.clipShape(RoundedRectangle(cornerRadius: 24))
                }
                .padding(.top, 26)
            }
            Spacer(minLength: 20)
            // «Обновить» — страница ALBAKOV в приложении App Store
            Button { UIApplication.shared.open(info.url) } label: {
                Text("Обновить").font(Theme.font(16, .semibold)).foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity).frame(height: 56).background(Capsule().fill(.white))
            }.buttonStyle(.plain)
            Button("Позже") { dismiss() }.font(Theme.font(14.5, .medium)).foregroundStyle(.white.opacity(0.7)).padding(.top, 16).padding(.bottom, 8)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BrandBackground())
        .preferredColorScheme(.dark)
    }

    private func card(_ items: [(text: String, fix: Bool)]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ЧТО НОВОГО").font(Theme.font(11.5, .semibold)).kerning(2).foregroundStyle(.white.opacity(0.55))
            ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: it.fix ? "checkmark" : "sparkle").font(.system(size: 10, weight: .semibold))
                        .frame(width: 22, height: 22).background(Circle().fill(.white.opacity(0.12)))
                    Text(it.text).font(Theme.font(14.5)).lineSpacing(2).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 24).fill(.white.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.12), lineWidth: 1))
    }

    /// «Что нового» из App Store → пункты: «Новое: …» и «Исправили: …» начинают группу, «— …» и «• …» — пункты внутри
    static func items(_ notes: String) -> [(text: String, fix: Bool)] {
        var out: [(text: String, fix: Bool)] = [], fix = false
        for raw in notes.components(separatedBy: .newlines) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            let low = line.lowercased()
            if low.hasPrefix("новое:") { fix = false; line = String(line.dropFirst(6)) }
            else if low.hasPrefix("изменили:") { fix = false; line = String(line.dropFirst(9)) }
            else if low.hasPrefix("улучшили:") { fix = false; line = String(line.dropFirst(9)) }
            else if low.hasPrefix("исправили:") { fix = true; line = String(line.dropFirst(10)) }
            line = line.trimmingCharacters(in: CharacterSet(charactersIn: " —-–•·")).trimmingCharacters(in: .whitespaces)
            if let f = line.first { out.append((f.uppercased() + line.dropFirst(), fix)) }   // с заглавной: «— поддержка …» → «Поддержка …»
        }
        return out
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
