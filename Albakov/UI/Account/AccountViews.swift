import SwiftUI

// Кабинет: вход и регистрация, заказы, бонусы, поддержка, профиль, уведомления; сотрудникам — панель
struct AccountView: View {
    @EnvironmentObject private var shop: Shop
    @EnvironmentObject private var router: Router
    @State private var tab = "orders"
    @State private var orders: [Order] = []
    @State private var bonusLog: [JSON] = []
    /// Заказы или история бонусов не загрузились (Q-3): вместо «пока нет» — причина и «Повторить». Ошибки раздельные:
    /// сбой одного запроса не должен выдавать себя за пустоту или ошибку другого (ревью этапа B)
    @State private var ordersError: String?
    @State private var bonusError: String?
    @State private var confirmLogout = false
    @State private var payURL: URL?

    var body: some View {
        if let u = shop.user {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    card(u).padding(.top, 16)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        tile("shippingbox", "Заказы", ordersSub, on: tab == "orders") { withAnimation { tab = "orders" } }
                        tile("heart", "Избранное", "\(shop.favorites.count) \(Fmt.plural(shop.favorites.count, "товар", "товара", "товаров"))", on: tab == "favorites") { withAnimation { tab = "favorites" } }
                        tile("arrow.left.arrow.right", "Обмен и возврат", "оформить по своему заказу", on: tab == "exchange") { withAnimation { tab = "exchange" } }
                        tile("text.bubble", "Поддержка", "ответим в чате", dot: u.supportUnread > 0) { router.push(.support, on: .account) }
                    }
                    if tab == "exchange" { Text("Откройте заказ и нажмите «Обменять размер или вернуть».").font(Theme.font(14)).foregroundStyle(Theme.muted).padding(.top, 6) }
                    content(u).padding(.top, 8)
                    more.padding(.top, 22)
                }.padding(.horizontal, Theme.gutter).padding(.bottom, 40)
            }
            .refreshable { await load() }
            .task { await load() }
            .paymentSheet($payURL) { Task { await load() } }
        } else {
            AuthView()
        }
    }

    /// Карточка покупателя (13.63): цвет раздела, инициал, имя, «с нами с…», бонусы на счёте
    private func card(_ u: User) -> some View {
        let name = [u.firstName, u.lastName].filter { !$0.isEmpty }.joined(separator: " ")
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Text(String((u.firstName.isEmpty ? "П" : u.firstName).prefix(1)).uppercased()).font(Theme.font(19, .medium))
                    .frame(width: 48, height: 48).background(Circle().fill(.white.opacity(0.18))).overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 1))
                VStack(alignment: .leading, spacing: 2) {
                    Text(name.isEmpty ? "Покупатель" : name).font(Theme.font(17, .medium)).lineLimit(2)
                    Text("С нами с " + Fmt.monthYear(u.createdAt)).font(Theme.font(12.5)).opacity(0.8)
                }
                Spacer(minLength: 4)
                Button { router.push(.profile, on: .account) } label: {
                    Image(systemName: "pencil").font(.system(size: 15, weight: .light)).frame(width: 38, height: 38).background(Circle().fill(.white.opacity(0.14)))
                }.buttonStyle(Pressable()).accessibilityLabel("Профиль")
            }
            if shop.settings.bonusEnabled {
                Button { withAnimation { tab = "bonus" } } label: {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 2) { Text("Бонусы на счёте").font(Theme.font(12)).opacity(0.8); Text(Fmt.num(u.bonus)).font(Theme.font(36, .light)) }
                        Spacer()
                        Text("1 бонус = 1 ₽\nможно оплатить весь заказ").font(Theme.font(11.5)).multilineTextAlignment(.trailing).opacity(0.82)
                    }
                    .padding(.top, 14).overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.2)).frame(height: 1) }
                }.buttonStyle(.plain)
            }
        }
        .foregroundStyle(.white).padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 26).fill(Theme.accentGradient)
            .overlay(RoundedRectangle(cornerRadius: 26).fill(RadialGradient(colors: [.white.opacity(0.18), .clear], center: .topLeading, startRadius: 0, endRadius: 260))))
    }
    private var ordersSub: String {
        let active = orders.filter { !["done", "canceled", "returned"].contains($0.status) }.count
        return active > 0 ? "\(active) в пути и в работе" : orders.isEmpty ? "пока нет" : "\(orders.count) \(Fmt.plural(orders.count, "заказ", "заказа", "заказов"))"
    }
    private func tile(_ icon: String, _ title: String, _ sub: String, on: Bool = false, dot: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button { Haptic.tap(); action() } label: {
            VStack(alignment: .leading, spacing: 2) {
                IconTile(icon: icon, size: 38, fill: Theme.tint, tint: Theme.accent).padding(.bottom, 10)
                Text(title).font(Theme.font(15, .medium)).foregroundStyle(Theme.text)
                Text(sub).font(Theme.font(12)).foregroundStyle(Theme.dim).lineLimit(1)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20).fill(on ? AnyShapeStyle(Color.white) : AnyShapeStyle(Theme.tile)))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(on ? Theme.accent : Theme.ink.opacity(0.06), lineWidth: on ? 1.5 : 1))
            .overlay(alignment: .topTrailing) { if dot { Circle().fill(Theme.accentGradient).frame(width: 9, height: 9).overlay(Circle().strokeBorder(.white, lineWidth: 2)).padding(12) } }
        }.buttonStyle(Pressable())
    }
    /// Короткий список внизу: профиль, уведомления, панель (сотрудникам), выход
    private var more: some View {
        VStack(spacing: 0) {
            row("person", "Профиль и пароль") { router.push(.profile, on: .account) }
            row("bell", "Уведомления") { router.push(.notifications, on: .account) }
            if shop.isStaff { row("square.grid.2x2", "Панель управления") { router.push(.admin, on: .account) } }
            Button { confirmLogout = true } label: {
                HStack(spacing: 12) { Image(systemName: "rectangle.portrait.and.arrow.right").font(.system(size: 16, weight: .light)).frame(width: 22); Text("Выйти").font(Theme.font(15)); Spacer() }
                    .foregroundStyle(Theme.accent).padding(.horizontal, 16).frame(height: 52).contentShape(Rectangle())
            }.buttonStyle(.plain)
            // Окно подтверждения привязано к самой строке «Выйти»: на iOS 26 оно всплывает у кнопки, а не вверху экрана
            .confirmationDialog("Выйти из кабинета?", isPresented: $confirmLogout, titleVisibility: .visible) {
                Button("Выйти", role: .destructive) { Task { await shop.logout() } }
            }
        }
        .background(RoundedRectangle(cornerRadius: 20).fill(Theme.tile)).hairline(RoundedRectangle(cornerRadius: 20), 0.06)
    }
    private func row(_ icon: String, _ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 16, weight: .light)).frame(width: 22)
                Text(title).font(Theme.font(15)); Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Theme.dim)
            }
            .foregroundStyle(Theme.text).padding(.horizontal, 16).frame(height: 52)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, 50) }
        }.buttonStyle(.plain)
    }
    @ViewBuilder
    private func content(_ u: User) -> some View {
        switch tab {
        case "favorites":
            let list = shop.favorites.compactMap { id in shop.products.first { $0.id == id } }
            if list.isEmpty { EmptyState(icon: "heart", title: "Здесь пока пусто", text: "Нажимайте на сердечко у понравившихся вещей — они соберутся здесь.", button: "Перейти в каталог") { router.reset(.catalog) }.padding(.horizontal, -Theme.gutter) }
            else { ProductGrid(products: list, tab: .account).padding(.horizontal, -Theme.gutter) }
        case "bonus":
            VStack(alignment: .leading, spacing: 18) {
                LoyalCard().padding(.vertical, 10)
                Text("Начисляем \(shop.settings.bonusPercent)% с каждой покупки" + (shop.settings.bonusOnlineExtra > 0 ? " и ещё \(shop.settings.bonusOnlineExtra)% при оплате онлайн" : "") + ". 1 бонус = 1 ₽ — списать можно при оформлении следующего заказа.")
                    .font(Theme.font(14.5)).foregroundStyle(Theme.muted)
                if bonusLog.isEmpty { if let bonusError { ErrorRetry(text: "История не загрузилась: " + bonusError) { Task { await load() } } } else { Text("Пока нет начислений").font(Theme.font(14)).foregroundStyle(Theme.muted) } }
                VStack(spacing: 0) {
                    ForEach(Array(bonusLog.enumerated()), id: \.offset) { _, e in
                        let a = e["amount"].int ?? 0
                        HStack {
                            VStack(alignment: .leading, spacing: 3) { Text(BonusView.label(e)).font(Theme.font(14.5)); Text(Fmt.date(ISO.date(e["at"].str))).font(Theme.font(12)).foregroundStyle(Theme.muted) }
                            Spacer()
                            Text((a > 0 ? "+" : "") + "\(a)").font(Theme.font(15, .medium)).foregroundStyle(a > 0 ? Theme.ok : Theme.text)
                        }.padding(.vertical, 12).overlay(alignment: .bottom) { Divider1() }
                    }
                }
            }
        default:
            if orders.isEmpty, let ordersError {
                EmptyState.loadFailed(ordersError) { Task { await load() } }.padding(.horizontal, -Theme.gutter)
            } else if orders.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    IconTile(icon: "bag", size: 44, fill: .white, tint: Theme.accent).padding(.bottom, 4)
                    Text("У Вас пока нет заказов").font(Theme.font(19, .medium))
                    Text("Здесь будут отображаться Ваши покупки и информация об их текущем статусе").font(Theme.font(13.5)).foregroundStyle(Theme.muted).lineSpacing(3)
                    PrimaryButton(title: "Перейти в каталог", height: 46) { router.reset(.catalog) }.frame(width: 210).padding(.top, 6)
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 22).fill(Theme.tile)).hairline(RoundedRectangle(cornerRadius: 22), 0.06)
            } else {
                VStack(spacing: 10) {
                    ForEach(orders) { o in
                        OrderCard(order: o, open: { router.push(.order(o.id), on: .account) }, pay: { payURL = $0 }).padding(14).softCard(18)
                    }
                }
            }
        }
    }
    private func load() async {
        await shop.refreshUser()
        do {
            orders = try await API.shared.json("GET", "orders")["orders"].array.map(Order.init)
            orders.forEach { shop.returnExpired($0) }
            ordersError = nil
        } catch {
            if let m = error.userMessage { if orders.isEmpty { ordersError = m } else { Toast.shared.show(m) } }   // заказы уже на экране — оставляем их
        }
        do { bonusLog = try await API.shared.json("GET", "me")["bonusLog"].array; bonusError = nil }
        catch {
            guard let m = error.userMessage else { return }   // загрузку отменили (ушли с экрана)
            if bonusLog.isEmpty { bonusError = m } else { Toast.shared.show(m) }   // история уже на экране — оставляем её
        }
    }
}

