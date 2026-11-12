import SwiftUI
import PhotosUI

// Родная панель управления для владельца и сотрудников. Разделы — по правам роли (как на сайте).
@MainActor
final class Admin: ObservableObject {
    static let shared = Admin()
    @Published var data = JSON(nil)
    @Published var loading = false
    @Published var error: String?
    var perms: [String] { data["perms"].array.map(\.str) }
    var roleName: String { data["roleName"].str }
    func can(_ p: String) -> Bool { perms.contains(p) }
    var orders: [Order] { data["orders"].array.map(Order.init).sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) } }
    var products: [JSON] { data["products"].array }

    func load() async {
        loading = true; defer { loading = false }
        do { data = try await API.shared.json("GET", "admin/data")["data"]; error = nil }
        catch { self.error = error.localizedDescription }
    }
}

struct AdminHomeView: View {
    @EnvironmentObject private var router: Router
    @StateObject private var admin = Admin.shared
    var body: some View {
        List {
            if let e = admin.error { Text(e).font(Theme.font(14)).foregroundStyle(Theme.danger) }
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    DotTitle(text: "Панель управления", size: 26)
                    Text(admin.roleName).font(Theme.font(13)).foregroundStyle(Theme.muted)
                }.padding(.vertical, 6)
                if admin.can("orders") {
                    let o = admin.orders
                    let today = o.filter { Calendar.current.isDateInToday($0.createdAt ?? .distantPast) && $0.status != "canceled" }
                    HStack(spacing: 8) {
                        AdminStat(title: "Сегодня", value: "\(today.count)", sub: Fmt.rub(today.reduce(0) { $0 + $1.total }))
                        AdminStat(title: "Новые", value: "\(o.filter { $0.status == "new" }.count)", sub: "ждут сборки")
                        AdminStat(title: "В пути", value: "\(o.filter { $0.status == "shipped" }.count)", sub: "у СДЭК")
                    }
                }
                ForEach(admin.data["problems"].array.indices, id: \.self) { i in
                    Text(admin.data["problems"].array[i]["title"].str + ". " + admin.data["problems"].array[i]["text"].str).font(Theme.font(13)).foregroundStyle(Theme.warn)
                }
            }
            Section {
                ForEach(AdminSections.list.filter { AdminSections.can($0.key) }, id: \.key) { s in
                    item(s.title, s.icon, s.key == "orders" ? .adminOrders : s.key == "support" ? .adminSupport : s.key == "customers" ? .adminCustomers : s.key == "push" ? .adminPush : s.key == "audit" ? .adminAudit : s.key == "products" ? .adminProducts : .adminSection(s.key), badge: badge(s.key))
                }
            }
        }
        .navigationTitle("Панель")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if admin.loading && !admin.data.exists { ProgressView() } }
        .task { await admin.load() }
        .refreshable { await admin.load() }
    }
    private func badge(_ k: String) -> Int {
        switch k {
        case "orders": return admin.orders.filter { $0.status == "new" }.count
        case "support": return admin.data["supportNew"].int ?? 0
        case "exchange": return admin.data["orders"].array.flatMap { $0["requests"].array }.filter { ["new", "received"].contains($0["status"].str) }.count
        case "products": return admin.data["waitlist"].array.filter { $0["status"].str == "waiting" }.count
        default: return 0
        }
    }
    private func item(_ t: String, _ icon: String, _ d: Dest, badge: Int = 0) -> some View {
        Button { router.push(d, on: .account) } label: {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 16, weight: .light)).frame(width: 24)
                Text(t).font(Theme.font(15.5)); Spacer()
                if badge > 0 { Text("\(badge)").font(Theme.font(12, .semibold)).foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(Theme.accent)) }
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Theme.dim)
            }.foregroundStyle(Theme.text)
        }
    }
}

