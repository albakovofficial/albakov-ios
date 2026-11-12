import SwiftUI

// Кабинет: вход и регистрация, заказы, бонусы, поддержка, профиль, уведомления; сотрудникам — панель
struct AccountView: View {
    @EnvironmentObject private var shop: Shop
    @EnvironmentObject private var router: Router
    @State private var tab = "orders"
    @State private var orders: [Order] = []
    @State private var bonusLog: [JSON] = []
    @State private var confirmLogout = false

    var body: some View {
        if let u = shop.user {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Eyebrow(text: "Личный кабинет").padding(.top, 22)
                    DotTitle(text: "Здравствуйте,\n\(u.firstName.isEmpty ? "покупатель" : u.firstName)", size: 36)
                    HStack(spacing: 10) { Rectangle().fill(Theme.muted).frame(width: 16, height: 1); Text("С нами с " + Fmt.monthYear(u.createdAt)).font(Theme.font(14)).foregroundStyle(Theme.muted) }
                    HStack(spacing: 10) {
                        stat("\(orders.count)", Fmt.plural(orders.count, "заказ", "заказа", "заказов"))
                        if shop.settings.bonusEnabled { stat(Fmt.num(u.bonus), "\(Fmt.plural(u.bonus, "бонус", "бонуса", "бонусов")) на счёте") }
                        Spacer()
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(tabs, id: \.0) { t in
                                Button { withAnimation(.easeOut(duration: 0.2)) { select(t.0) } } label: {
                                    HStack(spacing: 6) {
                                        Text(t.1).font(Theme.font(14)).foregroundStyle(tab == t.0 ? .white : Theme.muted)
                                        if t.0 == "support" && u.supportUnread > 0 { Circle().fill(Theme.accent).frame(width: 7, height: 7) }
                                    }.padding(.horizontal, 14).frame(height: 40).background(Capsule().fill(tab == t.0 ? Theme.ink : .clear))
                                }.buttonStyle(.plain)
                            }
                        }.padding(4).background(Capsule().fill(Theme.surface))
                    }
                    content(u)
                }.padding(.horizontal, Theme.gutter).padding(.bottom, 40)
            }
            .refreshable { await load() }
            .task { await load() }
            .confirmationDialog("Выйти из кабинета?", isPresented: $confirmLogout, titleVisibility: .visible) {
                Button("Выйти", role: .destructive) { Task { await shop.logout() } }
            }
        } else {
            AuthView()
        }
    }

    private var tabs: [(String, String)] {
        var t = [("orders", "Заказы"), ("favorites", "Избранное")]
        if shop.settings.bonusEnabled { t.append(("bonus", "Бонусы")) }
        t += [("support", "Поддержка"), ("profile", "Профиль"), ("notifications", "Уведомления")]
        if shop.isStaff { t.append(("admin", "Панель")) }
        return t
    }
    private func select(_ t: String) {
        switch t {
        case "support": router.push(.support, on: .account)
        case "profile": router.push(.profile, on: .account)
        case "notifications": router.push(.notifications, on: .account)
        case "admin": router.push(.admin, on: .account)
        default: tab = t
        }
    }
    private func stat(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(v).font(Theme.font(26, .light)); Text(l).font(Theme.font(12.5)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true) }
            .padding(14).frame(width: 104, height: 96, alignment: .topLeading).background(RoundedRectangle(cornerRadius: 18).fill(.white)).hairline(RoundedRectangle(cornerRadius: 18), 0.09)
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
                if bonusLog.isEmpty { Text("Пока нет начислений").font(Theme.font(14)).foregroundStyle(Theme.muted) }
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
            if orders.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Заказов пока нет").font(Theme.font(26, .light))
                    Text("Здесь появятся ваши покупки и статус доставки каждой из них.").font(Theme.font(15)).foregroundStyle(Theme.muted).lineSpacing(4)
                    PrimaryButton(title: "Перейти в каталог") { router.reset(.catalog) }.frame(width: 200)
                }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 24).fill(Theme.surface)).hairline(RoundedRectangle(cornerRadius: 24), 0.06)
            } else {
                VStack(spacing: 10) {
                    ForEach(orders) { o in
                        Button { router.push(.order(o.id), on: .account) } label: { OrderRow(order: o).padding(14).softCard(18) }.buttonStyle(Pressable())
                    }
                }
            }
        }
        Button { confirmLogout = true } label: { Text("Выйти из кабинета").font(Theme.font(14)).foregroundStyle(Theme.muted).underline() }.padding(.top, 24)
    }
    private func load() async {
        await shop.refreshUser()
        if let r = try? await API.shared.json("GET", "orders") { orders = r["orders"].array.map(Order.init) }
        if let r = try? await API.shared.json("GET", "me") { bonusLog = r["bonusLog"].array }
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
        } catch { self.error = error.localizedDescription; Haptic.error() }
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
        } catch { self.error = error.localizedDescription; Haptic.error() }
    }
}