struct AuthView: View {
    @EnvironmentObject private var shop: Shop
    @EnvironmentObject private var router: Router
    enum Mode { case login, register, forgot }
    @State private var mode: Mode = .login
    @State private var login = ""
    @State private var password = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var consent = false
    @State private var busy = false
    @State private var error: String?
    @State private var code: CodeStep?

    struct CodeStep: Identifiable { let id: String; let email: String; let kind: String; var resetPassword = "" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Eyebrow(text: "Личный кабинет")
                DotTitle(text: mode == .login ? "Вход" : mode == .register ? "Регистрация" : "Новый пароль", size: 36)
                if mode != .forgot {
                    Segmented(items: [("login", "Вход"), ("register", "Регистрация")], value: Binding(get: { mode == .register ? "register" : "login" }, set: { mode = $0 == "register" ? .register : .login; error = nil }))
                }
                Text(mode == .login ? "Заказы, бонусы и поддержка — в одном месте." : mode == .register ? "Бонусы с каждой покупки и история заказов." : "Пришлём код на почту — введите его и задайте новый пароль.")
                    .font(Theme.font(14.5)).foregroundStyle(Theme.muted)
                switch mode {
                case .login:
                    Field(label: "Телефон или электронная почта", text: $login, keyboard: .emailAddress, content: .username, capitalization: .never)
                    Field(label: "Пароль", text: $password, content: .password, secure: true)
                case .register:
                    HStack(spacing: 10) { Field(label: "Имя", text: $firstName, content: .givenName); Field(label: "Фамилия", text: $lastName, content: .familyName) }
                    Field(label: "Телефон", text: $phone, placeholder: "+7", keyboard: .phonePad, content: .telephoneNumber)
                    Field(label: "Почта", text: $email, keyboard: .emailAddress, content: .emailAddress, capitalization: .never)
                    Field(label: "Пароль — от 6 символов", text: $password, content: .newPassword, secure: true)
                    Toggle(isOn: $consent) { Text("Даю согласие на обработку персональных данных").font(Theme.font(13.5)).foregroundStyle(Theme.muted) }.tint(Theme.ink)
                case .forgot:
                    Field(label: "Телефон или почта", text: $login, keyboard: .emailAddress, content: .username, capitalization: .never)
                }
                ErrorText(text: error)
                PrimaryButton(title: mode == .login ? "Войти" : mode == .register ? "Зарегистрироваться" : "Получить код", busy: busy) { Task { await submit() } }
                if mode == .login {
                    HStack(spacing: 18) {
                        LinkButton(title: "Забыли пароль?", color: Theme.muted) { mode = .forgot; error = nil }
                        LinkButton(title: "Где мой заказ — без входа", color: Theme.muted) { router.push(.track, on: .account) }
                    }.padding(.horizontal, 4)
                    HStack(spacing: 4) { Text("Нет аккаунта?").font(Theme.font(14)).foregroundStyle(Theme.muted); LinkButton(title: "Зарегистрируйтесь") { mode = .register; error = nil } }.padding(.top, 6)
                } else {
                    LinkButton(title: "У меня есть аккаунт", color: Theme.muted) { mode = .login; error = nil }
                }
            }
            .padding(Theme.gutter).padding(.top, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .sheet(item: $code) { step in CodeSheet(step: step) { j in code = nil; shop.signedIn(j) } }
    }