// MARK: - Заказы
struct AdminOrdersView: View {
    @EnvironmentObject private var router: Router
    @ObservedObject private var admin = Admin.shared
    @State private var filter = "active"
    @State private var q = ""
    private var list: [Order] {
        admin.orders.filter { o in
            (filter == "all" || (filter == "active" ? ["new", "processing"].contains(o.status) : o.status == filter)) &&
            (q.isEmpty || ("\(o.number) \(o.customerName) \(o.phone) \(o.email)").lowercased().contains(q.lowercased()))
        }
    }
    var body: some View {
        List {
            Picker("", selection: $filter) {
                Text("В работе").tag("active"); Text("В пути").tag("shipped"); Text("Готово").tag("done"); Text("Все").tag("all")
            }.pickerStyle(.segmented).listRowSeparator(.hidden)
            if list.isEmpty { Text("Заказов нет").font(Theme.font(14)).foregroundStyle(Theme.muted) }
            ForEach(list) { o in Button { router.push(.adminOrder(o.id), on: .account) } label: { OrderRow(order: o, admin: true) }.foregroundStyle(Theme.text) }
        }
        .listStyle(.plain)
        .searchable(text: $q, placement: .navigationBarDrawer(displayMode: .always), prompt: "Номер, имя, телефон")
        .navigationTitle("Заказы").navigationBarTitleDisplayMode(.inline)
        .task { if !admin.data.exists { await admin.load() } }   // открыт сразу из push или ссылки — минуя главную панели
        .refreshable { await admin.load() }
    }
}

struct AdminOrderView: View {
    let id: String
    @ObservedObject private var admin = Admin.shared
    @State private var track = ""
    @State private var note = ""
    @State private var busy = false
    @State private var error: String?
    private var order: Order? { admin.orders.first { $0.id == id } }

    var body: some View {
        if let o = order {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { Text("№ \(o.number)").font(Theme.font(26, .light)); Spacer(); StatusPill(status: o.status, admin: true) }
                        Text(Fmt.date(o.createdAt, time: true)).font(Theme.font(13)).foregroundStyle(Theme.muted)
                        Text("\(Fmt.rub(o.total)) · \(o.payMethodText.lowercased()) · \(o.payStatusText)")
                            .font(Theme.font(14, .medium)).foregroundStyle(o.paid || o.payMethod == "cod" ? Theme.text : Theme.danger)
                    }.padding(.vertical, 4)
                    Menu {
                        ForEach(["new", "processing", "shipped", "done", "canceled", "returned"], id: \.self) { s in
                            Button(Order.statusAdminRu[s] ?? s) { Task { await patch(["status": s]) } }
                        }
                    } label: { Label("Сменить статус", systemImage: "arrow.triangle.2.circlepath").font(Theme.font(15, .medium)) }
                    Menu {
                        ForEach([("pending", "Не оплачен"), ("paid", "Оплачен"), ("refunded", "Деньги возвращены")], id: \.0) { p in Button(p.1) { Task { await patch(["paymentStatus": p.0]) } } }
                    } label: { Label("Оплата: " + o.payStatusText, systemImage: "rublesign.circle").font(Theme.font(15)) }
                    if o.payMethod == "cod" && !o.paid { Button { Task { await patch(["paymentStatus": "paid"]) } } label: { Label("Отметить оплату", systemImage: "rublesign.circle").font(Theme.font(15)) } }
                }
                Section("Покупатель") {
                    Text(o.customerName).font(Theme.font(15, .medium))
                    if !o.phone.isEmpty, let u = URL(string: "tel:+\(o.phone)") { Link(destination: u) { Label(Fmt.phone(o.phone), systemImage: "phone").font(Theme.font(15)) } }
                    if !o.email.isEmpty, let u = URL(string: "mailto:\(o.email)") { Link(destination: u) { Label(o.email, systemImage: "envelope").font(Theme.font(15)) } }
                }
                Section("Доставка") {
                    Text([o.deliveryName, o.city, o.address].filter { !$0.isEmpty }.joined(separator: "\n")).font(Theme.font(14.5)).textSelection(.enabled)
                    if !o.comment.isEmpty { Text("Комментарий: " + o.comment).font(Theme.font(13.5)).foregroundStyle(Theme.muted) }
                    HStack {
                        TextField("Трек-номер СДЭК", text: $track).font(Theme.font(15)).keyboardType(.asciiCapable).autocorrectionDisabled().textInputAutocapitalization(.never)
                        Button("Сохранить") { Task { await patch(["track": track]) } }.font(Theme.font(14, .medium)).disabled(track == o.trackNumber)
                    }
                    if !o.trackNumber.isEmpty { Text("Покупателю приходит письмо и уведомление с трек-номером").font(Theme.font(12)).foregroundStyle(Theme.dim) }
                }
                Section("Товары") {
                    ForEach(Array(o.items.enumerated()), id: \.offset) { _, it in
                        HStack(spacing: 12) {
                            RemoteImage(path: it.image).frame(width: 48, height: 62).clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(it.name).font(Theme.font(14))
                                Text([it.color, it.size, "\(it.qty) шт."].filter { !$0.isEmpty }.joined(separator: " · ")).font(Theme.font(12.5)).foregroundStyle(Theme.muted)
                            }
                            Spacer(); Text(Fmt.rub(it.price * it.qty)).font(Theme.font(14))
                        }
                    }
                }
                OrderRequestsSection(o: o.raw)
                OrderRefundSection(o: o.raw)
                if Shop.shared.cdekReady && (o.raw["delivery"]["pvz"].exists || o.raw["delivery"]["door"].exists || o.raw["cdek"].exists) { OrderCdekSection(o: o.raw) }
                Section("Заметка для команды") {
                    TextField("Видна только в панели", text: $note, axis: .vertical).font(Theme.font(14.5)).lineLimit(2...6)
                    if note != o.adminNote { Button("Сохранить заметку") { Task { await patch(["note": note]) } }.font(Theme.font(14, .medium)) }
                }
                if !o.history.isEmpty {
                    Section("История") {
                        ForEach(Array(o.history.reversed().enumerated()), id: \.offset) { _, h in
                            VStack(alignment: .leading, spacing: 2) { Text(h.text).font(Theme.font(13.5)); Text(Fmt.date(h.at, time: true)).font(Theme.font(11.5)).foregroundStyle(Theme.dim) }
                        }
                    }
                }
                OrderDeleteSection(o: o.raw)
                if let error { Text(error).font(Theme.font(13)).foregroundStyle(Theme.danger) }
            }
            .navigationTitle("Заказ № \(o.number)").navigationBarTitleDisplayMode(.inline)
            .disabled(busy)
            .overlay { if busy { ProgressView() } }
            .onAppear { track = o.trackNumber; note = o.adminNote }
            .refreshable { await admin.load() }
        } else {
            ProgressView().task { if !admin.data.exists { await admin.load() } }
        }
    }
    private func patch(_ b: [String: Any]) async {
        busy = true; error = nil; defer { busy = false }
        do { _ = try await API.shared.raw("PATCH", "admin/orders/\(id)", body: b); await admin.load(); Haptic.success(); Toast.shared.show("Сохранено") }
        catch { self.error = error.localizedDescription; Haptic.error() }
    }
}

