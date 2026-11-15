import SwiftUI

// Карточки заказа в панели, как на сайте: заявка покупателя (обмен/возврат), оплата и возврат денег,
// отправка СДЭК (создать, наклейка, накладная, статус, отмена), возврат через СДЭК, удаление заказа.

private func act(_ id: String, _ path: String, _ method: String = "POST", _ body: [String: Any] = [:]) async throws -> JSON {
    try await API.shared.json(method, "admin/orders/\(id)/\(path)", body: method == "DELETE" ? nil : body)
}
private func dt(_ s: String) -> String { Fmt.date(ISO.date(s), time: true) }

/// Заявка покупателя на обмен размера или возврат денег
struct OrderRequestsSection: View {
    let o: JSON
    @State private var declineFor: String?
    @State private var note = ""
    static let state = ["new": "Ждём вещь", "received": "Вещь проверена", "done": "Закрыта", "declined": "Отклонена"]
    static func what(_ r: JSON) -> String {
        r["lines"].array.map { l in l["name"].str + (l["color"].str.isEmpty ? "" : ", " + l["color"].str) + ", " + l["size"].str + (r["kind"].str == "exchange" ? " → " + l["toSize"].str : "") + ((l["qty"].int ?? 1) > 1 ? " × \(l["qty"].int ?? 1)" : "") }.joined(separator: "; ")
    }
    var body: some View {
        let list = Array(o["requests"].array.reversed())
        if !list.isEmpty {
            Section("Заявка покупателя") {
                ForEach(list.indices, id: \.self) { i in
                    let r = list[i], open = ["new", "received"].contains(r["status"].str)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text((r["kind"].str == "exchange" ? "Обмен размера" : "Возврат денег") + " · " + r["reasonLabel"].str).font(Theme.font(14.5, .medium)); Spacer(); Text(OrderRequestsSection.state[r["status"].str] ?? r["status"].str).font(Theme.font(12, .medium)).foregroundStyle(open ? Theme.accent : Theme.muted) }
                        Text(OrderRequestsSection.what(r)).font(Theme.font(13.5))
                        if !r["comment"].str.isEmpty { Text("«\(r["comment"].str)»").font(Theme.font(13)).foregroundStyle(Theme.muted) }
                        Text(dt(r["createdAt"].str) + (r["returnError"].str.isEmpty ? "" : " · возврат СДЭК не создан: " + r["returnError"].str)).font(Theme.font(12)).foregroundStyle(Theme.muted)
                        if !r["exchangeNumber"].str.isEmpty { Text("Заказ-обмен № " + r["exchangeNumber"].str).font(Theme.font(13, .medium)) }
                        if !r["declineNote"].str.isEmpty { Text("Причина отказа: " + r["declineNote"].str).font(Theme.font(12.5)).foregroundStyle(Theme.muted) }
                        if open {
                            if r["kind"].str == "exchange" {
                                Button("Вещь пришла и проверена — отправить " + r["lines"].array.map { $0["toSize"].str }.joined(separator: ", ")) { Task { await run(r["id"].str, "exchange") } }.font(Theme.font(14, .medium))
                            } else if r["status"].str == "new" {
                                Button("Вещь пришла и проверена") { Task { await run(r["id"].str, "received") } }.font(Theme.font(14, .medium))
                            } else { Text("Верните деньги в «Оплата и возврат» — заявка закроется сама").font(Theme.font(12.5)).foregroundStyle(Theme.muted) }
                            Button("Отклонить", role: .destructive) { declineFor = r["id"].str }.font(Theme.font(14))
                        }
                    }.padding(.vertical, 4)
                }
            }
            .alert("Почему отклоняем?", isPresented: Binding(get: { declineFor != nil }, set: { if !$0 { declineFor = nil } })) {
                TextField("Покупатель увидит это в поддержке", text: $note)
                Button("Отклонить", role: .destructive) { if let id = declineFor { Task { await run(id, "decline", note) } } }
                Button("Отмена", role: .cancel) {}
            }
        }
    }
    private func run(_ rid: String, _ action: String, _ note: String = "") async {
        do {
            let r = try await act(o["id"].str, "request", "POST", ["id": rid, "action": action, "note": note])
            await AdminAPI.reload(); Haptic.success()
            Toast.shared.show(r["exchange"].exists ? "Создан заказ-обмен № \(r["exchange"]["number"].str) — отправьте его как обычно" : action == "decline" ? "Заявка отклонена, резерв размера снят" : "Готово")
        } catch { Toast.shared.show(error.userMessage) }
    }
}