    private func submit() async {
        busy = true; error = nil; defer { busy = false }
        do {
            switch mode {
            case .login:
                let r = try await API.shared.json("POST", "auth/login", body: ["login": login, "password": password])
                if r["confirm"].exists { code = CodeStep(id: r["confirm"]["id"].str, email: r["confirm"]["email"].str, kind: "login") }
                else { shop.signedIn(r); Haptic.success() }
            case .register:
                let r = try await API.shared.json("POST", "auth/register", body: ["firstName": firstName, "lastName": lastName, "phone": phone, "email": email, "password": password, "consent": consent])
                if r["pending"].exists { code = CodeStep(id: r["pending"]["id"].str, email: r["pending"]["email"].str, kind: "register") }
                else { shop.signedIn(r); Haptic.success() }
            case .forgot:
                let r = try await API.shared.json("POST", "auth/forgot", body: ["login": login])
                code = CodeStep(id: r["id"].str, email: r["email"].str, kind: "reset")
            }
        } catch { self.error = error.userMessage; Haptic.error() }
    }
}

struct CodeSheet: View {
    let step: AuthView.CodeStep
    let done: (JSON) -> Void
    @State private var code = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focus: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(step.kind == "login" ? "Подтвердите вход" : step.kind == "reset" ? "Новый пароль" : "Подтвердите почту").font(Theme.font(26, .light))
            Text(step.kind == "login" ? "Вы входите с нового устройства в аккаунт с доступом к панели. Отправили код на \(step.email)." : "Отправили код из 6 цифр на \(step.email).")
                .font(Theme.font(14)).foregroundStyle(Theme.muted)
            TextField("000000", text: $code).font(.system(size: 30, weight: .light, design: .monospaced)).kerning(10)
                .keyboardType(.numberPad).textContentType(.oneTimeCode).focused($focus)
                .padding(.horizontal, 16).frame(height: 64).background(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.line))
                .onChange(of: code) { v in code = String(v.filter(\.isNumber).prefix(6)) }
            if step.kind == "reset" { Field(label: "Новый пароль — от 6 символов", text: $password, content: .newPassword, secure: true) }
            ErrorText(text: error)
            PrimaryButton(title: "Подтвердить", busy: busy, disabled: code.count != 6) { Task { await send() } }
            Spacer()
        }
        .padding(20)
        .presentationDetents([.medium, .large])
        .onAppear { focus = true }
    }
    private func send() async {
        busy = true; error = nil; defer { busy = false }
        do {
            let path = step.kind == "login" ? "auth/login-confirm" : step.kind == "reset" ? "auth/reset" : "auth/verify"
            var b: [String: Any] = ["id": step.id, "code": code]
            if step.kind == "reset" { b["password"] = password }
            let r = try await API.shared.json("POST", path, body: b)
            Haptic.success(); done(r)
        } catch { self.error = error.userMessage; Haptic.error() }
    }
}