// MARK: - Поддержка
struct AdminSupportView: View {
    @EnvironmentObject private var router: Router
    @State private var tickets: [JSON] = []
    @State private var showClosed = false
    var body: some View {
        List {
            Toggle("Показать закрытые", isOn: $showClosed).font(Theme.font(14)).tint(Theme.ink)
            ForEach(Array(tickets.filter { showClosed || $0["status"].str != "closed" }.enumerated()), id: \.offset) { _, t in
                Button { router.push(.adminTicket(t["id"].str), on: .account) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("№ \(t["number"].str) · \(t["name"].str)").font(Theme.font(15, t["unreadShop"].bool ? .semibold : .medium))
                            Spacer(); if t["unreadShop"].bool { Circle().fill(Theme.accent).frame(width: 8, height: 8) }
                        }
                        Text(t["topic"].str + (t["orderNumber"].str.isEmpty ? "" : " · заказ № " + t["orderNumber"].str)).font(Theme.font(12.5)).foregroundStyle(Theme.muted)
                        Text(t["messages"].array.last?["text"].str ?? "").font(Theme.font(13)).foregroundStyle(Theme.muted).lineLimit(2)
                    }.foregroundStyle(Theme.text).padding(.vertical, 4)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Поддержка").navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }
    private func load() async { if let r = try? await API.shared.json("GET", "admin/support") { tickets = r["tickets"].array } }
}

struct AdminTicketView: View {
    let id: String
    @State private var t = JSON(nil)
    @State private var draft = ""
    @State private var busy = false
    var body: some View {
        ChatView(messages: t["messages"].array, mine: { $0["from"].str != "user" }, draft: $draft, busy: busy, closed: false) {
            busy = true
            Task {
                if let r = try? await API.shared.json("POST", "admin/support/\(id)", body: ["text": draft]) { t = r["ticket"]; draft = ""; Haptic.success() }
                busy = false
            }
        }
        .navigationTitle(t["name"].string ?? "Обращение").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(t["status"].str == "closed" ? "Открыть" : "Закрыть") {
                    Task { if let r = try? await API.shared.json("PATCH", "admin/support/\(id)", body: ["status": t["status"].str == "closed" ? "open" : "closed"]) { t = r["ticket"] } }
                }.font(Theme.font(14, .medium))
            }
        }
        .task { await load() }
    }
    private func load() async {
        if let r = try? await API.shared.json("GET", "admin/support") { t = r["tickets"].array.first { $0["id"].str == id } ?? JSON(nil) }
        _ = try? await API.shared.raw("PATCH", "admin/support/\(id)", body: ["read": true])
    }
}