/// Оплата и возврат денег: суммы, плательщик, история, выбор позиций → сумма от сервера → подтверждение
struct OrderRefundSection: View {
    let o: JSON
    @State private var open = false
    @State private var lines: [Int: Int] = [:]
    @State private var delivery = false
    @State private var restock = true
    @State private var deduct = true
    @State private var reason = ""
    @State private var amount = 0
    @State private var deducted = 0
    @State private var armed = false
    @State private var busy = false
    @State private var error: String?
    @State private var key = uid("rf")
    private var retCost: Int { o["returns"].array.filter { ($0["cost"].int ?? 0) > 0 && !$0["deducted"].bool }.reduce(0) { $0 + ($1["cost"].int ?? 0) } }
    var body: some View {
        let pm = o["payment"], c = o["customer"], total = o["total"].int ?? 0, back = o["refunded"].int ?? 0
        let paidLike = ["paid", "refunded"].contains(pm["status"].str)
        let online = pm["method"].str == "online" && !pm["providerId"].str.isEmpty
        Section("Оплата и возврат") {
            HStack(spacing: 8) {
                AdminStat(title: "Оплачено", value: Fmt.rub(paidLike ? total : 0))
                AdminStat(title: "Возвращено", value: back > 0 ? "−" + Fmt.rub(back) : "0 ₽")
                AdminStat(title: "У магазина", value: Fmt.rub(paidLike ? max(0, total - back) : 0))
            }
            row("Плательщик", c["lastName"].str + " " + c["firstName"].str + " · " + Fmt.phone(c["phone"].str))
            row("Способ", (pm["method"].str == "online" ? "Онлайн через ЮKassa" : pm["method"].str == "bonus" ? "Бонусами" : pm["method"].str == "gift" ? "Подарочным сертификатом" : "При получении") + ((o["giftUsed"].int ?? 0) > 0 ? " · сертификатом \(Fmt.rub(o["giftUsed"].int ?? 0)) (\(o["giftCode"].str))" : ""))
            if online { row("Платёж ЮKassa", pm["providerId"].str) }
            ForEach(o["refunds"].array.indices, id: \.self) { i in
                let r = o["refunds"].array[i]
                VStack(alignment: .leading, spacing: 3) {
                    Text("−" + Fmt.rub(r["amount"].int ?? 0) + " · " + dt(r["at"].str) + (r["status"].str == "pending" ? " · в обработке" : "")).font(Theme.font(13.5, .medium)).foregroundStyle(Theme.sale)
                    Text((r["items"].array.map { "\($0["name"].str), \($0["size"].str) × \($0["qty"].int ?? 1)" } + (r["delivery"].bool ? ["доставка"] : [])).joined(separator: "; ")).font(Theme.font(12.5))
                    if !r["reason"].str.isEmpty { Text("Причина: " + r["reason"].str).font(Theme.font(12)).foregroundStyle(Theme.muted) }
                }
            }
            if online && pm["status"].str == "paid" {
                Button(open ? "Скрыть" : "Вернуть деньги") { withAnimation { open.toggle() } }.font(Theme.font(15, .medium))
                if open {
                    Text("Отметьте, за что возвращаете деньги. Сумму посчитаем сами — с учётом промокода и бонусов.").font(Theme.font(12.5)).foregroundStyle(Theme.muted)
                    ForEach(o["items"].array.indices, id: \.self) { i in
                        let it = o["items"].array[i], can = (it["qty"].int ?? 1) - (it["refundedQty"].int ?? 0)
                        if can <= 0 { Text("\(it["name"].str) · \(it["size"].str) — возвращено").font(Theme.font(13.5)).foregroundStyle(Theme.dim) }
                        else {
                            HStack {
                                Toggle(isOn: Binding(get: { lines[i] != nil }, set: { lines[i] = $0 ? can : nil; Task { await calc() } })) { VStack(alignment: .leading) { Text(it["name"].str).font(Theme.font(14)); Text([it["color"].str, "размер " + it["size"].str].filter { !$0.isEmpty }.joined(separator: " · ")).font(Theme.font(12)).foregroundStyle(Theme.muted) } }.tint(Theme.ink)
                                if can > 1, lines[i] != nil { Stepper("\(lines[i] ?? can) шт.", value: Binding(get: { lines[i] ?? can }, set: { lines[i] = $0; Task { await calc() } }), in: 1...can).font(Theme.font(13)).fixedSize() }
                            }
                        }
                    }
                    if (o["delivery"]["price"].int ?? 0) > 0 && !o["deliveryRefunded"].bool {
                        Toggle("Доставка — \(Fmt.rub(o["delivery"]["price"].int ?? 0))", isOn: Binding(get: { delivery }, set: { delivery = $0; Task { await calc() } })).font(Theme.font(14)).tint(Theme.ink)
                    }
                    // заказ отменён — товар вернулся на склад ещё при отмене, второй раз не прибавляем (аудит H-2)
                    if o["status"].str == "canceled" {
                        Text("Товар уже на складе — он вернулся туда, когда заказ отменили").font(Theme.font(13)).foregroundStyle(Theme.muted)
                    } else {
                        Toggle("Вернуть товар на склад (вещь вернулась к вам)", isOn: $restock).font(Theme.font(14)).tint(Theme.ink)
                    }
                    if retCost > 0 { Toggle("Удержать обратную доставку СДЭК — \(Fmt.rub(retCost))", isOn: Binding(get: { deduct }, set: { deduct = $0; Task { await calc() } })).font(Theme.font(14)).tint(Theme.ink) }
                    TextField("Причина, для себя — например, не подошёл размер", text: $reason).font(Theme.font(14))
                    HStack { Text("К возврату").font(Theme.font(15)); Spacer(); Text(Fmt.rub(amount) + (deducted > 0 ? " (удержано \(Fmt.rub(deducted)))" : "")).font(Theme.font(17, .medium)) }
                    Text("Деньги уйдут \(c["lastName"].str) \(c["firstName"].str) туда же, откуда была оплата заказа № \(o["number"].str). Покупатель получит письмо.").font(Theme.font(12.5)).foregroundStyle(Theme.muted)
                    ErrorText(text: error)
                    Button(armed ? "Подтвердить возврат \(Fmt.rub(amount))" : amount > 0 ? "Вернуть \(Fmt.rub(amount))" : "Выберите позиции", role: armed ? .destructive : nil) { Task { await refund() } }
                        .font(Theme.font(15, .medium)).disabled(amount == 0 || busy)
                }
            } else if pm["status"].str == "refunded" { Text("Деньги по заказу возвращены полностью.").font(Theme.font(13.5)).foregroundStyle(Theme.ok) }
            else if pm["method"].str == "cod" { Text("Оплата при получении — деньги возвращаются вручную, переводом покупателю.").font(Theme.font(13)).foregroundStyle(Theme.muted) }
            else if pm["method"].str == "online" && pm["status"].str != "paid" { Text("Заказ не оплачен — возвращать нечего.").font(Theme.font(13)).foregroundStyle(Theme.muted) }
        }
    }
    private func row(_ k: String, _ v: String) -> some View { HStack(alignment: .top) { Text(k).font(Theme.font(13)).foregroundStyle(Theme.muted); Spacer(); Text(v).font(Theme.font(13.5)).multilineTextAlignment(.trailing).textSelection(.enabled) } }
    private func payload(_ dry: Bool) -> [String: Any] {
        ["lines": lines.map { ["idx": $0.key, "qty": $0.value] }, "delivery": delivery, "restock": restock && o["status"].str != "canceled", "reason": reason, "dry": dry, "key": key, "deduct": deduct ? retCost : 0]
    }
    private func calc() async {
        armed = false; error = nil
        if lines.isEmpty && !delivery { amount = 0; return }
        do { let r = try await act(o["id"].str, "refund", "POST", payload(true)); amount = r["amount"].int ?? 0; deducted = r["deducted"].int ?? 0 }
        catch { amount = 0; self.error = error.userMessage }
    }
    private func refund() async {
        guard amount > 0 else { return }
        if !armed { armed = true; return }
        busy = true; defer { busy = false }
        do {
            let r = try await act(o["id"].str, "refund", "POST", payload(false))
            await AdminAPI.reload(); Haptic.success(); open = false; lines = [:]; armed = false; key = uid("rf")
            Toast.shared.show("Возврат \(Fmt.rub(r["refund"]["amount"].int ?? 0)) оформлен" + (r["refund"]["mailedAt"].exists ? ", покупателю отправлено письмо" : ""))
        } catch { self.error = error.userMessage; armed = false }
    }
}