// MARK: - Заказы
struct OrdersView: View {
    @EnvironmentObject private var shop: Shop
    @EnvironmentObject private var router: Router
    @State private var orders: [Order] = []
    @State private var loading = true
    @State private var error: String?
    @State private var payURL: URL?
    var body: some View {
        List {
            if let error { Text(error).font(Theme.font(14)).foregroundStyle(Theme.danger) }
            if !loading && orders.isEmpty && error == nil {
                EmptyState(icon: "shippingbox", title: "У Вас пока нет заказов", text: "Здесь будут отображаться Ваши покупки и информация об их текущем статусе").listRowSeparator(.hidden)
            }
            ForEach(orders) { o in
                OrderCard(order: o, open: { router.push(.order(o.id), on: .account) }, pay: { payURL = $0 }).buttonStyle(.borderless)
            }
        }
        .listStyle(.plain)
        .paymentSheet($payURL) { Task { await load() } }
        .overlay { if loading { ProgressView() } }
        .navigationTitle("Мои заказы").navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }
    private func load() async {
        do {
            if shop.user != nil { orders = try await API.shared.json("GET", "orders")["orders"].array.map(Order.init) }
            else {   // без кабинета — заказы, оформленные на этом телефоне
                var list: [Order] = []
                for (id, t) in OrderTokens.all {
                    do { list.append(Order(try await API.shared.json("GET", "orders/\(id)", query: ["t": t])["order"])) }
                    catch let e as APIError where e.status == 404 || e.status == 403 { continue }   // заказ удалён или ссылка больше не действует
                    // остальные ошибки (нет связи, сбой) — наверх: экран покажет причину, а не «заказов нет» (Q-3, IOS-09)
                }
                orders = list.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            }
            orders.forEach { shop.returnExpired($0) }   // время на оплату вышло — вещи снова в корзине
            error = nil
        } catch { self.error = error.userMessage }
        loading = false
    }
}

