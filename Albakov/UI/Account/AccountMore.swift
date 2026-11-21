import SwiftUI

// Бонусы, поддержка (чат), личные данные, уведомления
struct BonusView: View {
    @EnvironmentObject private var shop: Shop
    @State private var log: [JSON] = []
    @State private var logError: String?
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    LoyalCard().padding(.vertical, 12)
                    Text("\(shop.user?.bonus ?? 0) \(Fmt.plural(shop.user?.bonus ?? 0, "бонус", "бонуса", "бонусов")) на счёте · 1 бонус = 1 ₽").font(Theme.font(14)).foregroundStyle(Theme.muted)
                    Text("Начисляем \(shop.settings.bonusPercent)% с каждой покупки" + (shop.settings.bonusOnlineExtra > 0 ? " и ещё \(shop.settings.bonusOnlineExtra)% при оплате онлайн" : "") + ". Списать можно при оформлении следующего заказа.")
                        .font(Theme.font(13.5)).foregroundStyle(Theme.muted).padding(.top, 4)
                }.padding(.vertical, 8)
            }
            Section("История") {
                if log.isEmpty, let logError {   // история не загрузилась (Q-3) — не «пока нет начислений»
                    ErrorRetry(text: "История не загрузилась: " + logError) { Task { await load() } }
                } else if log.isEmpty { Text("Пока нет начислений").font(Theme.font(14)).foregroundStyle(Theme.muted) }
                ForEach(Array(log.enumerated()), id: \.offset) { _, e in
                    let a = e["amount"].int ?? 0
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(BonusView.label(e)).font(Theme.font(14.5))
                            Text(Fmt.date(ISO.date(e["at"].str))).font(Theme.font(12)).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Text((a > 0 ? "+" : "") + "\(a)").font(Theme.font(15, .medium)).foregroundStyle(a > 0 ? Theme.ok : Theme.text)
                    }
                }
            }
        }
        .navigationTitle("Бонусы").navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }
    private func load() async {
        do { log = try await API.shared.json("GET", "me")["bonusLog"].array; logError = nil }
        catch { logError = error.userMessage; return }
        // отметка «новые бонусы просмотрены» — попутная: не получилось — отметится в следующий раз
        _ = try? await API.shared.raw("POST", "me/bonus-seen")
    }
    static func label(_ e: JSON) -> String {
        let n = e["orderNumber"].str
        switch e["type"].str {
        case "earn": return "Начислено за заказ" + (n.isEmpty ? "" : " № " + n)
        case "spend": return "Оплата заказа" + (n.isEmpty ? "" : " № " + n)
        case "refund": return "Возвращено по заказу" + (n.isEmpty ? "" : " № " + n)
        case "cancel": return "Отменено по заказу" + (n.isEmpty ? "" : " № " + n)
        case "manual": return e["note"].string.flatMap { $0.isEmpty ? nil : $0 } ?? "Подарок от магазина"
        case "welcome": return "Приветственные бонусы"
        default: return e["note"].string ?? "Бонусы"
        }
    }
}

