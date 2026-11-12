import SwiftUI

// Подарочные сертификаты в панели: итоги, фильтр по статусу, список, выпуск вручную, повтор письма, отмена, настройки продажи.
struct AdminGifts: View {
    @ObservedObject private var admin = Admin.shared
    @State private var f = "all"
    @State private var issue = false
    @State private var cancelId: String?
    @State private var enabled = true
    @State private var noms = ""
    @State private var months = "12"
    @State private var min = "3000"
    @State private var max = "100000"
    @State private var error: String?
    static let st = ["active": ("Действует", Theme.ok), "pending": ("Ждёт оплаты", Theme.warn), "used": ("Использован", Theme.dim), "expired": ("Истёк", Theme.dim), "canceled": ("Отменён", Theme.dim)]

    var body: some View {
        let list = Array(admin.data["giftcards"].array.reversed())
        let shown = list.filter { f == "all" || $0["state"].str == f }
        let sold = list.filter { !["pending", "canceled"].contains($0["state"].str) }
        List {
            Section {
                Text("Покупатели покупают сертификаты на странице «Подарочные сертификаты» и оплачивают онлайн. Код уходит получателю письмом.").font(Theme.font(13)).foregroundStyle(Theme.muted)
                HStack(spacing: 8) {
                    AdminStat(title: "Продано и выпущено", value: "\(sold.count)")
                    AdminStat(title: "На сумму", value: Fmt.rub(sold.reduce(0) { $0 + ($1["amount"].int ?? 0) }))
                    AdminStat(title: "Не потрачено", value: Fmt.rub(sold.filter { $0["state"].str == "active" }.reduce(0) { $0 + ($1["balance"].int ?? 0) }))
                }
                Button { issue = true } label: { Label("Выпустить сертификат", systemImage: "plus").font(Theme.font(15, .medium)) }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach([("all", "Все"), ("active", "Действуют"), ("used", "Использованы"), ("pending", "Ждут оплаты"), ("expired", "Истекли"), ("canceled", "Отменены")], id: \.0) { x in
                            Chip(title: x.1 + " \(x.0 == "all" ? list.count : list.filter { $0["state"].str == x.0 }.count)", on: f == x.0, dark: true, height: 34) { f = x.0 }
                        }
                    }
                }
            }
            Section {
                if shown.isEmpty { Text("Сертификатов пока нет. Они появятся, когда кто-то купит сертификат или вы выпустите его вручную.").font(Theme.font(13.5)).foregroundStyle(Theme.muted) }
                ForEach(shown.indices, id: \.self) { i in
                    let g = shown[i], s = AdminGifts.st[g["state"].str] ?? (g["state"].str, Theme.text)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(g["code"].str).font(Theme.font(15, .medium)).kerning(1).textSelection(.enabled)
                            if g["manual"].bool { Text("вручную").font(Theme.font(11)).foregroundStyle(Theme.muted) }
                            Spacer(); Text(s.0).font(Theme.font(12, .medium)).foregroundStyle(s.1)
                        }
                        Text("\(Fmt.rub(g["amount"].int ?? 0)) · остаток \(Fmt.rub(g["balance"].int ?? 0))" + (g["expiresAt"].str.isEmpty ? "" : " · до " + Fmt.date(ISO.date(g["expiresAt"].str)))).font(Theme.font(13))
                        let to = g["to"]
                        if !to["name"].str.isEmpty || !to["email"].str.isEmpty { Text([to["name"].str, to["email"].str].filter { !$0.isEmpty }.joined(separator: " · ")).font(Theme.font(12.5)).foregroundStyle(Theme.muted) }
                        Text(!g["sentAt"].str.isEmpty ? "Письмо отправлено " + Fmt.date(ISO.date(g["sentAt"].str)) : !g["sendAt"].str.isEmpty ? "Отправим " + g["sendAt"].str : to["email"].str.isEmpty ? "Без письма" : "Письмо ещё не отправлено").font(Theme.font(12)).foregroundStyle(Theme.muted)
                        ForEach(g["log"].array.indices, id: \.self) { k in
                            let l = g["log"].array[k], a = l["amount"].int ?? 0
                            Text((a < 0 ? "Списано " + Fmt.rub(-a) : "Возвращено " + Fmt.rub(a)) + " · заказ № " + l["number"].str + " · " + Fmt.date(ISO.date(l["at"].str))).font(Theme.font(11.5)).foregroundStyle(Theme.dim)
                        }
                        HStack(spacing: 18) {
                            if g["state"].str == "active" && !to["email"].str.isEmpty { Button("Отправить письмо ещё раз") { Task { await post("gifts/\(g["id"].str)/resend", "Письмо отправлено") } } }
                            if ["active", "pending"].contains(g["state"].str) { Button("Отменить", role: .destructive) { cancelId = g["id"].str } }
                        }.font(Theme.font(13)).buttonStyle(.borderless).padding(.top, 2)
                    }.padding(.vertical, 4)
                }
            }
            Section("Настройки") {
                Toggle(isOn: $enabled) { VStack(alignment: .leading) { Text("Продавать сертификаты").font(Theme.font(15)); Text("Покупка работает только с подключённой ЮKassa").font(Theme.font(12)).foregroundStyle(Theme.muted) } }.tint(Theme.ink)
                LabeledContent("Номиналы, ₽") { TextField("5000, 10000", text: $noms).multilineTextAlignment(.trailing) }.font(Theme.font(14.5))
                LabeledContent("Срок, месяцев") { TextField("12", text: $months).keyboardType(.numberPad).multilineTextAlignment(.trailing) }.font(Theme.font(14.5))
                LabeledContent("Своя сумма от, ₽") { TextField("3000", text: $min).keyboardType(.numberPad).multilineTextAlignment(.trailing) }.font(Theme.font(14.5))
                LabeledContent("Своя сумма до, ₽") { TextField("100000", text: $max).keyboardType(.numberPad).multilineTextAlignment(.trailing) }.font(Theme.font(14.5))
                if let error { Text(error).font(Theme.font(13)).foregroundStyle(Theme.danger) }
                Button("Сохранить") { Task { await save() } }.font(Theme.font(15, .medium))
            }
        }
        .navigationTitle("Подарочные сертификаты").navigationBarTitleDisplayMode(.inline)
        .task { if !admin.data.exists { await admin.load() }; fill() }
        .refreshable { await admin.load() }
        .sheet(isPresented: $issue) { IssueGiftSheet(nominal: admin.data["settings"]["gifts"]["nominals"].array.dropFirst().first?.int ?? 10000) }
        .confirmationDialog("Отменить сертификат? Им больше нельзя будет оплатить заказ.", isPresented: Binding(get: { cancelId != nil }, set: { if !$0 { cancelId = nil } }), titleVisibility: .visible) {
            Button("Отменить сертификат", role: .destructive) { if let id = cancelId { Task { await post("gifts/\(id)/cancel", "Сертификат отменён") } } }
        }
    }
    private func fill() {
        let c = admin.data["settings"]["gifts"]
        enabled = !c["enabled"].exists || c["enabled"].bool
        let n = c["nominals"].array.compactMap(\.int); noms = (n.isEmpty ? [5000, 10000, 20000, 30000] : n).map(String.init).joined(separator: ", ")
        months = String(c["months"].int ?? 12); min = String(c["min"].int ?? 3000); max = String(c["max"].int ?? 100000)
    }
    private func post(_ path: String, _ ok: String) async {
        do { _ = try await AdminAPI.post(path); await admin.load(); Toast.shared.show(ok) } catch { Toast.shared.show(error.localizedDescription) }
    }
    private func save() async {
        error = nil
        let n = noms.split(whereSeparator: { ",; ".contains($0) }).compactMap { Int($0) }.filter { $0 >= 100 }.prefix(6)
        if n.isEmpty { error = "Укажите хотя бы один номинал"; return }
        var s = admin.data["settings"].dictAny
        s["gifts"] = ["enabled": enabled, "nominals": Array(n), "months": Swift.max(1, Swift.min(36, Int(months) ?? 12)), "min": Swift.max(100, Int(min) ?? 1000), "max": Swift.max(1000, Int(max) ?? 100000)]
        do { try await AdminAPI.saveSettings(s); await AdminAPI.reload(); Toast.shared.show("Сохранено") } catch { self.error = error.localizedDescription }
    }
}