struct OrderRow: View {
    let order: Order
    var admin = false
    var body: some View {
        let n = order.items.reduce(0) { $0 + $1.qty }
        let first = order.items.first
        HStack(alignment: .top, spacing: 12) {
            OrderThumbs(items: order.items, w: admin ? 46 : 52)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("№ \(order.number)").font(Theme.font(15, .medium))
                    Spacer(minLength: 6)
                    StatusPill(status: order.status, admin: admin)
                }
                if let first {
                    Text(first.name).font(Theme.font(14)).lineLimit(1).padding(.top, 2)
                    Text(first.meta).font(Theme.font(12)).foregroundStyle(Theme.muted).lineLimit(2)
                    if order.items.count > 1 { Text("и ещё \(order.items.count - 1) \(Fmt.plural(order.items.count - 1, "вещь", "вещи", "вещей"))").font(Theme.font(12)).foregroundStyle(Theme.dim) }
                }
                if admin { Text(order.customerName + " · " + order.payMethodText).font(Theme.font(12.5)).foregroundStyle(Theme.text).lineLimit(1).padding(.top, 2) }
                HStack(alignment: .firstTextBaseline) {
                    Text(Fmt.date(order.createdAt, time: admin)).font(Theme.font(12)).foregroundStyle(Theme.muted)
                    Spacer()
                    Text("\(n) шт. · ").font(Theme.font(12)).foregroundColor(Theme.muted) + Text(Fmt.rub(order.total)).font(Theme.font(14, .medium)).foregroundColor(Theme.text)
                }.padding(.top, 2)
                if admin && order.awaitingPay && order.payBy != nil { PayLeftLabel(order: order) }
                else if admin && !order.paid && order.payMethod == "online" && order.status != "canceled" { Text("Не оплачен").font(Theme.font(11.5, .medium)).foregroundStyle(Theme.danger) }
            }
        }.padding(.vertical, 6)
    }
}

/// Карточка в «Моих заказах»: строка заказа + «Оплатить · осталось 12:48», пока время есть
struct OrderCard: View {
    let order: Order
    let open: () -> Void
    let pay: (URL) -> Void
    var body: some View {
        VStack(spacing: 12) {
            Button(action: open) { OrderRow(order: order).contentShape(Rectangle()) }.buttonStyle(.plain)
            if order.awaitingPay, order.payBy != nil, let u = URL(string: order.payUrl), PayClock.left(order, Date()) > 0 {
                PayNowButton(order: order) { pay(u) }
            }
        }
    }
}

