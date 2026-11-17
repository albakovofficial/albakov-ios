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
        catch { self.error = error.userMessage }
    }
}

/// Рабочий стол панели (13.63, вариант C): сводка дня цветом раздела, ежедневное — крупными карточками, остальное — значками по 4 в ряд
struct AdminHomeView: View {
    @EnvironmentObject private var router: Router
    @StateObject private var admin = Admin.shared
    @State private var find = ""
    private static let work = ["orders", "support", "products", "exchange"]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let e = admin.error { Text(e).font(Theme.font(14)).foregroundStyle(Theme.danger) }
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .light)).foregroundStyle(Theme.dim)
                    TextField("Найти раздел", text: $find).font(Theme.font(15)).textInputAutocapitalization(.never).autocorrectionDisabled()
                }.padding(.horizontal, 14).frame(height: 44).background(RoundedRectangle(cornerRadius: 14).fill(.white)).hairline(RoundedRectangle(cornerRadius: 14), 0.07)
                if find.isEmpty {
                    if admin.can("orders") { summary }
                    ForEach(admin.data["problems"].array.indices, id: \.self) { i in
                        Text(admin.data["problems"].array[i]["title"].str + ". " + admin.data["problems"].array[i]["text"].str).font(Theme.font(13)).foregroundStyle(Theme.warn)
                    }
                }
                let w = Self.work.filter { AdminSections.can($0) && match($0) }
                if !w.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(w, id: \.self) { k in workCard(k) }
                    }
                }
                let rest = AdminSections.list.filter { AdminSections.can($0.key) && !Self.work.contains($0.key) && match($0.key) }
                if !rest.isEmpty {
                    Text("ВСЕ РАЗДЕЛЫ").font(Theme.font(11, .semibold)).kerning(1.3).foregroundStyle(Theme.dim).padding(.top, 8).padding(.leading, 4)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 14) {
                        ForEach(rest, id: \.key) { s in
                            Button { router.push(dest(s.key), on: .account) } label: {
                                VStack(spacing: 6) {
                                    chip(s.key, s.icon, 46)
                                    Text(AdminSections.short(s.key, s.title)).font(Theme.font(11)).foregroundStyle(Theme.text).multilineTextAlignment(.center).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                                }.frame(maxWidth: .infinity)
                            }.buttonStyle(Pressable())
                        }
                    }
                    .padding(.vertical, 16).padding(.horizontal, 6).background(RoundedRectangle(cornerRadius: 22).fill(.white)).hairline(RoundedRectangle(cornerRadius: 22), 0.06)
                }
                if !find.isEmpty && w.isEmpty && rest.isEmpty { Text("Такого раздела нет").font(Theme.font(14)).foregroundStyle(Theme.dim).padding(.top, 8) }
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 40)
        }
        .background(Color(hex: "#f6f7f9"))
        .navigationTitle("Панель")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if admin.loading && !admin.data.exists { ProgressView() } }
        .task { await admin.load() }
        .refreshable { await admin.load() }
    }
    private func match(_ k: String) -> Bool {
        let q = find.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty, let s = AdminSections.list.first(where: { $0.key == k }) else { return true }
        return (s.title + " " + AdminSections.short(k, s.title)).lowercased().contains(q)
    }
    /// Сводка дня: заказы и сумма за сегодня, новые, в пути
    private var summary: some View {
        let o = admin.orders
        let today = o.filter { Calendar.current.isDateInToday($0.createdAt ?? .distantPast) && $0.status != "canceled" }
        return Button { router.push(.adminOrders, on: .account) } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) { Text("Сегодня").font(Theme.font(18, .medium)); Spacer(); Text(admin.roleName).font(Theme.font(12.5)).opacity(0.75) }
                HStack(spacing: 8) {
                    kpi("\(today.count)", "\(Fmt.plural(today.count, "заказ", "заказа", "заказов")) · \(Fmt.rub(today.reduce(0) { $0 + $1.total }))")
                    kpi("\(o.filter { $0.status == "new" }.count)", "новых, ждут сборки")
                    kpi("\(o.filter { $0.status == "shipped" }.count)", "в пути у СДЭК")
                }
            }
            .foregroundStyle(.white).padding(16)
            .background(RoundedRectangle(cornerRadius: 24).fill(Theme.accentGradient).overlay(RoundedRectangle(cornerRadius: 24).fill(RadialGradient(colors: [.white.opacity(0.14), .clear], center: .topLeading, startRadius: 0, endRadius: 240))))
        }.buttonStyle(Pressable())
    }
    private func kpi(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 2) { Text(v).font(Theme.font(24)); Text(l).font(Theme.font(10.5)).opacity(0.78).lineLimit(2).fixedSize(horizontal: false, vertical: true) }
            .padding(10).frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading).background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.1)))
    }
    private func workCard(_ k: String) -> some View {
        let s = AdminSections.list.first(where: { $0.key == k })!
        let n = badge(k)
        let sub: String = {
            switch k {
            case "orders": return n > 0 ? "\(n) \(Fmt.plural(n, "новый", "новых", "новых"))" : "новых нет"
            case "support": return n > 0 ? "\(n) \(Fmt.plural(n, "вопрос", "вопроса", "вопросов"))" : "вопросов нет"
            case "products": return n > 0 ? "\(n) ждут поступления" : "\(admin.products.filter { !$0["active"].exists || $0["active"].bool }.count) в продаже"
            default: return n > 0 ? "\(n) \(Fmt.plural(n, "заявка", "заявки", "заявок"))" : "заявок нет"
            }
        }()
        return Button { router.push(dest(k), on: .account) } label: {
            VStack(alignment: .leading, spacing: 2) {
                chip(k, s.icon, 40).padding(.bottom, 10)
                Text(AdminSections.short(k, s.title)).font(Theme.font(15, .medium)).foregroundStyle(Theme.text)
                Text(sub).font(Theme.font(12)).foregroundStyle(Theme.dim)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 20).fill(.white)).hairline(RoundedRectangle(cornerRadius: 20), 0.06)
            .overlay(alignment: .topTrailing) {
                if n > 0 { Text("\(n)").font(Theme.font(11.5, .semibold)).foregroundStyle(.white).padding(.horizontal, 6).frame(minWidth: 22, minHeight: 22).background(Capsule().fill(Theme.accentGradient)).padding(12) }
            }
        }.buttonStyle(Pressable())
    }
    /// Значок раздела на плашке цвета группы: продажи — цвет раздела, каталог и управление — графит, маркетинг и витрина — небесный
    private func chip(_ k: String, _ icon: String, _ size: CGFloat) -> some View {
        let g = AdminSections.group(k)
        let fill = g == 0 ? Theme.tint : g == 2 || g == 4 ? Color(hex: "#e9f3fc") : Color(hex: "#eff0f2")
        let tint = g == 0 ? Theme.accent : g == 2 || g == 4 ? Color(hex: "#3f86cc") : Color(hex: "#25272b")
        return IconTile(icon: icon, size: size, fill: fill, tint: tint)
    }
    private func dest(_ k: String) -> Dest {
        switch k {
        case "orders": return .adminOrders
        case "support": return .adminSupport
        case "customers": return .adminCustomers
        case "push": return .adminPush
        case "audit": return .adminAudit
        case "products": return .adminProducts
        default: return .adminSection(k)
        }
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
            (q.isEmpty || ("\(o.number) \(o.customerName) \(o.phone) \(o.email) " + o.items.map { $0.sku + " " + $0.name }.joined(separator: " ")).lowercased().contains(q.lowercased()))
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
        .searchable(text: $q, placement: .navigationBarDrawer(displayMode: .always), prompt: "Номер, имя, телефон, артикул")
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
    @State private var deleting: JSON?
    @EnvironmentObject private var router: Router
    private var order: Order? { admin.orders.first { $0.id == id } }

    var body: some View {
        Group { content }
            // окно удаления держим снаружи списка и ветки «заказ загружен» — обновление данных его не закроет (1.0.3)
            .sheet(item: Binding(get: { deleting.map { IdentJSON(j: $0) } }, set: { deleting = $0?.j })) { w in
                OrderDeleteSheet(o: w.j) { router.pop(on: .account) }
                    .presentationDetents([.height(w.j["payment"]["status"].str == "paid" ? 560 : 500)])
            }
    }
    @ViewBuilder private var content: some View {
        if let o = order {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { Text("№ \(o.number)").font(Theme.font(26, .light)); Spacer(); StatusPill(status: o.status, admin: true) }
                        Text(Fmt.date(o.createdAt, time: true)).font(Theme.font(13)).foregroundStyle(Theme.muted)
                        Text("\(Fmt.rub(o.total)) · \(o.payMethodText.lowercased()) · \(o.payStatusText)")
                            .font(Theme.font(14, .medium)).foregroundStyle(o.paid || o.payMethod == "cod" ? Theme.text : Theme.danger)
                        if o.awaitingPay && o.payBy != nil { PayLeftLabel(order: o, prefix: "Покупатель оплачивает · осталось ") }
                        else if o.payExpired { Text("Время на оплату вышло — заказ отменён автоматически").font(Theme.font(12)).foregroundStyle(Theme.muted) }
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
                            ProductImage(path: it.image, kind: it.artKind, tone: it.artTone).frame(width: 48, height: 62).background(Theme.photo).clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(it.name).font(Theme.font(14))
                                Text(it.meta).font(Theme.font(12.5)).foregroundStyle(Theme.muted)
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
                OrderDeleteSection { deleting = o.raw }
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
        catch { self.error = error.userMessage; Haptic.error() }
    }
}

// MARK: - Поддержка
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
                    catch { self.error = error.userMessage }
                }
            }
            Spacer()
        }.padding(20).presentationDetents([.medium])
    }
}