// MARK: - Покупатели и бонусы
struct AdminCustomersView: View {
    @ObservedObject private var admin = Admin.shared
    @State private var q = ""
    @State private var bonusFor: JSON?
    var body: some View {
        List {
            ForEach(Array(admin.data["users"].array.filter { q.isEmpty || ($0["firstName"].str + " " + $0["lastName"].str + " " + $0["phone"].str + " " + $0["email"].str).lowercased().contains(q.lowercased()) }.prefix(200).enumerated()), id: \.offset) { _, u in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text([u["firstName"].str, u["lastName"].str].joined(separator: " ")).font(Theme.font(15))
                        Text(Fmt.phone(u["phone"].str) + " · " + u["email"].str).font(Theme.font(12)).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Button("\(u["bonus"].int ?? 0) б.") { bonusFor = u }.font(Theme.font(13, .medium)).buttonStyle(.bordered).tint(Theme.ink)
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $q, placement: .navigationBarDrawer(displayMode: .always), prompt: "Имя, телефон, почта")
        .navigationTitle("Покупатели").navigationBarTitleDisplayMode(.inline)
        .task { if !admin.data.exists { await admin.load() } }
        .sheet(item: Binding(get: { bonusFor.map { IdentJSON(j: $0) } }, set: { bonusFor = $0?.j })) { w in BonusGrantSheet(user: w.j) }
    }
}
struct IdentJSON: Identifiable { let j: JSON; var id: String { j["id"].str } }

struct BonusGrantSheet: View {
    let user: JSON
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var note = ""
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Бонусы — \(user["firstName"].str)").font(Theme.font(22, .light))
            Text("Сейчас: \(user["bonus"].int ?? 0). Минус — списать.").font(Theme.font(13.5)).foregroundStyle(Theme.muted)
            Field(label: "Сколько", text: $amount, placeholder: "500 или -200", keyboard: .numbersAndPunctuation)
            Field(label: "За что (увидит покупатель)", text: $note)
            ErrorText(text: error)
            PrimaryButton(title: "Начислить") {
                Task {
                    do { _ = try await API.shared.raw("POST", "admin/users/\(user["id"].str)/bonus", body: ["amount": Int(amount) ?? 0, "note": note]); await Admin.shared.load(); Haptic.success(); dismiss() }
                    catch { self.error = error.localizedDescription }
                }
            }
            Spacer()
        }.padding(20).presentationDetents([.medium])
    }
}