struct StatusPill: View {
    let status: String
    var admin = false
    var body: some View {
        let color: Color = ["done": Theme.ok, "canceled": Theme.dim, "returned": Theme.dim, "shipped": Color(hex: "#2b50ff"), "new": Theme.accent].first { $0.key == status }?.value ?? Theme.text
        Text((admin ? Order.statusAdminRu : Order.statusRu)[status] ?? status).font(Theme.font(11.5, .medium)).foregroundStyle(color)
            .padding(.horizontal, 9).padding(.vertical, 4).background(Capsule().fill(color.opacity(0.1)))
    }
}

struct OrderView: View {
    let id: String
    @EnvironmentObject private var shop: Shop
    @EnvironmentObject private var router: Router
    @State private var order: Order?
    @State private var error: String?
    @State private var notFound = false
    @State private var request = false
    @State private var payURL: URL?
    var body: some View {
        ScrollView {
            if let o = order {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        // ждёт оплаты или время вышло — статус заказа не нужен, всё говорит карточка оплаты
                        if !(o.awaitingPay || o.payExpired) { StatusPill(status: o.status) }
                        DotTitle(text: "Заказ № \(o.number)", size: 32)
                        Text("от \(Fmt.date(o.createdAt))").font(Theme.font(14)).foregroundStyle(Theme.muted)
                    }
                    // Оплата онлайн не прошла (окно закрыли, связь пропала) — оплатить можно отсюда, как на сайте (1.0.2)
                    // 1.0.3: 15 минут на оплату с обратным отсчётом; вышло — «Оформить заново»
                    if o.paidLate { PaidLateCard(order: o) }
                    else if o.payExpired && o.kind == "gift" { GiftExpiredCard(order: o) }
                    else if o.payExpired { PayExpiredCard(order: o) }
                    else if o.awaitingPay, let u = URL(string: o.payUrl) {
                        if o.payBy != nil { PayTimerCard(order: o, onPay: { payURL = u }, onExpire: { Task { await load() } }) }
                        else {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Заказ ждёт оплаты").font(Theme.font(17, .medium))
                                Text("Вещи отложены за вами. Оплатите заказ, чтобы мы начали его собирать.").font(Theme.font(13.5)).foregroundStyle(Theme.muted)
                                PrimaryButton(title: "Оплатить · \(Fmt.rub(o.total))") { payURL = u }
                            }.padding(18).softCard(20)
                        }
                    }
                    OrderSteps(status: o.status)
                    if !o.trackNumber.isEmpty, let u = URL(string: o.trackURL) {
                        Link(destination: u) {
                            HStack { VStack(alignment: .leading, spacing: 3) { Text("Отследить посылку").font(Theme.font(15, .medium)); Text("СДЭК · \(o.trackNumber)" + (o.cdekStatus.isEmpty ? "" : " · " + o.cdekStatus)).font(Theme.font(12.5)).foregroundStyle(Theme.muted) }; Spacer(); Image(systemName: "arrow.up.right") }
                                .foregroundStyle(Theme.text).padding(16).background(RoundedRectangle(cornerRadius: 18).fill(Theme.surface))
                        }
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(o.items.enumerated()), id: \.offset) { _, it in
                            HStack(alignment: .top, spacing: 12) {
                                ProductImage(path: it.image, kind: it.artKind, tone: it.artTone).frame(width: 64, height: 84).background(Theme.photo).clipShape(RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(it.name).font(Theme.font(14.5))
                                    Text(it.meta).font(Theme.font(12.5)).foregroundStyle(Theme.muted)
                                    Text(Fmt.rub(it.price * it.qty)).font(Theme.font(14, .medium))
                                }
                            }.padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading).overlay(alignment: .bottom) { Divider1() }
                        }
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        info("Доставка", [o.deliveryName, o.city, o.address].filter { !$0.isEmpty }.joined(separator: "\n"))
                        Divider1()
                        info("Получатель", [o.customerName, Fmt.phone(o.phone), o.email].filter { !$0.isEmpty }.joined(separator: "\n"))
                        Divider1()
                        info("Оплата", "\(o.payMethodText) · \(o.payStatusText)")
                    }.padding(18).softCard(20)
                    VStack(spacing: 8) {
                        line("Товары", Fmt.rub(o.subtotal + o.saleDiscount))
                        if o.saleDiscount + o.promoDiscount > 0 { line("Скидка", "−" + Fmt.rub(o.saleDiscount + o.promoDiscount)) }
                        if o.bonusUsed > 0 { line("Бонусы", "−" + Fmt.rub(o.bonusUsed)) }
                        if o.giftUsed > 0 { line("Подарочный сертификат", "−" + Fmt.rub(o.giftUsed)) }
                        line("Доставка", o.deliveryPrice == 0 ? "Бесплатно" : Fmt.rub(o.deliveryPrice))
                        Divider1()
                        HStack(alignment: .firstTextBaseline) { Text("Итого").font(Theme.font(19)); Spacer(); Text(Fmt.rub(o.total)).font(Theme.font(23, .light)) }
                        if o.bonusEarn > 0 { Text("+\(o.bonusEarn) бонусов после получения").font(Theme.font(12.5)).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading) }
                    }.padding(20).background(RoundedRectangle(cornerRadius: 24).fill(Theme.surface)).hairline(RoundedRectangle(cornerRadius: 24), 0.06)
                    if o.requestOk {
                        GhostButton(title: "Обменять размер или вернуть", icon: "arrow.left.arrow.right") { request = true }
                    } else if !o.requestWhy.isEmpty && o.status == "done" {
                        Text(o.requestWhy).font(Theme.font(12.5)).foregroundStyle(Theme.dim)
                    }
                    if shop.user != nil { GhostButton(title: "Вопрос по заказу", icon: "bubble.left") { router.push(.support, on: .account) } }
                }.padding(Theme.gutter)
            } else if notFound {
                // Заказ оформлен на другом устройстве или без входа: подсказываем, как его найти (аудит T-3, 16.11)
                VStack(spacing: 12) {
                    EmptyState(icon: "shippingbox", title: "Заказ не найден", text: "Возможно, он оформлен на другом устройстве. Найдите его по номеру заказа и телефону" + (shop.user == nil ? " или войдите в личный кабинет." : "."), button: "Найти по номеру и телефону") { router.push(.track, on: .account) }
                    if shop.user == nil { GhostButton(title: "Войти", icon: "person") { router.reset(.account) }.padding(.horizontal, Theme.gutter) }
                }
            } else if let error { EmptyState(icon: "exclamationmark.triangle", title: "Не удалось открыть заказ", text: error, button: "Повторить") { self.error = nil; Task { await load() } } }
            else { ProgressView().padding(.top, 80) }
        }
        .navigationTitle(order.map { "№ \($0.number)" } ?? "Заказ").navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $request) { if let o = order { RequestSheet(order: o) { order = $0 } } }
        .paymentSheet($payURL) { Task { await load(); if order?.paid == true { Toast.shared.show("Оплата получена") } } }
    }
    private func load() async {
        do { order = Order(try await API.shared.json("GET", "orders/\(id)", query: OrderTokens.all[id].map { ["t": $0] } ?? [:])["order"]); error = nil; notFound = false; if let o = order { shop.returnExpired(o) } }
        catch let e as APIError where e.status == 404 && order == nil { notFound = true; error = nil }
        // запрос прервали (свайп обновления, уход с экрана) — без заказа не крутим загрузку бесконечно, а предлагаем повторить
        catch { self.error = error.userMessage ?? (order == nil ? "Проверьте интернет и попробуйте ещё раз" : nil) }
    }
    private func info(_ t: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(t).font(Theme.font(12.5)).foregroundStyle(Theme.muted); Text(v).font(Theme.font(14.5)) }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func line(_ t: String, _ v: String) -> some View { HStack { Text(t).font(Theme.font(14)).foregroundStyle(Theme.muted); Spacer(); Text(v).font(Theme.font(14)) } }
}