// MARK: - Push: свои уведомления и рассылка акций
struct AdminPushView: View {
    @ObservedObject private var push = PushManager.shared
    @Environment(\.openURL) private var openURL
    @State private var r = JSON(nil)
    @State private var testing = false
    @State private var testMsg: String?
    @State private var prefs: [String: Bool] = [:]
    @State private var prefsError: String?
    /// Идёт сохранение: переключатели ждут ответа — два одновременных сохранения целого набора могли бы разойтись с экраном
    @State private var saving = false
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
            // Это устройство (1.0.2): получает ли оно уведомления панели — новые заказы, оплаты, вопросы
            Section {
                HStack(spacing: 12) {
                    Image(systemName: deviceOk ? "bell.badge.fill" : "bell.slash").font(.system(size: 20)).foregroundStyle(deviceOk ? Theme.ok : Theme.warn).frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(deviceOk ? "Уведомления панели приходят сюда" : deviceTitle).font(Theme.font(15, .medium))
                        Text(deviceOk ? "Новые заказы, оплаты и вопросы — по вашей роли, даже когда приложение закрыто" : deviceHint).font(Theme.font(12.5)).foregroundStyle(Theme.muted)
                    }
                }.padding(.vertical, 4)
                if push.status == .notDetermined { Button("Разрешить уведомления") { Task { await push.request(); await load() } }.font(Theme.font(15, .medium)) }
                else if push.status == .denied { Button("Открыть настройки iPhone") { if let u = URL(string: UIApplication.openSettingsURLString) { openURL(u) } }.font(Theme.font(15, .medium)) }
                if push.status == .authorized || push.status == .provisional {
                    Button(testing ? "Отправляем…" : "Прислать проверочное") { Task { await test() } }.font(Theme.font(15)).disabled(testing || push.endpoint == nil)
                    if let testMsg { Text(testMsg).font(Theme.font(12.5)).foregroundStyle(Theme.muted) }
                }
            } header: { Text("Это устройство") } footer: {
                if r.exists && !r["apnsReady"].bool { Text("Ключ Apple для уведомлений ещё не добавлен — пока его нет, уведомления в приложение не приходят. Владелец добавляет его на сайте: Панель → Push-уведомления → «Приложение iPhone».").font(Theme.font(12)).foregroundStyle(Theme.danger) }
            }
            Section("Что присылать мне") {
                if let prefsError, prefs.isEmpty { ErrorRetry(text: "Настройки не загрузились: " + prefsError) { Task { await load() } } }
                ForEach(prefs.keys.sorted { (names[$0]?.0 ?? $0) < (names[$1]?.0 ?? $1) }, id: \.self) { k in
                    Toggle(isOn: Binding(get: { prefs[k] ?? false }, set: { on in prefs[k] = on; saving = true; Task { await savePref(k, was: !on) } })) {
                        VStack(alignment: .leading, spacing: 2) { Text(names[k]?.0 ?? k).font(Theme.font(15)); if let s = names[k]?.1, !s.isEmpty { Text(s).font(Theme.font(12)).foregroundStyle(Theme.muted) } }
                    }.tint(Theme.ink).disabled(saving)
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
    /// Не сохранилось — переключатель возвращается как был, причина — сообщением (Q-3).
    /// saving ставится ещё в переключателе, до запуска задачи: иначе второй переключатель успел бы отправить своё сохранение
    private func savePref(_ k: String, was: Bool) async {
        defer { saving = false }
        do { _ = try await API.shared.raw("PUT", "admin/push", body: ["prefs": prefs]) }
        catch { prefs[k] = was; Toast.shared.show(error.userMessage) }
    }
    private func load() async {
        push.refreshStatus(); push.resend()
        do { let j = try await API.shared.json("GET", "admin/push"); r = j; prefs = j["prefs"].dict.mapValues(\.bool); prefsError = nil }
        catch { if let m = error.userMessage { prefsError = m } }
    }
    private var deviceOk: Bool { (push.status == .authorized || push.status == .provisional) && push.endpoint != nil && r["apnsReady"].bool }
    private var deviceTitle: String {
        switch push.status {
        case .denied: return "Уведомления запрещены"
        case .notDetermined: return "Уведомления ещё не разрешены"
        default: return r.exists && !r["apnsReady"].bool ? "Уведомления пока не приходят" : "Подключаем устройство…"
        }
    }
    private var deviceHint: String {
        switch push.status {
        case .denied: return "Разрешите уведомления для ALBAKOV в настройках iPhone — иначе о новых заказах не узнать сразу"
        case .notDetermined: return "Разрешите — и новые заказы будут приходить сразу"
        default: return r.exists && !r["apnsReady"].bool ? "Нужен ключ Apple — см. ниже" : "Через пару секунд обновите экран"
        }
    }
    private func test() async {
        guard let e = push.endpoint else { return }
        testing = true; testMsg = nil; defer { testing = false }
        do { _ = try await API.shared.raw("POST", "push/test", body: ["endpoint": e, "scope": "staff"]); testMsg = "Отправили — уведомление появится через пару секунд"; Haptic.success() }
        catch { testMsg = error.userMessage; Haptic.error() }
    }
    private func broadcast(test: Bool) async {
        busy = true; error = nil; defer { busy = false; armed = false }
        do {
            let j = try await API.shared.json("POST", "admin/push/broadcast", body: ["title": title, "body": text, "url": link, "test": test])
            Toast.shared.show(test ? "Пробное отправлено" : "Доставлено: \(j["sent"].int ?? 0) из \(j["to"].int ?? 0)"); Haptic.success()
            if !test { await load() }
        } catch { self.error = error.userMessage }
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