// MARK: - Заказы
struct OrdersView: View {
    @EnvironmentObject private var shop: Shop
    @EnvironmentObject private var router: Router
    @State private var orders: [Order] = []
    @State private var loading = true
    @State private var error: String?
    var body: some View {
        List {
            if let error { Text(error).font(Theme.font(14)).foregroundStyle(Theme.danger) }
            if !loading && orders.isEmpty && error == nil {
                EmptyState(icon: "shippingbox", title: "Заказов пока нет", text: "Здесь появятся ваши заказы и их статусы").listRowSeparator(.hidden)
            }
            ForEach(orders) { o in
                Button { router.push(.order(o.id), on: .account) } label: { OrderRow(order: o) }
            }
        }
        .listStyle(.plain)
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
                for (id, t) in OrderTokens.all { if let j = try? await API.shared.json("GET", "orders/\(id)", query: ["t": t]) { list.append(Order(j["order"])) } }
                orders = list.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            }
            error = nil
        } catch { self.error = error.localizedDescription }
        loading = false
    }
}

struct OrderRow: View {
    let order: Order
    var admin = false
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RemoteImage(path: order.items.first?.image ?? "").frame(width: 58, height: 76).clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("№ \(order.number)").font(Theme.font(15, .medium))
                    Spacer()
                    StatusPill(status: order.status, admin: admin)
                }
                if admin { Text(order.customerName).font(Theme.font(13.5)).foregroundStyle(Theme.text) }
                Text("\(Fmt.date(order.createdAt, time: admin)) · \(order.items.reduce(0) { $0 + $1.qty }) шт. · \(Fmt.rub(order.total))").font(Theme.font(12.5)).foregroundStyle(Theme.muted)
                if admin && !order.paid && order.payMethod == "online" { Text("Не оплачен").font(Theme.font(11.5, .medium)).foregroundStyle(Theme.danger) }
            }
        }.padding(.vertical, 6)
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
    @State private var request = false
    var body: some View {
        ScrollView {
            if let o = order {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        StatusPill(status: o.status)
                        DotTitle(text: "Заказ № \(o.number)", size: 32)
                        Text("от \(Fmt.date(o.createdAt))").font(Theme.font(14)).foregroundStyle(Theme.muted)
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
                                ProductImage(path: it.image, kind: "tee", tone: "#3a3632").frame(width: 64, height: 84).background(Theme.photo).clipShape(RoundedRectangle(cornerRadius: 12))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(it.name).font(Theme.font(14.5))
                                    Text([it.color, "размер " + it.size, it.qty > 1 ? "\(it.qty) шт." : ""].filter { !$0.isEmpty }.joined(separator: " · ")).font(Theme.font(12.5)).foregroundStyle(Theme.muted)
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
            } else if let error { EmptyState(icon: "exclamationmark.triangle", title: "Не удалось открыть заказ", text: error) }
            else { ProgressView().padding(.top, 80) }
        }
        .navigationTitle(order.map { "№ \($0.number)" } ?? "Заказ").navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $request) { if let o = order { RequestSheet(order: o) { order = $0 } } }
    }
    private func load() async {
        do { order = Order(try await API.shared.json("GET", "orders/\(id)", query: OrderTokens.all[id].map { ["t": $0] } ?? [:])["order"]); error = nil }
        catch { self.error = error.localizedDescription }
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
                        Capsule().fill(i <= idx ? Theme.ink : Theme.line).frame(height: 3)
                        Text(steps[i]).font(Theme.font(11, i == idx ? .medium : .regular)).foregroundStyle(i <= idx ? Theme.text : Theme.dim)
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
        } catch { self.error = error.localizedDescription; Haptic.error() }
    }
}

struct FlowChips: View {
    let items: [String], selected: String
    let pick: (String) -> Void
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) { ForEach(items, id: \.self) { t in Chip(title: t, on: t == selected, dark: true, height: 40) { pick(t) } } }
        }
    }
}
