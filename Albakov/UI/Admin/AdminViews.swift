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
                    Text("Панель управления").font(Theme.font(24, .light))
                    Text(admin.roleName).font(Theme.font(13)).foregroundStyle(Theme.muted)
                }.padding(.vertical, 6)
                if admin.can("orders") {
                    let o = admin.orders
                    let today = o.filter { Calendar.current.isDateInToday($0.createdAt ?? .distantPast) && $0.status != "canceled" }
                    HStack(spacing: 10) {
                        stat("Сегодня", "\(today.count)", Fmt.rub(today.reduce(0) { $0 + $1.total }))
                        stat("Новые", "\(o.filter { $0.status == "new" }.count)", "ждут сборки")
                        stat("В пути", "\(o.filter { $0.status == "shipped" }.count)", "у СДЭК")
                    }
                }
            }
            Section {
                if admin.can("orders") {
                    item("Заказы", "shippingbox", .adminOrders, badge: admin.orders.filter { $0.status == "new" }.count)
                    item("Поддержка", "bubble.left.and.text.bubble.right", .adminSupport, badge: admin.data["supportNew"].int ?? 0)
                }
                if admin.can("content") { item("Товары и остатки", "tshirt", .adminProducts) }
                if admin.can("orders") || admin.can("marketing") { item("Покупатели и бонусы", "person.2", .adminCustomers) }
                item("Push-уведомления", "bell.badge", .adminPush)
                if admin.can("staff") { item("Журнал действий", "list.bullet.rectangle", .adminAudit) }
            }
        }
        .navigationTitle("Панель")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if admin.loading && !admin.data.exists { ProgressView() } }
        .task { await admin.load() }
        .refreshable { await admin.load() }
    }
    private func stat(_ t: String, _ v: String, _ s: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(t).font(Theme.font(11.5)).foregroundStyle(Theme.muted)
            Text(v).font(Theme.font(24, .light))
            Text(s).font(Theme.font(11)).foregroundStyle(Theme.dim).lineLimit(1).minimumScaleFactor(0.8)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
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

// MARK: - Товары и остатки
struct AdminProductsView: View {
    @EnvironmentObject private var router: Router
    @ObservedObject private var admin = Admin.shared
    @State private var q = ""
    var body: some View {
        List {
            ForEach(Array(admin.products.filter { q.isEmpty || ($0["name"].str + " " + $0["sku"].str).lowercased().contains(q.lowercased()) }.enumerated()), id: \.offset) { _, p in
                let prod = Product(p)
                Button { router.push(.adminProduct(prod.id), on: .account) } label: {
                    HStack(spacing: 12) {
                        RemoteImage(path: prod.image).frame(width: 48, height: 62).clipShape(RoundedRectangle(cornerRadius: 8)).opacity(prod.active ? 1 : 0.4)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(prod.name).font(Theme.font(14.5))
                            Text("\(Fmt.rub(prod.price)) · остаток \(prod.stock)" + (prod.active ? "" : " · скрыт")).font(Theme.font(12.5)).foregroundStyle(prod.stock == 0 ? Theme.danger : Theme.muted)
                        }
                    }.foregroundStyle(Theme.text)
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $q, placement: .navigationBarDrawer(displayMode: .always), prompt: "Название или артикул")
        .navigationTitle("Товары").navigationBarTitleDisplayMode(.inline)
        .task { if !admin.data.exists { await admin.load() } }   // открыт сразу из push или ссылки — минуя главную панели
        .refreshable { await admin.load() }
    }
}

struct AdminProductView: View {
    let id: String
    @ObservedObject private var admin = Admin.shared
    @State private var draft: [String: Any] = [:]
    @State private var price = ""
    @State private var compareAt = ""
    @State private var active = true
    @State private var stock: [String: Int] = [:]   // "цвет|размер" → остаток
    @State private var busy = false
    @State private var error: String?
    @State private var photo: PhotosPickerItem?
    @State private var photoColor = ""

    private var raw: JSON? { admin.products.first { $0["id"].str == id } }

    var body: some View {
        if let raw {
            let p = Product(raw)
            Form {
                Section {
                    Text(p.name).font(Theme.font(20, .light))
                    Toggle("Показывать на сайте", isOn: $active).tint(Theme.ink)
                }
                Section("Цена") {
                    HStack { Text("Цена, ₽"); Spacer(); TextField("0", text: $price).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                    HStack { Text("Старая цена, ₽"); Spacer(); TextField("нет", text: $compareAt).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                }
                ForEach(p.colors) { c in
                    Section("Остатки · \(c.name)") {
                        ForEach(c.sizes, id: \.size) { s in
                            let k = c.id + "|" + s.size
                            Stepper(value: Binding(get: { stock[k] ?? s.stock }, set: { stock[k] = max(0, $0) }), in: 0...9999) {
                                HStack { Text(s.size).font(Theme.font(15, .medium)); Spacer(); Text("\(stock[k] ?? s.stock) шт.").font(Theme.font(15)).foregroundStyle((stock[k] ?? s.stock) == 0 ? Theme.danger : Theme.text) }
                            }
                        }
                        PhotosPicker(selection: Binding(get: { photo }, set: { photo = $0; photoColor = c.id }), matching: .images) {
                            Label("Добавить фото (\(c.images.count))", systemImage: "photo.badge.plus").font(Theme.font(14))
                        }
                    }
                }
                if let error { Text(error).font(Theme.font(13)).foregroundStyle(Theme.danger) }
                Section { PrimaryButton(title: "Сохранить", busy: busy) { Task { await save(raw) } }.listRowInsets(EdgeInsets()).listRowBackground(Color.clear) }
            }
            .navigationTitle("Товар").navigationBarTitleDisplayMode(.inline)
            .onAppear { price = "\(p.price)"; compareAt = p.compareAt > 0 ? "\(p.compareAt)" : ""; active = p.active }
            .onChange(of: photo) { item in Task { await addPhoto(item, raw) } }
        } else { ProgressView().task { if !admin.data.exists { await admin.load() } } }
    }

    private func mutable(_ raw: JSON) -> [String: Any] { (raw.raw as? [String: Any]) ?? [:] }

    private func save(_ raw: JSON) async {
        busy = true; error = nil; defer { busy = false }
        var v = mutable(raw)
        v["price"] = Int(price) ?? 0
        v["compareAt"] = Int(compareAt) ?? 0
        v["active"] = active
        if var colors = v["colors"] as? [[String: Any]] {
            for ci in colors.indices {
                let cid = colors[ci]["id"] as? String ?? ""
                if var sizes = colors[ci]["sizes"] as? [[String: Any]] {
                    for si in sizes.indices { let k = cid + "|" + (sizes[si]["size"] as? String ?? ""); if let n = stock[k] { sizes[si]["stock"] = n } }
                    colors[ci]["sizes"] = sizes
                }
            }
            v["colors"] = colors
        }
        do { _ = try await API.shared.raw("PUT", "admin/products/\(id)", body: ["value": v]); await admin.load(); stock = [:]; Haptic.success(); Toast.shared.show("Товар сохранён") }
        catch { self.error = error.localizedDescription; Haptic.error() }
    }

    private func addPhoto(_ item: PhotosPickerItem?, _ raw: JSON) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) else { return }
        busy = true; defer { busy = false; photo = nil }
        // Сжимаем до 2000 px по длинной стороне — как при загрузке на сайте
        let scale = min(1, 2000 / max(img.size.width, img.size.height))
        let size = CGSize(width: img.size.width * scale, height: img.size.height * scale)
        let jpg = UIGraphicsImageRenderer(size: size).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }.jpegData(compressionQuality: 0.85) ?? data
        do {
            let url = try await API.shared.upload(jpg)
            var v = mutable(raw)
            if var colors = v["colors"] as? [[String: Any]], let ci = colors.firstIndex(where: { ($0["id"] as? String) == photoColor }) {
                var imgs = colors[ci]["images"] as? [String] ?? []; imgs.append(url); colors[ci]["images"] = imgs; v["colors"] = colors
                _ = try await API.shared.raw("PUT", "admin/products/\(id)", body: ["value": v]); await admin.load(); Toast.shared.show("Фото добавлено")
            }
        } catch { self.error = error.localizedDescription }
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
            try? await Task.sleep(nanoseconds: q.isEmpty ? 0 : 300_000_000)
            if let r = try? await API.shared.json("GET", "admin/audit", query: q.isEmpty ? [:] : ["q": q]) { items = r["items"].array }
        }
    }
}