struct ProfileView: View {
    @EnvironmentObject private var shop: Shop
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var current = ""
    @State private var newPassword = ""
    @State private var busy = false
    @State private var error: String?
    @State private var askDelete = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) { Field(label: "Имя", text: $firstName, content: .givenName); Field(label: "Фамилия", text: $lastName, content: .familyName) }
                Field(label: "Телефон", text: $phone, keyboard: .phonePad, content: .telephoneNumber)
                Field(label: "Почта — это и логин", text: $email, keyboard: .emailAddress, content: .emailAddress, capitalization: .never)
                Text("Сменить пароль").font(Theme.font(18, .light)).padding(.top, 10)
                Field(label: "Новый пароль", text: $newPassword, content: .newPassword, secure: true)
                Field(label: "Текущий пароль — нужен, чтобы сменить пароль или почту", text: $current, content: .password, secure: true)
                ErrorText(text: error)
                PrimaryButton(title: "Сохранить", busy: busy) { Task { await save() } }
                Button { askDelete = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "trash").font(.system(size: 16, weight: .light)).foregroundStyle(Theme.danger)
                            .frame(width: 40, height: 40).background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: "#fbebeb")))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Удалить аккаунт").font(Theme.font(15, .medium)).foregroundStyle(Theme.danger)
                            Text("Личные данные удалятся, бонусы сгорят").font(Theme.font(12.5)).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                    }.padding(.vertical, 14).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
                .padding(.top, 26)
            }.padding(Theme.gutter)
        }
        .sheet(isPresented: $askDelete) { DeleteAccountSheet().presentationDetents([.large]) }
        .navigationTitle("Личные данные").navigationBarTitleDisplayMode(.inline)
        .onAppear { if let u = shop.user, firstName.isEmpty { firstName = u.firstName; lastName = u.lastName; phone = Fmt.phone(u.phone); email = u.email } }
    }
    private func save() async {
        busy = true; error = nil; defer { busy = false }
        var b: [String: Any] = ["firstName": firstName, "lastName": lastName, "phone": phone, "email": email]
        if !newPassword.isEmpty { b["newPassword"] = newPassword }
        if !current.isEmpty { b["currentPassword"] = current }
        do { _ = try await API.shared.raw("PUT", "me", body: RequestBody(b)); await shop.refreshUser(); current = ""; newPassword = ""; Haptic.success(); Toast.shared.show("Сохранено") }
        catch { self.error = error.userMessage; Haptic.error() }
    }
}

/// Окно «Удалить аккаунт?»: что удалится, что останется, пароль для подтверждения
struct DeleteAccountSheet: View {
    @EnvironmentObject private var shop: Shop
    @EnvironmentObject private var router: Router
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var going: [Order] = []
    @State private var goingError: String?
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "trash").font(.system(size: 22, weight: .light)).foregroundStyle(Theme.danger)
                    .frame(width: 52, height: 52).background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: "#fbebeb")))
                Text("Удалить аккаунт?").font(Theme.font(26, .light))
                VStack(alignment: .leading, spacing: 9) {
                    line(false, "Имя, телефон, почта, избранное и корзина удалятся навсегда")
                    if let b = shop.user?.bonus, b > 0 { line(false, "Сгорят \(Fmt.num(b)) \(Fmt.plural(b, "бонус", "бонуса", "бонусов"))") }
                    ForEach(going) { o in line(true, "Заказ № \(o.number) — доставим его как обычно") }
                    if let goingError { ErrorRetry(text: "Не удалось проверить незавершённые заказы: " + goingError) { Task { await loadGoing() } } }
                    line(true, "Чеки и история заказов останутся у магазина — так требует закон")
                }
                Field(label: "Пароль — для подтверждения", text: $password, content: .password, secure: true).padding(.top, 6)
                ErrorText(text: error)
                Button { Task { await remove() } } label: {
                    ZStack { if busy { ProgressView().tint(.white) } else { Text("Удалить навсегда").font(Theme.font(15, .medium)) } }
                        .foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 54).background(Capsule().fill(Theme.danger))
                }.buttonStyle(Pressable()).disabled(busy)
                GhostButton(title: "Отмена") { dismiss() }
            }.padding(20).padding(.top, 8)
        }
        .scrollDismissesKeyboard(.interactively)
        .task { await loadGoing() }
    }
    /// Незавершённые заказы — чтобы покупатель знал, что их доставят. Не загрузились — говорим об этом (Q-3):
    /// иначе выглядело бы, будто незавершённых заказов нет
    private func loadGoing() async {
        do { going = try await API.shared.json("GET", "orders")["orders"].array.map(Order.init).filter { ["new", "processing", "shipped"].contains($0.status) }; goingError = nil }
        catch { if let m = error.userMessage { goingError = m } }
    }
    private func line(_ ok: Bool, _ t: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: ok ? "checkmark" : "xmark").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted).frame(width: 18).padding(.top, 3)
            Text(t).font(Theme.font(14.5)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func remove() async {
        guard !password.isEmpty else { error = "Введите пароль"; return }
        busy = true; error = nil; defer { busy = false }
        do {
            try await shop.deleteAccount(password: password)
            Haptic.success(); dismiss(); router.closeCheckout(); router.reset(.account); Toast.shared.show("Аккаунт удалён")
        } catch { self.error = error.userMessage; Haptic.error() }
    }
}