/// Отправка СДЭК: создать отправление (вес и размеры посылки), наклейка и накладная (PDF), статус, отмена; возврат через СДЭК
struct OrderCdekSection: View {
    let o: JSON
    @ObservedObject private var admin = Admin.shared
    @State private var w = ""
    @State private var l = ""
    @State private var wd = ""
    @State private var h = ""
    @State private var busy = false
    @State private var error: String?
    @State private var pdf: URL?
    @State private var retOpen = false
    @State private var retLines: [Int: Int] = [:]
    @State private var retArmed = false
    @State private var confirmCancel = false
    static let step = ["ACCEPTED": "Заявка принята СДЭК", "CREATED": "Создано — отнесите посылку в пункт СДЭК"]
    static let retSt = ["ACCEPTED": "Заявка принята", "CREATED": "Ждём, когда покупатель сдаст посылку", "ACCEPTED_AT_PICK_UP_POINT": "Пришла в ваш пункт — заберите", "DELIVERED": "Получена вами"]
    var body: some View {
        let c = o["cdek"], sp = admin.data["settings"]["cdek"]["shipmentPoint"], pv = o["delivery"]["pvz"], door = o["delivery"]["door"].exists && !(o["delivery"]["door"].raw is NSNull)
        Section("Отправка СДЭК") {
            VStack(alignment: .leading, spacing: 4) {
                Text("Отправляете из: " + (sp["address"].string ?? "пункт не выбран")).font(Theme.font(13))
                Text((door ? "Курьер привезёт: " : "Получатель забирает: ") + (pv["address"].string ?? o["delivery"]["address"].string ?? "—")).font(Theme.font(13))
            }
            if o["payment"]["method"].str == "cod" { Text("Оплата при получении: СДЭК возьмёт с покупателя \(Fmt.rub((o["total"].int ?? 0) - (o["refunded"].int ?? 0)))").font(Theme.font(13, .medium)) }
            if !c.exists {
                if !sp.exists { Text("Сначала укажите пункт отгрузки: «Оплата и доставка» → «Отправка заказов в СДЭК».").font(Theme.font(13)).foregroundStyle(Theme.warn) }
                HStack(spacing: 6) { num("Вес, г", $w); num("Д, см", $l); num("Ш, см", $wd); num("В, см", $h) }
                let unpaid = o["payment"]["method"].str == "online" && o["payment"]["status"].str != "paid"
                Button(unpaid ? "Заказ ещё не оплачен" : "Создать отправление в СДЭК") { Task { await create() } }
                    .font(Theme.font(15, .medium)).disabled(unpaid || !sp.exists || ["canceled", "returned"].contains(o["status"].str) || busy)
                Text("СДЭК присвоит номер. Когда сдадите посылку в пункт, покупатель получит письмо с трек-номером, а заказ станет «Передан в доставку».").font(Theme.font(12)).foregroundStyle(Theme.muted)
            } else {
                let waiting = c["status"].str.isEmpty || ["ACCEPTED", "CREATED"].contains(c["status"].str)
                HStack { VStack(alignment: .leading) { Text("Номер СДЭК").font(Theme.font(12)).foregroundStyle(Theme.muted); Text(c["number"].string ?? "присваивается…").font(Theme.font(16, .medium)).textSelection(.enabled) }; Spacer(); Text(OrderCdekSection.step[c["status"].str] ?? (c["statusName"].string ?? "Обновляется")).font(Theme.font(12.5)).foregroundStyle(c["status"].str == "DELIVERED" ? Theme.ok : Theme.text).multilineTextAlignment(.trailing) }
                if !c["statusAt"].str.isEmpty { Text("Обновлено " + dt(c["statusAt"].str)).font(Theme.font(11.5)).foregroundStyle(Theme.dim) }
                HStack {
                    Button("Наклейка на посылку") { Task { await printDoc("barcode") } }.disabled(c["number"].str.isEmpty)
                    Spacer()
                    Button("Накладная") { Task { await printDoc("waybill") } }.disabled(c["number"].str.isEmpty)
                }.font(Theme.font(14, .medium))
                if let pdf { ShareLink(item: pdf) { Label("Открыть или распечатать PDF", systemImage: "printer") }.font(Theme.font(14)) }
                Button("Обновить статус") { Task { await simple("cdek-sync", "POST", "Статус обновлён") } }.font(Theme.font(14))
                if waiting { Button("Отменить отправление", role: .destructive) { confirmCancel = true }.font(Theme.font(14)) }
                if waiting { Text("Распечатайте наклейку, приклейте на пакет и сдайте посылку в пункт. После этого покупатель получит трек-номер.").font(Theme.font(12)).foregroundStyle(Theme.muted) }
            }
            ErrorText(text: error)
        }
        .confirmationDialog("Отменить отправление в СДЭК?", isPresented: $confirmCancel, titleVisibility: .visible) { Button("Отменить отправление", role: .destructive) { Task { await simple("cdek", "DELETE", "Отправление отменено") } } }
        .onAppear { prefill() }
        .task { if c.exists && c["status"].str != "DELIVERED" { _ = try? await act(o["id"].str, "cdek-sync"); await admin.load() } }
        Section("Возврат через СДЭК") {
            Text("Покупатель хочет вернуть вещь — отметьте её. Сайт оформит обратную заявку в СДЭК на ваш пункт и пришлёт покупателю номер и инструкцию.").font(Theme.font(12.5)).foregroundStyle(Theme.muted)
            ForEach(o["returns"].array.indices, id: \.self) { i in
                let r = o["returns"].array[i], waiting = ["ACCEPTED", "CREATED", ""].contains(r["status"].str)
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text(r["number"].string ?? "номер присваивается…").font(Theme.font(14, .medium)).textSelection(.enabled); Spacer(); Text(OrderCdekSection.retSt[r["status"].str] ?? (r["statusName"].string ?? "Обновляется")).font(Theme.font(12)) }
                    Text(r["items"].array.map { "\($0["name"].str), \($0["size"].str) × \($0["qty"].int ?? 1)" }.joined(separator: "; ")).font(Theme.font(12.5))
                    Text(((r["cost"].int ?? 0) > 0 ? "Обратная доставка \(Fmt.rub(r["cost"].int ?? 0))" + (r["deducted"].bool ? " · удержана · " : " · удержится при возврате денег · ") : "") + (r["mailedAt"].exists ? "инструкция отправлена покупателю" : "письмо уйдёт, когда СДЭК присвоит номер")).font(Theme.font(11.5)).foregroundStyle(Theme.muted)
                    if waiting { Button("Отменить возврат", role: .destructive) { Task { await simple("return-cancel", "POST", "Возврат отменён", ["uuid": r["uuid"].str]) } }.font(Theme.font(13)) }
                }
            }
            let can = o["items"].array.indices.compactMap { i -> (Int, JSON, Int)? in
                let it = o["items"].array[i]
                let n = (it["qty"].int ?? 1) - (it["refundedQty"].int ?? 0) - o["returns"].array.reduce(0) { $0 + ($1["items"].array.first { $0["idx"].int == i }?["qty"].int ?? 0) }
                return n > 0 ? (i, it, n) : nil
            }
            if !can.isEmpty {
                Button(retOpen ? "Скрыть" : "Оформить возврат через СДЭК") { withAnimation { retOpen.toggle() } }.font(Theme.font(14.5, .medium))
                if retOpen {
                    ForEach(can, id: \.0) { x in
                        Toggle(isOn: Binding(get: { retLines[x.0] != nil }, set: { retLines[x.0] = $0 ? x.2 : nil; retArmed = false })) { Text("\(x.1["name"].str) · \(x.1["size"].str) · \(x.2) шт.").font(Theme.font(13.5)) }.tint(Theme.ink)
                    }
                    Button(retArmed ? "Подтвердить: заявка и письмо покупателю" : "Оформить возврат в СДЭК") {
                        if !retArmed { retArmed = true; return }
                        Task { await simple("return-ship", "POST", "Возврат оформлен, покупателю придут номер и инструкция", ["lines": retLines.map { ["idx": $0.key, "qty": $0.value] }]); retArmed = false; retOpen = false; retLines = [:] }
                    }.font(Theme.font(14.5, .medium)).disabled(retLines.isEmpty)
                }
            }
            if !o["returns"].array.isEmpty { Button("Обновить статус возврата") { Task { await simple("return-sync", "POST", "Статус обновлён") } }.font(Theme.font(13.5)) }
        }
    }
    private func num(_ t: String, _ b: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) { Text(t).font(Theme.font(10.5)).foregroundStyle(Theme.muted); TextField("", text: b).keyboardType(.numberPad).font(Theme.font(14)).padding(.horizontal, 8).frame(height: 36).background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface)) }
    }
    /// Посылка по карточкам товаров (как Pricing.parcelFor): вещи со своим размером — стопкой
    /// (длина и ширина по самой крупной, высоты складываются), без размера — в упаковку из настроек СДЭК
    private func prefill() {
        guard w.isEmpty else { return }
        let cfg = admin.data["settings"]["cdek"]
        var packs = cfg["packs"].array.map { $0.dictAny }
        if packs.isEmpty { packs = [["id": "bag", "name": "Пакет", "length": 30, "width": 25, "height": 5, "weight": 20], ["id": "m", "name": "Коробка M", "length": 40, "width": 30, "height": 10, "weight": 150], ["id": "l", "name": "Коробка L", "length": 50, "width": 40, "height": 20, "weight": 300]] }
        packs.sort { vol(JSON($0)) < vol(JSON($1)) }
        let def = max(50, cfg["pkg"]["weight"].int ?? 1000), defIdx = max(0, packs.firstIndex { ($0["id"] as? String) == cfg["defaultPack"].str } ?? 0)
        var wt = 0, other = 0
        var stack: (l: Int, w: Int, h: Int)? = nil
        for it in o["items"].array {
            let q = max(0, (it["qty"].int ?? 0) - (it["refundedQty"].int ?? 0)); if q == 0 { continue }
            let p = admin.data["products"].array.first { $0["id"].str == it["productId"].str } ?? JSON(nil)
            wt += ((p["weight"].int ?? 0) > 0 ? (p["weight"].int ?? def) : def) * q
            var d = [p["box"]["length"].int ?? 0, p["box"]["width"].int ?? 0, p["box"]["height"].int ?? 0]
            if d.contains(where: { $0 <= 0 }), !p["pack"].str.isEmpty, let raw = packs.first(where: { ($0["id"] as? String) == p["pack"].str }) {
                let pk = JSON(raw)
                d = [pk["length"].int ?? 0, pk["width"].int ?? 0, pk["height"].int ?? 0]
            }
            if d.contains(where: { $0 <= 0 }) { other += q; continue }
            d.sort(by: >)
            if let s = stack { stack = (l: Swift.max(s.l, d[0]), w: Swift.max(s.w, d[1]), h: s.h + d[2] * q) } else { stack = (l: d[0], w: d[1], h: d[2] * q) }
        }
        var L = 0, W = 0, H = 0
        if other > 0 || stack == nil {
            var idx = defIdx; if other >= 3 { idx += 1 }; if other >= 6 { idx += 1 }
            let pk = JSON(packs[min(idx, packs.count - 1)])
            wt += pk["weight"].int ?? 0
            L = pk["length"].int ?? 30; W = pk["width"].int ?? 25; H = pk["height"].int ?? 5
            if let s = stack { L = Swift.max(L, s.l); W = Swift.max(W, s.w); H += s.h }
        } else if let s = stack { L = s.l; W = s.w; H = s.h }
        let lim = { (v: Int) in min(150, Swift.max(1, v)) }
        w = String(min(30000, Swift.max(50, wt))); l = String(lim(L)); wd = String(lim(W)); h = String(lim(H))
    }
    private func vol(_ p: JSON) -> Int { (p["length"].int ?? 1) * (p["width"].int ?? 1) * (p["height"].int ?? 1) }
    private func create() async {
        busy = true; error = nil; defer { busy = false }
        do { _ = try await act(o["id"].str, "cdek", "POST", ["pkg": ["weight": w, "length": l, "width": wd, "height": h]]); await admin.load(); Haptic.success(); Toast.shared.show("Отправление создано в СДЭК") }
        catch { self.error = error.userMessage }
    }
    private func simple(_ path: String, _ method: String, _ ok: String, _ body: [String: Any] = [:]) async {
        error = nil
        do { _ = try await act(o["id"].str, path, method, body); await admin.load(); Toast.shared.show(ok) } catch { self.error = error.userMessage }
    }
    private func printDoc(_ kind: String) async {
        do {
            let d = try await API.shared.raw("GET", "admin/orders/\(o["id"].str)/cdek-print", query: ["kind": kind])
            let u = FileManager.default.temporaryDirectory.appendingPathComponent((kind == "barcode" ? "naklejka-" : "nakladnaya-") + o["number"].str + ".pdf")
            try d.write(to: u); pdf = u
        } catch { self.error = error.userMessage }
    }
}

