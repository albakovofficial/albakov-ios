import SwiftUI

// Бонусы, поддержка (чат), личные данные, уведомления
struct BonusView: View {
    @EnvironmentObject private var shop: Shop
    @State private var log: [JSON] = []
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(shop.user?.bonus ?? 0)").font(Theme.font(46, .light))
                    Text("бонусов на счёте · 1 бонус = 1 ₽").font(Theme.font(13.5)).foregroundStyle(Theme.muted)
                    Text("Начисляем \(shop.settings.bonusPercent)% с каждой покупки" + (shop.settings.bonusOnlineExtra > 0 ? " и ещё \(shop.settings.bonusOnlineExtra)% при оплате онлайн" : "") + ". Списать можно при оформлении следующего заказа.")
                        .font(Theme.font(13.5)).foregroundStyle(Theme.muted).padding(.top, 4)
                }.padding(.vertical, 8)
            }
            Section("История") {
                if log.isEmpty { Text("Пока нет начислений").font(Theme.font(14)).foregroundStyle(Theme.muted) }
                ForEach(Array(log.enumerated()), id: \.offset) { _, e in
                    let a = e["amount"].int ?? 0
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(label(e)).font(Theme.font(14.5))
                            Text(Fmt.date(ISO.date(e["at"].str))).font(Theme.font(12)).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        Text((a > 0 ? "+" : "") + "\(a)").font(Theme.font(15, .medium)).foregroundStyle(a > 0 ? Theme.ok : Theme.text)
                    }
                }
            }
        }
        .navigationTitle("Бонусы")
        .task {
            if let r = try? await API.shared.json("GET", "me") { log = r["bonusLog"].array }
            _ = try? await API.shared.raw("POST", "me/bonus-seen")
        }
    }
    private func label(_ e: JSON) -> String {
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

struct SupportListView: View {
    @EnvironmentObject private var router: Router
    @State private var tickets: [JSON] = []
    @State private var topics: [String] = []
    @State private var loading = true
    @State private var compose = false
    var body: some View {
        List {
            Section {
                Button { compose = true } label: { Label("Новое обращение", systemImage: "square.and.pencil").font(Theme.font(15, .medium)).foregroundStyle(Theme.text) }
            } footer: { Text("Отвечаем ежедневно. Ответ придёт сюда, на почту и уведомлением.").font(Theme.font(12)) }
            ForEach(Array(tickets.enumerated()), id: \.offset) { _, t in
                Button { router.push(.ticket(t["id"].str), on: .account) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(t["topic"].str + (t["orderNumber"].str.isEmpty ? "" : " · заказ № " + t["orderNumber"].str)).font(Theme.font(15, t["unread"].bool ? .semibold : .medium))
                            Spacer()
                            if t["unread"].bool { Circle().fill(Theme.danger).frame(width: 8, height: 8) }
                        }
                        Text(t["messages"].array.last?["text"].str ?? "").font(Theme.font(13)).foregroundStyle(Theme.muted).lineLimit(2)
                        Text((t["status"].str == "closed" ? "Закрыто · " : "") + Fmt.date(ISO.date(t["updatedAt"].str), time: true)).font(Theme.font(11.5)).foregroundStyle(Theme.dim)
                    }.foregroundStyle(Theme.text).padding(.vertical, 4)
                }
            }
        }
        .overlay { if loading { ProgressView() } }
        .navigationTitle("Поддержка")
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $compose) { NewTicketSheet(topics: topics) { id in compose = false; Task { await load() }; router.push(.ticket(id), on: .account) } }
    }
    private func load() async {
        if let r = try? await API.shared.json("GET", "support") { tickets = r["tickets"].array; topics = r["topics"].array.map(\.str) }
        loading = false
    }
}

struct NewTicketSheet: View {
    let topics: [String]
    let created: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var topic = ""
    @State private var text = ""
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                FlowChips(items: topics, selected: topic) { topic = $0 }
                TextField("Опишите вопрос", text: $text, axis: .vertical).font(Theme.font(16)).lineLimit(5...10)
                    .padding(14).background(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.line))
                ErrorText(text: error)
                PrimaryButton(title: "Отправить", busy: busy, disabled: text.trimmingCharacters(in: .whitespaces).isEmpty) {
                    busy = true
                    Task {
                        do { let r = try await API.shared.json("POST", "support", body: ["topic": topic, "text": text]); Haptic.success(); created(r["ticket"]["id"].str) }
                        catch { self.error = error.localizedDescription }
                        busy = false
                    }
                }
                Spacer()
            }
            .padding(Theme.gutter)
            .navigationTitle("Новое обращение").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
            .onAppear { if topic.isEmpty { topic = topics.first ?? "" } }
        }
    }
}