struct NotificationsView: View {
    @EnvironmentObject private var shop: Shop
    @ObservedObject private var push = PushManager.shared
    @State private var prefs: [String: Bool] = [:]
    /// Настройки получены с сервера. До этого переключатели закрыты: сервер сохраняет набор целиком, и переключатель,
    /// нажатый поверх незагруженного (пустого) набора, выключил бы все остальные уведомления (Q-3)
    @State private var prefsLoaded = false
    @State private var prefsError: String?
    /// Идёт сохранение: переключатели ждут ответа — два одновременных сохранения целого набора могли бы разойтись с экраном
    @State private var saving = false
    private let kinds = [("orders", "Заказы", "В пути, ждёт в пункте выдачи, напоминание забрать"), ("support", "Ответы поддержки", "Когда мы ответили на ваш вопрос"),
                         ("returns", "Обмен и возврат", "Новый размер отправлен, деньги вернулись"), ("stock", "Снова в наличии", "Размер, о котором вы просили сообщить"),
                         ("bonus", "Бонусы", "Начисления на бонусный счёт"), ("promo", "Акции и новинки", "Редко и только о важном — по желанию")]
    var body: some View {
        List {
            Section {
                switch push.status {
                case .authorized, .provisional, .ephemeral:
                    Label("Включены на этом iPhone", systemImage: "checkmark.circle.fill").font(Theme.font(15)).foregroundStyle(Theme.ok)
                    Button("Прислать проверочное") { Task { await sendTest() } }.font(Theme.font(15)).foregroundStyle(Theme.text)
                case .denied:
                    Text("Уведомления выключены в настройках iPhone").font(Theme.font(15))
                    Button("Открыть настройки") { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } }.font(Theme.font(15, .medium)).foregroundStyle(Theme.text)
                default:
                    Button("Включить уведомления") { Task { await push.request() } }.font(Theme.font(15, .medium)).foregroundStyle(Theme.text)
                }
            }
            Section("Что присылать") {
                if let prefsError, !prefsLoaded { ErrorRetry(text: "Настройки не загрузились: " + prefsError) { Task { await loadPrefs() } } }
                ForEach(kinds.filter { $0.0 != "bonus" || shop.settings.bonusEnabled }, id: \.0) { k in
                    Toggle(isOn: Binding(get: { prefs[k.0] ?? false }, set: { on in prefs[k.0] = on; saving = true; Task { await save(k.0, was: !on) } })) {
                        VStack(alignment: .leading, spacing: 2) { Text(k.1).font(Theme.font(15)); Text(k.2).font(Theme.font(12.5)).foregroundStyle(Theme.muted) }
                    }.tint(Theme.ink).disabled(!prefsLoaded || saving)
                }
            }
        }
        .navigationTitle("Уведомления").navigationBarTitleDisplayMode(.inline)
        .task { push.refreshStatus(); await loadPrefs() }
    }
    private func loadPrefs() async {
        do { prefs = try await API.shared.json("GET", "me/push")["prefs"].dict.mapValues(\.bool); prefsLoaded = true; prefsError = nil }
        catch { if let m = error.userMessage { prefsError = m } }
    }
    /// Не сохранилось — переключатель возвращается как был, причина — сообщением.
    /// saving ставится ещё в переключателе, до запуска задачи: иначе второй переключатель успел бы отправить своё сохранение
    private func save(_ kind: String, was: Bool) async {
        defer { saving = false }
        do { _ = try await API.shared.raw("PUT", "me/push", body: ["prefs": prefs]) }
        catch { prefs[kind] = was; Toast.shared.show(error.userMessage) }
    }
    private func sendTest() async {
        guard let e = push.endpoint else { return }
        do { _ = try await API.shared.raw("POST", "push/test", body: ["endpoint": e]); Toast.shared.show("Отправили — придёт через пару секунд") }
        catch { Toast.shared.show(error.userMessage) }
    }
}