/// Удаление заказа — для тестовых и ошибочных
/// 1.0.3: окно открывает сам экран заказа (sheet на Section внутри List с первого раза закрывался сам)
struct OrderDeleteSection: View {
    let open: () -> Void
    var body: some View {
        Section {
            Button { Haptic.tap(); open() } label: {
                HStack(spacing: 14) {
                    Image(systemName: "trash").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.danger)
                        .frame(width: 38, height: 38).background(Circle().fill(Theme.danger.opacity(0.1)))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Удалить заказ").font(Theme.font(15.5, .medium)).foregroundStyle(Theme.danger)
                        Text("Для тестовых и ошибочных заказов").font(Theme.font(12.5)).foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.dim)
                }.padding(.vertical, 4).contentShape(Rectangle())
            }.buttonStyle(.plain)
        } header: { Text("Удаление") }
    }
}

/// Окно «Удалить заказ?» (1.0.2): что именно произойдёт, крупная красная кнопка и «Отмена»
struct OrderDeleteSheet: View {
    let o: JSON
    let done: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        let paid = o["payment"]["status"].str == "paid"
        let c = o["customer"], items = o["items"].array
        let qty = items.reduce(0) { $0 + ($1["qty"].int ?? 1) }
        VStack(alignment: .leading, spacing: 18) {
            Capsule().fill(Theme.line).frame(width: 36, height: 5).frame(maxWidth: .infinity).padding(.top, 2)
            HStack(spacing: 14) {
                Image(systemName: "trash").font(.system(size: 20, weight: .medium)).foregroundStyle(Theme.danger)
                    .frame(width: 52, height: 52).background(Circle().fill(Theme.danger.opacity(0.1)))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Удалить заказ № \(o["number"].str)?").font(Theme.font(22, .light))
                    Text([[c["firstName"].str, c["lastName"].str].filter { !$0.isEmpty }.joined(separator: " "), Fmt.rub(o["total"].int ?? 0), "\(qty) \(Fmt.plural(qty, "вещь", "вещи", "вещей"))"].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(Theme.font(13.5)).foregroundStyle(Theme.muted)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                row("shippingbox", "Товар вернётся на склад")
                row("ticket", "Промокод, сертификат и бонусы — как при отмене")
                row("exclamationmark.circle", "Заказ исчезнет из панели и кабинета покупателя. Удаление не отменить", strong: true)
                if paid { row("creditcard", "Заказ оплачен — деньги сами не вернутся. Сначала оформите возврат оплаты", strong: true) }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 20).fill(Theme.surface))
            ErrorText(text: error)
            Spacer(minLength: 0)
            Button { Task { await delete() } } label: {
                HStack(spacing: 8) {
                    if busy { ProgressView().tint(.white) } else { Image(systemName: "trash").font(.system(size: 14, weight: .medium)); Text("Удалить навсегда").font(Theme.font(15, .medium)).kerning(0.6) }
                }.foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 54).background(Capsule().fill(Theme.danger))
            }.buttonStyle(.plain).disabled(busy)
            GhostButton(title: "Отмена") { dismiss() }
        }
        .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 16)
        .interactiveDismissDisabled(busy)
    }
    private func row(_ icon: String, _ text: String, strong: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(strong ? Theme.danger : Theme.muted).frame(width: 18).padding(.top, 1)
            Text(text).font(Theme.font(14)).foregroundStyle(strong ? Theme.text : Theme.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func delete() async {
        busy = true; error = nil
        do {
            _ = try await API.shared.raw("DELETE", "admin/orders/\(o["id"].str)")
            await Admin.shared.load(); Haptic.success(); dismiss(); done()
            Toast.shared.show("Заказ № \(o["number"].str) удалён")
        } catch { self.error = error.userMessage; busy = false; Haptic.error() }
    }
}

// MARK: - Обмен и возвраты: настройки, причины, размеры, все заявки

struct AdminExchange: View {
    @EnvironmentObject private var router: Router
    @ObservedObject private var admin = Admin.shared
    var body: some View {
        let all = admin.data["orders"].array.flatMap { o in o["requests"].array.map { (o, $0) } }.sorted { $0.1["createdAt"].str > $1.1["createdAt"].str }
        var reasons: [String: Int] = [:], sizes: [String: Int] = [:]
        for x in all {
            reasons[x.1["reasonLabel"].str, default: 0] += 1
            if ["small", "big"].contains(x.1["reason"].str) { for l in x.1["lines"].array { sizes["\(l["name"].str), \(l["size"].str) — \(x.1["reasonLabel"].str.lowercased())", default: 0] += l["qty"].int ?? 1 } }
        }
        return SettingsForm(title: "Обмен и возвраты", sub: "Покупатель оформляет обмен размера или возврат сам — в карточке заказа. Если размер не подошёл, ему сначала предлагается обмен: новый размер сразу откладывается.",
            defs: [FDef(k: "enabled", label: "Принимать заявки на обмен и возврат", kind: .bool, hint: "В карточке товара показывается «Не подошёл размер — обменяем», а в заказе — кнопка «Обменять размер или вернуть»"),
                   FDef(k: "days", label: "Сколько дней после получения", kind: .number, hint: "По закону покупатель может вернуть вещь минимум 7 дней после получения"),
                   FDef(k: "free", label: "Обмен размера бесплатный — доставку в обе стороны оплачивает магазин", kind: .bool)],
            getObj: { s in (s["exchange"] as? [String: Any]) ?? ["enabled": true, "days": 14, "free": true] },
            apply: { s, o in let d = (o["days"] as? NSNumber)?.intValue ?? 0; if !(d >= 7 && d <= 60) { return "Срок — от 7 до 60 дней" }; s["exchange"] = o; return nil },
            extra: AnyView(VStack(alignment: .leading, spacing: 14) {
                top("Почему возвращают", reasons, empty: "Заявок пока не было")
                top("Какие размеры не садятся", sizes, empty: "Пока нет данных", note: "Если один размер часто «велик» или «мал» — поправьте мерки и рост/вес в карточке товара")
                VStack(alignment: .leading, spacing: 10) {
                    Text("Заявки").font(Theme.font(18, .light))
                    if all.isEmpty { Text("Заявок пока не было").font(Theme.font(13.5)).foregroundStyle(Theme.muted) }
                    ForEach(all.indices, id: \.self) { i in
                        let o = all[i].0, r = all[i].1
                        Button { router.push(.adminOrder(o["id"].str), on: .account) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack { Text("№ \(o["number"].str) · \(o["customer"]["firstName"].str) \(o["customer"]["lastName"].str)").font(Theme.font(14, .medium)); Spacer(); Text(OrderRequestsSection.state[r["status"].str] ?? "").font(Theme.font(12)).foregroundStyle(Theme.accent) }
                                Text((r["kind"].str == "exchange" ? "Обмен: " : "Возврат: ") + OrderRequestsSection.what(r)).font(Theme.font(13)).foregroundStyle(Theme.text).multilineTextAlignment(.leading)
                                Text(dt(r["createdAt"].str) + " · " + r["reasonLabel"].str).font(Theme.font(12)).foregroundStyle(Theme.muted)
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
                        }.buttonStyle(.plain)
                    }
                }.padding(16).softCard(20)
            }))
    }
    private func top(_ t: String, _ d: [String: Int], empty: String, note: String = "") -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(t).font(Theme.font(18, .light))
            if d.isEmpty { Text(empty).font(Theme.font(13.5)).foregroundStyle(Theme.muted) }
            ForEach(d.sorted { $0.value > $1.value }.prefix(6), id: \.key) { k in HStack { Text(k.key).font(Theme.font(13.5)); Spacer(); Text("\(k.value)").font(Theme.font(14, .medium)) } }
            if !note.isEmpty && !d.isEmpty { Text(note).font(Theme.font(12)).foregroundStyle(Theme.muted) }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).softCard(20)
    }
}