struct OrderSteps: View {
    let status: String
    var body: some View {
        let steps = ["Принят", "Собирается", "В пути", "Получен"]
        let idx = ["new": 0, "processing": 1, "shipped": 2, "done": 3][status]
        if let idx {
            HStack(spacing: 6) {
                ForEach(steps.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 6) {
                        Capsule().fill(i <= idx ? Theme.accent : Theme.line).frame(height: 3)
                        Text(steps[i]).font(Theme.font(11, i == idx ? .medium : .regular)).foregroundStyle(i <= idx ? Theme.text : Theme.dim)
                            .lineLimit(1).minimumScaleFactor(0.6)   // «Собирается» не рвётся посередине (аудит 16.11)
                    }
                }
            }
        }
    }
}

// Заявка на обмен размера или возврат: какие вещи, что не так, на какой размер
struct RequestSheet: View {
    let order: Order
    let updated: (Order) -> Void
    @EnvironmentObject private var shop: Shop
    @Environment(\.dismiss) private var dismiss
    @State private var kind = "exchange"
    @State private var reason = "big"
    @State private var picked: [Int: String] = [:]   // индекс вещи → новый размер ("" при возврате)
    @State private var comment = ""
    @State private var busy = false
    @State private var error: String?
    private let reasons = [("small", "Маловата"), ("big", "Великовата"), ("color", "Не тот цвет"), ("defect", "Брак"), ("other", "Передумал")]
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("", selection: $kind) { Text("Обмен размера").tag("exchange"); Text("Возврат денег").tag("refund") }.pickerStyle(.segmented)
                    Text("Что не так?").font(Theme.font(16, .medium))
                    FlowChips(items: reasons.map(\.1), selected: reasons.first { $0.0 == reason }?.1 ?? "") { t in reason = reasons.first { $0.1 == t }?.0 ?? "other" }
                    Text("Какие вещи").font(Theme.font(16, .medium))
                    ForEach(Array(order.items.enumerated()), id: \.offset) { i, it in
                        VStack(alignment: .leading, spacing: 10) {
                            Button { if picked[i] == nil { picked[i] = "" } else { picked[i] = nil } } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: picked[i] != nil ? "checkmark.square.fill" : "square").font(.system(size: 20)).foregroundStyle(Theme.ink)
                                    Text("\(it.name) · \(it.size)").font(Theme.font(14.5)).foregroundStyle(Theme.text).multilineTextAlignment(.leading)
                                }
                            }
                            if kind == "exchange", picked[i] != nil, let p = shop.product(it.productId) {
                                let sizes = p.color(it.colorId).sizes.filter { $0.size != it.size }
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(sizes, id: \.size) { s in
                                            Chip(title: s.size, on: picked[i] == s.size, out: s.stock <= 0, height: 40) { if s.stock > 0 { picked[i] = s.size } }
                                        }
                                    }
                                }
                            }
                        }.padding(14).background(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.line))
                    }
                    TextField("Комментарий (необязательно)", text: $comment, axis: .vertical).font(Theme.font(15)).lineLimit(2...4)
                        .padding(14).background(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line))
                    Text(kind == "exchange" ? "Сдайте вещь в любом пункте СДЭК. Как только она придёт к нам и мы её проверим, отправим новый размер." : "Деньги вернутся, когда вещь придёт на склад и мы её проверим.")
                        .font(Theme.font(13)).foregroundStyle(Theme.muted)
                    ErrorText(text: error)
                    PrimaryButton(title: kind == "exchange" ? "Оформить обмен" : "Оформить возврат", busy: busy, disabled: picked.isEmpty) { Task { await send() } }
                }.padding(Theme.gutter)
            }
            .navigationTitle("Обмен и возврат").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
        }
    }
    private func send() async {
        busy = true; error = nil; defer { busy = false }
        let lines: [[String: Any]] = picked.map { i, s in ["idx": i, "qty": order.items[i].qty, "toSize": s] }
        var b: [String: Any] = ["kind": kind, "reason": reason, "comment": comment, "lines": lines]
        if let t = OrderTokens.all[order.id] { b["t"] = t }
        do {
            let r = try await API.shared.json("POST", "orders/\(order.id)/request", body: b)
            updated(Order(r["order"])); Haptic.success(); Toast.shared.show("Заявка оформлена — подробности в письме"); dismiss()
        } catch { self.error = error.userMessage; Haptic.error() }
    }
}

struct FlowChips: View {
    let items: [String], selected: String
    let pick: (String) -> Void
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) { ForEach(items, id: \.self) { t in Chip(title: t, on: t == selected, height: 40) { pick(t) } } }
        }
    }
}