/// Выпустить сертификат без оплаты — для подарка, розыгрыша или замены
struct IssueGiftSheet: View {
    let nominal: Int
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var name = ""
    @State private var email = ""
    @State private var msg = ""
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DotTitle(text: "Выпустить сертификат", size: 28, dot: false)
                Text("Без оплаты — для подарка, розыгрыша или замены. Если указать почту, код сразу уйдёт письмом.").font(Theme.font(14)).foregroundStyle(Theme.muted)
                Field(label: "Сумма, ₽", text: $amount, keyboard: .numberPad)
                Field(label: "Имя получателя", text: $name)
                Field(label: "Почта получателя — необязательно", text: $email, keyboard: .emailAddress, capitalization: .never)
                Field(label: "Пожелание", text: $msg)
                ErrorText(text: error)
                PrimaryButton(title: "Выпустить", busy: busy) { Task { await go() } }
            }.padding(20)
        }
        .onAppear { if amount.isEmpty { amount = String(nominal) } }
    }
    private func go() async {
        busy = true; defer { busy = false }
        do {
            let r = try await AdminAPI.post("gifts", ["amount": Int(amount) ?? 0, "toName": name, "toEmail": email, "message": msg])
            await Admin.shared.load(); Toast.shared.show("Сертификат \(r["gift"]["code"].str) выпущен" + (r["sent"].bool ? " и отправлен" : "")); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Обзор: выручка, заказы, средний чек, ждут действий, остатки, последние заказы

struct AdminOverview: View {
    @EnvironmentObject private var router: Router
    @ObservedObject private var admin = Admin.shared
    var body: some View {
        let o = admin.orders.filter { !["canceled"].contains($0.status) }
        let cal = Calendar.current
        let today = o.filter { cal.isDateInToday($0.createdAt ?? .distantPast) }
        let week = o.filter { ($0.createdAt ?? .distantPast) > Date().addingTimeInterval(-7 * 86400) }
        let month = o.filter { ($0.createdAt ?? .distantPast) > Date().addingTimeInterval(-30 * 86400) }
        let low = admin.products.flatMap { p in p["colors"].array.flatMap { c in c["sizes"].array.filter { ($0["stock"].int ?? 0) <= 1 }.map { (p["name"].str, c["name"].str, $0["size"].str, $0["stock"].int ?? 0) } } }
        List {
            Section {
                DotTitle(text: "Обзор", size: 28)
                HStack(spacing: 8) {
                    AdminStat(title: "Сегодня", value: Fmt.rub(today.reduce(0) { $0 + $1.total }), sub: "\(today.count) зак.")
                    AdminStat(title: "7 дней", value: Fmt.rub(week.reduce(0) { $0 + $1.total }), sub: "\(week.count) зак.")
                    AdminStat(title: "30 дней", value: Fmt.rub(month.reduce(0) { $0 + $1.total }), sub: "\(month.count) зак.")
                }
                HStack(spacing: 8) {
                    AdminStat(title: "Средний чек", value: month.isEmpty ? "—" : Fmt.rub(month.reduce(0) { $0 + $1.total } / month.count))
                    AdminStat(title: "Ждут сборки", value: "\(admin.orders.filter { $0.status == "new" }.count)")
                    AdminStat(title: "Покупателей", value: "\(admin.data["users"].array.count)")
                }
            }
            Section("Ждут действий") {
                link("Новые заказы", admin.orders.filter { $0.status == "new" }.count, .adminOrders)
                link("Вопросы в поддержке", admin.data["supportNew"].int ?? 0, .adminSupport)
                link("Заявки на обмен и возврат", admin.data["orders"].array.flatMap { $0["requests"].array }.filter { ["new", "received"].contains($0["status"].str) }.count, .adminSection("exchange"))
                link("Ждут поступления товара", admin.data["waitlist"].array.filter { $0["status"].str == "waiting" }.count, .adminSection("mail"))
            }
            if !low.isEmpty {
                Section("Заканчиваются") {
                    ForEach(low.prefix(15).indices, id: \.self) { i in
                        let x = low[i]
                        HStack { Text("\(x.0) · \(x.1) · \(x.2)").font(Theme.font(13.5)); Spacer(); Text(x.3 == 0 ? "нет" : "\(x.3) шт.").font(Theme.font(13, .medium)).foregroundStyle(x.3 == 0 ? Theme.danger : Theme.warn) }
                    }
                }
            }
            Section("Последние заказы") {
                ForEach(admin.orders.prefix(8)) { ord in Button { router.push(.adminOrder(ord.id), on: .account) } label: { OrderRow(order: ord, admin: true) }.foregroundStyle(Theme.text) }
            }
        }
        .navigationTitle("Обзор").navigationBarTitleDisplayMode(.inline)
        .task { if !admin.data.exists { await admin.load() } }
        .refreshable { await admin.load() }
    }
    private func link(_ t: String, _ n: Int, _ d: Dest) -> some View {
        Button { router.push(d, on: .account) } label: { HStack { Text(t).font(Theme.font(15)).foregroundStyle(Theme.text); Spacer(); Text("\(n)").font(Theme.font(14, .medium)).foregroundStyle(n > 0 ? Theme.accent : Theme.dim) } }
    }
}