// MARK: - Push: свои уведомления и рассылка акций
struct AdminPushView: View {
    @State private var r = JSON(nil)
    @State private var prefs: [String: Bool] = [:]
    @State private var title = ""
    @State private var text = ""
    @State private var link = "/catalog"
    @State private var busy = false
    @State private var error: String?
    @State private var armed = false
    private let names: [String: (String, String)] = ["order": ("Новый заказ", "С оплатой при получении"), "paid": ("Заказ оплачен", "Онлайн-оплата прошла"),
        "support": ("Вопрос покупателя", "Новые обращения"), "request": ("Заявка на обмен или возврат", ""), "returnIn": ("Возврат пришёл на склад", ""),
        "stock": ("Заканчивается размер", "2 штуки или меньше"), "digest": ("Итоги дня", "В 21:00 по Москве"), "security": ("Вход в панель", "С нового устройства")]
    var body: some View {
        Form {
            Section("Что присылать мне") {
                ForEach(prefs.keys.sorted { (names[$0]?.0 ?? $0) < (names[$1]?.0 ?? $1) }, id: \.self) { k in
                    Toggle(isOn: Binding(get: { prefs[k] ?? false }, set: { prefs[k] = $0; Task { _ = try? await API.shared.raw("PUT", "admin/push", body: ["prefs": prefs]) } })) {
                        VStack(alignment: .leading, spacing: 2) { Text(names[k]?.0 ?? k).font(Theme.font(15)); if let s = names[k]?.1, !s.isEmpty { Text(s).font(Theme.font(12)).foregroundStyle(Theme.muted) } }
                    }.tint(Theme.ink)
                }
            }
            if let aud = r["audience"].int {
                Section {
                    TextField("Заголовок", text: $title).font(Theme.font(15))
                    TextField("Текст", text: $text, axis: .vertical).font(Theme.font(15)).lineLimit(2...4)
                    TextField("Ссылка: /catalog, /sale, /product/…", text: $link).font(Theme.font(14)).autocorrectionDisabled().textInputAutocapitalization(.never)
                    NotificationMock(title: title.isEmpty ? "Заголовок уведомления" : title, text: text.isEmpty ? "Текст — одна-две строки о главном" : text).listRowInsets(EdgeInsets())
                    if let error { Text(error).font(Theme.font(13)).foregroundStyle(Theme.danger) }
                    Button("Прислать пробное мне") { Task { await broadcast(test: true) } }.font(Theme.font(15))
                    Button(armed ? "Точно отправить \(aud)? Нажмите ещё раз" : "Отправить \(aud) \(Fmt.plural(aud, "покупателю", "покупателям", "покупателям"))") {
                        if !armed { armed = true } else { Task { await broadcast(test: false) } }
                    }.font(Theme.font(15, .medium)).foregroundStyle(armed ? Theme.danger : Theme.text).disabled(aud == 0 || busy)
                } header: { Text("Рассылка покупателям") } footer: { Text("Только тем, кто включил «Акции и новинки». Пишите редко и по делу.").font(Theme.font(12)) }
            }
        }
        .navigationTitle("Push-уведомления").navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }
    private func load() async { if let j = try? await API.shared.json("GET", "admin/push") { r = j; prefs = j["prefs"].dict.mapValues(\.bool) } }
    private func broadcast(test: Bool) async {
        busy = true; error = nil; defer { busy = false; armed = false }
        do {
            let j = try await API.shared.json("POST", "admin/push/broadcast", body: ["title": title, "body": text, "url": link, "test": test])
            Toast.shared.show(test ? "Пробное отправлено" : "Доставлено: \(j["sent"].int ?? 0) из \(j["to"].int ?? 0)"); Haptic.success()
            if !test { await load() }
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Журнал действий
struct AdminAuditView: View {
    @State private var items: [JSON] = []
    @State private var q = ""
    var body: some View {
        List {
            ForEach(Array(items.enumerated()), id: \.offset) { _, x in
                VStack(alignment: .leading, spacing: 4) {
                    Text(x["text"].str).font(Theme.font(14))
                    Text([x["name"].string ?? "Система", x["role"].str, Fmt.date(ISO.date(x["at"].str), time: true)].filter { !$0.isEmpty }.joined(separator: " · ")).font(Theme.font(11.5)).foregroundStyle(Theme.dim)
                }.padding(.vertical, 3)
            }
        }
        .listStyle(.plain)
        .searchable(text: $q, placement: .navigationBarDrawer(displayMode: .always), prompt: "Номер заказа, товар, слово")
        .navigationTitle("Журнал действий").navigationBarTitleDisplayMode(.inline)
        .task(id: q) {
            guard (try? await Task.sleep(nanoseconds: q.isEmpty ? 0 : 300_000_000)) != nil else { return }
            if let r = try? await API.shared.json("GET", "admin/audit", query: q.isEmpty ? [:] : ["q": q]) { items = r["items"].array }
        }
    }
}