/// Переписка: сообщения покупателя справа, ответы магазина слева
struct ChatView: View {
    let messages: [JSON]
    let mine: (JSON) -> Bool
    @Binding var draft: String
    var busy: Bool
    var closed: Bool
    let send: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(Array(messages.enumerated()), id: \.offset) { i, m in
                            let me = mine(m)
                            HStack {
                                if me { Spacer(minLength: 40) }
                                VStack(alignment: me ? .trailing : .leading, spacing: 4) {
                                    Text(m["text"].str).font(Theme.font(15)).foregroundStyle(me ? .white : Theme.text).textSelection(.enabled)
                                    Text(Fmt.date(ISO.date(m["at"].str), time: true)).font(Theme.font(10.5)).foregroundStyle(me ? .white.opacity(0.6) : Theme.dim)
                                }
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 18).fill(me ? Theme.ink : Theme.surface))
                                if !me { Spacer(minLength: 40) }
                            }.id(i)
                        }
                    }.padding(Theme.gutter)
                }
                .onAppear { proxy.scrollTo(messages.count - 1, anchor: .bottom) }
                .onChange(of: messages.count) { _ in withAnimation { proxy.scrollTo(messages.count - 1, anchor: .bottom) } }
            }
            HStack(spacing: 10) {
                TextField(closed ? "Обращение закрыто — напишите, чтобы открыть снова" : "Сообщение", text: $draft, axis: .vertical).font(Theme.font(15)).lineLimit(1...5)
                    .padding(.horizontal, 14).padding(.vertical, 11).background(RoundedRectangle(cornerRadius: 20).fill(Theme.surface))
                Button(action: send) {
                    Group { if busy { ProgressView().tint(.white) } else { Image(systemName: "arrow.up").font(.system(size: 15, weight: .semibold)) } }
                        .foregroundStyle(.white).frame(width: 40, height: 40).background(Circle().fill(Theme.ink.opacity(draft.isEmpty ? 0.3 : 1)))
                }.disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || busy)
            }
            .padding(.horizontal, Theme.gutter).padding(.vertical, 8).background(.ultraThinMaterial)
        }
    }
}

struct TicketView: View {
    let id: String
    @State private var t = JSON(nil)
    @State private var draft = ""
    @State private var busy = false
    var body: some View {
        ChatView(messages: t["messages"].array, mine: { $0["from"].str == "user" }, draft: $draft, busy: busy, closed: t["status"].str == "closed") {
            busy = true
            Task {
                if let r = try? await API.shared.json("POST", "support/\(id)", body: ["text": draft]) { t = r["ticket"]; draft = ""; Haptic.tap() }
                busy = false
            }
        }
        .navigationTitle(t["topic"].string ?? "Обращение").navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }
    private func load() async { if let r = try? await API.shared.json("GET", "support/\(id)") { t = r["ticket"]; await Shop.shared.refreshUser() } }
}

struct ProfileView: View {
    @EnvironmentObject private var shop: Shop
    @State private var firstName = "", lastName = "", phone = "", email = "", current = "", newPassword = ""
    @State private var busy = false
    @State private var error: String?
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
            }.padding(Theme.gutter)
        }
        .navigationTitle("Личные данные")
        .onAppear { if let u = shop.user, firstName.isEmpty { firstName = u.firstName; lastName = u.lastName; phone = Fmt.phone(u.phone); email = u.email } }
    }
    private func save() async {
        busy = true; error = nil; defer { busy = false }
        var b: [String: Any] = ["firstName": firstName, "lastName": lastName, "phone": phone, "email": email]
        if !newPassword.isEmpty { b["newPassword"] = newPassword }
        if !current.isEmpty { b["currentPassword"] = current }
        do { _ = try await API.shared.raw("PUT", "me", body: b); await shop.refreshUser(); current = ""; newPassword = ""; Haptic.success(); Toast.shared.show("Сохранено") }
        catch { self.error = error.localizedDescription; Haptic.error() }
    }
}

struct NotificationsView: View {
    @EnvironmentObject private var shop: Shop
    @ObservedObject private var push = PushManager.shared
    @State private var prefs: [String: Bool] = [:]
    private let kinds = [("orders", "Заказы", "В пути, ждёт в пункте выдачи, напоминание забрать"), ("support", "Ответы поддержки", "Когда мы ответили на ваш вопрос"),
                         ("returns", "Обмен и возврат", "Новый размер отправлен, деньги вернулись"), ("stock", "Снова в наличии", "Размер, о котором вы просили сообщить"),
                         ("bonus", "Бонусы", "Начисления на бонусный счёт"), ("promo", "Акции и новинки", "Редко и только о важном — по желанию")]
    var body: some View {
        List {
            Section {
                switch push.status {
                case .authorized, .provisional, .ephemeral:
                    Label("Включены на этом iPhone", systemImage: "checkmark.circle.fill").font(Theme.font(15)).foregroundStyle(Theme.ok)
                    Button("Прислать проверочное") { Task { if let e = push.endpoint { _ = try? await API.shared.raw("POST", "push/test", body: ["endpoint": e]); Toast.shared.show("Отправили — придёт через пару секунд") } } }.font(Theme.font(15)).foregroundStyle(Theme.text)
                case .denied:
                    Text("Уведомления выключены в настройках iPhone").font(Theme.font(15))
                    Button("Открыть настройки") { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } }.font(Theme.font(15, .medium)).foregroundStyle(Theme.text)
                default:
                    Button("Включить уведомления") { Task { await push.request() } }.font(Theme.font(15, .medium)).foregroundStyle(Theme.text)
                }
            }
            Section("Что присылать") {
                ForEach(kinds.filter { $0.0 != "bonus" || shop.settings.bonusEnabled }, id: \.0) { k in
                    Toggle(isOn: Binding(get: { prefs[k.0] ?? false }, set: { prefs[k.0] = $0; Task { await save() } })) {
                        VStack(alignment: .leading, spacing: 2) { Text(k.1).font(Theme.font(15)); Text(k.2).font(Theme.font(12.5)).foregroundStyle(Theme.muted) }
                    }.tint(Theme.ink)
                }
            }
        }
        .navigationTitle("Уведомления")
        .task {
            push.refreshStatus()
            if let r = try? await API.shared.json("GET", "me/push") { prefs = r["prefs"].dict.mapValues(\.bool) }
        }
    }
    private func save() async { _ = try? await API.shared.raw("PUT", "me/push", body: ["prefs": prefs]) }
}
