import SwiftUI

// «Оплата и доставка» как на сайте (paymentSettings в public/js/admin.js): способы оплаты, ЮKassa, чеки, способы доставки,
// ключи СДЭК и отправка заказов в СДЭК. Ключи хранятся только на сервере — их вводит владелец, приложение их не показывает.
struct AdminPayment: View {
    @ObservedObject private var admin = Admin.shared
    @EnvironmentObject private var shop: Shop
    @State private var p: [String: Any] = [:]
    @State private var yk: [String: Any] = [:]
    @State private var methods: [[String: Any]] = []
    /// Стабильные ключи способов доставки (Q-2): номер способа меняется при перестановке и удалении
    @State private var methodKeys = RowKeys()
    @State private var loaded = false
    @State private var busy = false
    @State private var error: String?
    @State private var secret = ""
    @State private var secState: (String, Bool)?
    @State private var secError: String?
    @State private var cdekId = ""
    @State private var cdekSecret = ""
    @State private var cdekTest = false
    @State private var cdekState: (String, Bool?)?
    @State private var addKind = false
    private static let tax = [(1, "ОСН — общая система"), (2, "УСН «Доходы»"), (3, "УСН «Доходы минус расходы»"), (5, "ЕСХН"), (6, "Патентная система")]
    private static let vat = [(1, "Без НДС"), (2, "НДС 0%"), (7, "НДС 5%"), (8, "НДС 7%"), (3, "НДС 10%"), (4, "НДС 20% (до 2026)"), (11, "НДС 22%")]

    var body: some View {
        AdminPage(title: "Оплата и доставка", sub: "Как покупатель платит и как получает заказ. Всё, что меняете здесь, сразу видно при оформлении заказа.", busy: busy, error: error, onSave: { Task { await save() } }) {
            sec("Способы оплаты", "Включите хотя бы один. Название — то, что покупатель увидит при оформлении.")
            payCard(icon: "payment", title: "Онлайн", sub: "Картой, СБП, SberPay, T-Pay через ЮKassa", on: pb("online"), label: ps("onlineLabel"), placeholder: "Картой или СБП онлайн",
                    state: shop.payReady ? "ЮKassa подключена — оплата работает" : "Не работает, пока не подключена ЮKassa (ниже)", ok: shop.payReady)
            payCard(icon: "cash", title: "При получении", sub: "Наличными или картой в пункте выдачи СДЭК", on: pb("cod"), label: ps("codLabel"), placeholder: "При получении",
                    state: shop.cdekReady ? "Покупатель видит только пункты СДЭК, где принимают оплату. СДЭК возьмёт сумму заказа и доставки и переведёт вам за вычетом комиссии; после вручения заказ отметится оплаченным" : "Заказ приходит неоплаченным, оплату отмечаете в заказе", ok: nil)

            sec("ЮKassa", "Приём онлайн-платежей. Данные — в личном кабинете ЮKassa: «Интеграция» → «Ключи API».")
            VStack(alignment: .leading, spacing: 14) {
                Segmented(items: [("yookassa", "ЮKassa — настоящие платежи"), ("demo", "Выключено")], value: Binding(get: { p["provider"] as? String == "yookassa" ? "yookassa" : "demo" }, set: { p["provider"] = $0 }))
                Field(label: "shopId магазина", text: Binding(get: { yk["shopId"].map { "\($0)" } ?? "" }, set: { yk["shopId"] = $0 }), placeholder: "Например, 1504706", keyboard: .numberPad)
                Field(label: "Секретный ключ", text: $secret, placeholder: "Вставьте live_… или test_…", secure: true, capitalization: .never)
                HStack {
                    GhostButton(title: "Сохранить ключ", height: 44) { Task { await saveSecret() } }.disabled(secret.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let e = secError { ErrorRetry(text: "Не удалось узнать, сохранён ли ключ. " + e) { Task { await loadSecret() } } }
                else if let s = secState { stateLine(s.0, s.1) }
            }.padding(16).softCard(20)

            sec("Чеки по 54-ФЗ", "ЮKassa отправит чек в налоговую и покупателю на почту. Нужна «Чеки от ЮKassa» или своя онлайн-касса.")
            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: Binding(get: { JSON(yk["sendReceipt"]).bool }, set: { yk["sendReceipt"] = $0 })) {
                    VStack(alignment: .leading, spacing: 2) { Text("Передавать данные для чека").font(Theme.font(15, .medium)); Text("Состав заказа и доставка уходят в чек отдельными строками").font(Theme.font(12.5)).foregroundStyle(Theme.muted) }
                }.tint(Theme.ink)
                menuPick("Система налогообложения", AdminPayment.tax, Binding(get: { JSON(yk["taxSystem"]).int ?? 2 }, set: { yk["taxSystem"] = $0 }))
                menuPick("Ставка НДС в чеке", AdminPayment.vat, Binding(get: { JSON(yk["vatCode"]).int ?? 1 }, set: { yk["vatCode"] = $0 }))
                Text("На УСН и патенте обычно «Без НДС»").font(Theme.font(12)).foregroundStyle(Theme.muted)
            }.padding(16).softCard(20)

            sec("Способы доставки", "Порядок здесь = порядок при оформлении. Первый способ выбран у покупателя по умолчанию.")
            let ids = methodKeys.displayKeys(count: methods.count)
            ForEach(Array(ids.enumerated()), id: \.element) { i, id in
                DeliveryCard(m: Binding(get: { methodKeys.row(id, in: methods) ?? [:] }, set: { v in methodKeys.update(id, in: &methods) { $0 = v } }), first: i == 0, last: i == ids.count - 1,
                             move: { d in withAnimation { methodKeys.move(id, by: d, in: &methods) } }, remove: { withAnimation { methodKeys.remove(id, from: &methods) } })
            }
            FlowRow(spacing: 8) {
                Chip(title: "+ Доставка с адресом", on: false, out: true) { add("courier") }
                Chip(title: "+ Курьер СДЭК", on: false, out: true) { add("door") }
                Chip(title: "+ Самовывоз", on: false, out: true) { add("pickup") }
            }

            sec("СДЭК: выбор пункта выдачи", "Покупатель вводит город — приложение подсказывает населённые пункты с областью и показывает только пункты СДЭК в выбранном месте. Ключи — в личном кабинете СДЭК: «Интеграция» → «Ключи API».")
            VStack(alignment: .leading, spacing: 14) {
                Field(label: "Account (идентификатор)", text: $cdekId, capitalization: .never)
                Field(label: "Secure password (секретный ключ)", text: $cdekSecret, placeholder: "Вставьте ключ", secure: true, capitalization: .never)
                Toggle("Тестовая среда СДЭК (только для проверки, данные учебные)", isOn: $cdekTest).font(Theme.font(14)).tint(Theme.ink)
                GhostButton(title: "Сохранить и проверить", height: 44) { Task { await saveCdek() } }
                stateLine(cdekState?.0 ?? (shop.cdekReady ? "Ключи сохранены — подбор пунктов работает" : "Не подключено — покупатели вводят адрес пункта вручную"), cdekState == nil ? shop.cdekReady : cdekState!.1)
            }.padding(16).softCard(20)
            CdekShipCard()
        }
        .task {
            if !admin.data.exists { await admin.load() }
            guard !loaded else { return }
            let s = admin.data["settings"]
            p = s["payment"].dictAny; yk = s["payment"]["yookassa"].dictAny
            methods = s["delivery"]["methods"].array.map(\.dictAny)
            methodKeys.match(count: methods.count)   // список способов задаётся только здесь — ключи сразу под него
            cdekId = s["cdek"]["clientId"].str; cdekTest = s["cdek"]["test"].bool
            loaded = true
            await loadSecret()
        }
    }

    // MARK: Детали
    private func sec(_ t: String, _ s: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(t).font(Theme.font(20, .medium)); Text(s).font(Theme.font(13)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true) }.padding(.top, 8)
    }
    private func stateLine(_ t: String, _ ok: Bool?) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(ok == nil ? Theme.dim : ok! ? Theme.ok : Theme.warn).frame(width: 7, height: 7).padding(.top, 5)
            Text(t).font(Theme.font(12.5)).foregroundStyle(ok == false ? Theme.warn : Theme.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func pb(_ k: String) -> Binding<Bool> { Binding(get: { JSON(p[k]).bool }, set: { p[k] = $0 }) }
    private func ps(_ k: String) -> Binding<String> { Binding(get: { p[k] as? String ?? "" }, set: { p[k] = $0 }) }
    private func payCard(icon: String, title: String, sub: String, on: Binding<Bool>, label: Binding<String>, placeholder: String, state: String, ok: Bool?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                RemoteImage(path: "img/benefits/\(icon).webp", contentMode: .fit).frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) { Text(title).font(Theme.font(16, .medium)); Text(sub).font(Theme.font(12.5)).foregroundStyle(Theme.muted) }
                Spacer()
                Toggle("", isOn: on).labelsHidden().tint(Theme.ink)
            }
            Field(label: "Название на сайте", text: label, placeholder: placeholder)
            stateLine(state, ok)
        }
        .padding(16).softCard(20)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(on.wrappedValue ? Theme.accent : .clear, lineWidth: 1.2))
    }
    private func menuPick(_ title: String, _ opts: [(Int, String)], _ v: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Theme.font(14)).foregroundStyle(Theme.muted)
            Picker(title, selection: v) { ForEach(opts, id: \.0) { Text($0.1).tag($0.0) } }.pickerStyle(.menu).tint(Theme.ink)
        }
    }
    private func add(_ kind: String) {
        var m: [String: Any]
        switch kind {
        case "pickup": m = ["name": "Самовывоз", "desc": "", "price": 0, "freeFrom": 0, "needsAddress": false]
        case "door": m = ["name": "Курьером СДЭК", "desc": "До двери по всей России", "price": 600, "freeFrom": 0, "needsAddress": true, "cdekDoor": true, "pickupPoint": false, "priceAuto": true, "markup": 0]
        default: m = ["name": "", "desc": "", "price": 0, "freeFrom": 0, "needsAddress": true, "pickupPoint": false]
        }
        m["id"] = uid("d"); withAnimation { methodKeys.append(m, to: &methods) }
    }
    /// Состояние ключа ЮKassa (без тела запрос ключ не меняет). Раньше сбой молча убирал строку состояния (аудит Q-B1)
    private func loadSecret() async {
        do { showSecret(try await AdminAPI.post("payment-secret")) } catch { secError = error.userMessage }
    }
    private func showSecret(_ r: JSON) {
        secError = nil
        let mask = r["mask"].str
        if !r["hasSecret"].bool { secState = ("Ключ не задан — онлайн-оплата не работает", false) }
        else if mask.hasPrefix("test_") { secState = ("Сохранён тестовый ключ (\(mask)) — деньги не списываются", false) }
        else { secState = ("Сохранён боевой ключ (\(mask))", true) }
    }
    private func saveSecret() async {
        do { showSecret(try await AdminAPI.post("payment-secret", ["secret": secret.trimmingCharacters(in: .whitespaces)])); secret = ""; Toast.shared.show("Ключ сохранён"); await shop.refreshUser() }
        catch { Toast.shared.show(error.userMessage) }
    }
    private func saveCdek() async {
        cdekState = ("Проверяем ключи в СДЭК…", nil)
        do {
            let r = try await AdminAPI.post("cdek", ["clientId": cdekId, "secret": cdekSecret, "test": cdekTest])
            cdekSecret = ""
            let c = r["settings"]["cdek"]
            cdekState = r["checked"].bool ? ("Подключено" + (c["test"].bool ? " (тестовая среда)" : "") + " — покупатели выбирают пункт из списка", true)
                : (r["error"].string ?? (!r["hasSecret"].bool ? "Введите Secure password" : "Не удалось проверить ключи"), false)
            await AdminAPI.reload()
        } catch { cdekState = (error.userMessage ?? "", false) }
    }
    private func save() async {
        error = nil
        let online = JSON(p["online"]).bool, cod = JSON(p["cod"]).bool
        if !online && !cod { error = "Включите хотя бы один способ оплаты"; return }
        let ms = methods.map(DeliveryCard.clean)
        if ms.isEmpty { error = "Добавьте хотя бы один способ доставки"; return }
        if ms.contains(where: { ($0["name"] as? String ?? "").isEmpty }) { error = "У каждого способа доставки должно быть название"; return }
        busy = true; defer { busy = false }
        var s = admin.data["settings"].dictAny
        let trim = { (k: String, d: String) -> String in let t = (p[k] as? String ?? "").trimmingCharacters(in: .whitespaces); return t.isEmpty ? d : t }
        s["payment"] = ["provider": p["provider"] as? String == "yookassa" ? "yookassa" : "demo", "online": online, "cod": cod,
                        "onlineLabel": trim("onlineLabel", "Картой или СБП онлайн"), "codLabel": trim("codLabel", "При получении"),
                        "yookassa": ["shopId": (yk["shopId"].map { "\($0)" } ?? "").trimmingCharacters(in: .whitespaces), "sendReceipt": JSON(yk["sendReceipt"]).bool,
                                     "taxSystem": JSON(yk["taxSystem"]).int ?? 2, "vatCode": JSON(yk["vatCode"]).int ?? 1]] as [String: Any]
        var d = s["delivery"] as? [String: Any] ?? [:]; d["methods"] = ms; s["delivery"] = d
        do { try await AdminAPI.saveSettings(s); await AdminAPI.reload(); Haptic.success(); Toast.shared.show("Сохранено") } catch { self.error = error.userMessage }
    }
}

/// Карточка способа доставки: название, срок, цена, «бесплатно от», адрес, режим СДЭК, цена по тарифу и наценка, превью для покупателя
private struct DeliveryCard: View {
    @Binding var m: [String: Any]
    let first: Bool, last: Bool
    let move: (Int) -> Void
    let remove: () -> Void
    @State private var askDel = false
    private var needs: Bool { !(m["needsAddress"] is Bool) || m["needsAddress"] as? Bool == true }
    private var mode: String { needs ? (JSON(m["cdekDoor"]).bool ? "door" : JSON(m["pickupPoint"]).bool ? "pvz" : "") : "" }
    /// Как readDelivery на сайте: числа не меньше нуля, режим СДЭК только со спросом адреса
    static func clean(_ m: [String: Any]) -> [String: Any] {
        let j = JSON(m), needs = !(m["needsAddress"] is Bool) || j["needsAddress"].bool
        let num = { (k: String) in max(0, j[k].double ?? Double(j[k].str) ?? 0) }
        let pvz = needs && j["pickupPoint"].bool, door = needs && j["cdekDoor"].bool
        return ["id": j["id"].str, "name": j["name"].str.trimmingCharacters(in: .whitespaces), "desc": j["desc"].str.trimmingCharacters(in: .whitespaces),
                "price": Int(num("price")), "freeFrom": Int(num("freeFrom")), "needsAddress": needs, "pickupPoint": pvz, "cdekDoor": door,
                "priceAuto": needs && (pvz || door) && j["priceAuto"].bool, "markup": Int(num("markup"))]
    }
    private var summary: String {
        let j = JSON(m), price = j["price"].int ?? 0, free = j["freeFrom"].int ?? 0
        if j["priceAuto"].bool && !mode.isEmpty { return "по тарифу СДЭК" + ((j["markup"].int ?? 0) > 0 ? " + " + Fmt.rub(j["markup"].int ?? 0) : "") + (free > 0 ? ", бесплатно от " + Fmt.rub(free) : "") }
        if price == 0 { return "Бесплатно" }
        return Fmt.rub(price) + (free > 0 ? ", бесплатно от " + Fmt.rub(free) : "")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                RemoteImage(path: "img/benefits/\(needs ? "delivery" : "pin").webp", contentMode: .fit).frame(width: 40, height: 40)
                Spacer()
                tool("arrow.up", !first) { move(-1) }
                tool("arrow.down", !last) { move(1) }
                tool("xmark", true) { askDel = true }
            }
            Field(label: "Название", text: str("name"), placeholder: "Например, Курьер по Москве")
            Field(label: "Срок или пояснение", text: str("desc"), placeholder: "Например, 1–2 дня, с примеркой")
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) { Field(label: "Стоимость, ₽", text: num("price"), keyboard: .numberPad); Text("0 — бесплатно всегда").font(Theme.font(11.5)).foregroundStyle(Theme.dim) }
                VStack(alignment: .leading, spacing: 4) { Field(label: "Бесплатно от, ₽", text: num("freeFrom"), keyboard: .numberPad); Text("0 — не делать бесплатной").font(Theme.font(11.5)).foregroundStyle(Theme.dim) }
            }
            Toggle(isOn: Binding(get: { needs }, set: { m["needsAddress"] = $0 })) {
                VStack(alignment: .leading, spacing: 2) { Text("Адрес покупателя").font(Theme.font(13)).foregroundStyle(Theme.muted); Text(needs ? "Спросить город и адрес" : "Не нужен — самовывоз").font(Theme.font(15, .medium)) }
            }.tint(Theme.ink)
            if needs {
                VStack(alignment: .leading, spacing: 6) {
                    Text("СДЭК").font(Theme.font(14, .medium))
                    Text("Город покупатель выбирает из подсказок СДЭК — с областью, без ошибок").font(Theme.font(12)).foregroundStyle(Theme.muted)
                    Picker("Режим СДЭК", selection: Binding(get: { mode }, set: { v in m["pickupPoint"] = v == "pvz"; m["cdekDoor"] = v == "door" })) {
                        Text("Не СДЭК, адрес вручную").tag(""); Text("Пункт выдачи из списка").tag("pvz"); Text("Курьер до двери").tag("door")
                    }.pickerStyle(.menu).tint(Theme.ink)
                }
                if !mode.isEmpty {
                    Toggle(isOn: Binding(get: { JSON(m["priceAuto"]).bool }, set: { m["priceAuto"] = $0 })) {
                        VStack(alignment: .leading, spacing: 2) { Text("Цена по тарифу СДЭК").font(Theme.font(15, .medium)); Text("Стоимость считается по городу покупателя из вашего пункта отгрузки. «Стоимость» выше — запасная, если СДЭК не ответил").font(Theme.font(12)).foregroundStyle(Theme.muted) }
                    }.tint(Theme.ink)
                    VStack(alignment: .leading, spacing: 4) { Field(label: "Наценка к тарифу, ₽", text: num("markup"), keyboard: .numberPad); Text("Например, на упаковку. Итог округляется до 10 ₽").font(Theme.font(11.5)).foregroundStyle(Theme.dim) }
                }
            }
            (Text("Покупатель увидит: ") + Text(str("name").wrappedValue.isEmpty ? "Без названия" : str("name").wrappedValue).bold() + Text(str("desc").wrappedValue.isEmpty ? "" : " · " + str("desc").wrappedValue) + Text(" — " + summary))
                .font(Theme.font(13)).foregroundStyle(Theme.muted).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
        }
        .padding(16).softCard(20)
        .confirmationDialog("Удалить способ доставки?", isPresented: $askDel, titleVisibility: .visible) { Button("Удалить", role: .destructive, action: remove) }
    }
    private func str(_ k: String) -> Binding<String> { Binding(get: { m[k] as? String ?? "" }, set: { m[k] = $0 }) }
    private func num(_ k: String) -> Binding<String> { Binding(get: { JSON(m[k]).int.map(String.init) ?? "0" }, set: { m[k] = Int($0.filter(\.isNumber)) ?? 0 }) }
    private func tool(_ i: String, _ on: Bool, _ a: @escaping () -> Void) -> some View {
        Button(action: a) { Image(systemName: i).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.text).frame(width: 30, height: 30).background(Circle().fill(Theme.surface)) }
            .buttonStyle(.plain).opacity(on ? 1 : 0.3).disabled(!on)
    }
}

/// Отправка заказов в СДЭК: пункт отгрузки, тарифы, упаковки, вес по умолчанию, получатель возвратов, услуги
private struct CdekShipCard: View {
    @ObservedObject private var admin = Admin.shared
    @State private var point: [String: Any]?
    @State private var tariff = 136
    @State private var tariffDoor = 137
    @State private var packs: [[String: Any]] = []
    /// Стабильные ключи упаковок (аудит IOS-05): номер упаковки меняется при удалении
    @State private var packKeys = RowKeys()
    @State private var defPack = ""
    @State private var weight = "1000"
    @State private var retName = ""
    @State private var retPhone = ""
    @State private var part = false
    @State private var tryOn = false
    @State private var loaded = false
    @State private var cityPick = false
    @State private var city: CdekCity?
    @State private var state: (String, Bool)?
    private static let defPacks: [[String: Any]] = [["id": "bag", "name": "Пакет", "length": 30, "width": 25, "height": 5, "weight": 20],
                                                     ["id": "m", "name": "Коробка M", "length": 40, "width": 30, "height": 10, "weight": 150],
                                                     ["id": "l", "name": "Коробка L", "length": 50, "width": 40, "height": 20, "weight": 300]]
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Отправка заказов в СДЭК").font(Theme.font(16, .medium))
                Text("В заказе появится кнопка «Создать отправление в СДЭК»: заявка, трек-номер покупателю и наклейка на посылку — без личного кабинета СДЭК").font(Theme.font(12.5)).foregroundStyle(Theme.muted)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Пункт СДЭК, куда вы сдаёте посылки").font(Theme.font(14)).foregroundStyle(Theme.muted)
                if let pt = point {
                    HStack(alignment: .top) {
                        Image(systemName: "mappin.circle.fill").foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 2) { Text(pt["address"] as? String ?? "").font(Theme.font(14.5, .medium)); Text("\(pt["city"] as? String ?? "") · код \(pt["code"] as? String ?? "")").font(Theme.font(12)).foregroundStyle(Theme.muted) }
                        Spacer(); Button("Изменить") { cityPick = true }.font(Theme.font(13))
                    }
                } else { GhostButton(title: "Выбрать пункт отгрузки", icon: "mappin", height: 44) { cityPick = true } }
            }
            pick("Тариф", [(136, "Посылка склад–склад"), (234, "Экономичная посылка склад–склад")], $tariff, "В постаматы — тариф «склад–постамат», подставится сам")
            pick("Тариф для курьера", [(137, "Посылка склад–дверь"), (233, "Экономичная посылка склад–дверь")], $tariffDoor, "Вы сдаёте посылку в пункт, курьер везёт до двери")
            VStack(alignment: .leading, spacing: 8) {
                Text("Упаковки").font(Theme.font(14)).foregroundStyle(Theme.muted)
                Text("Размер и вес самой упаковки. В карточке товара выбираете, в какую упаковку он кладётся; посылка берётся по самой крупной вещи, а от 3 вещей — на размер больше").font(Theme.font(12)).foregroundStyle(Theme.dim)
                ForEach(packKeys.displayKeys(count: packs.count), id: \.self) { id in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { TextField("Название", text: pstr(id, "name")).font(Theme.font(14.5, .medium)); Button { packKeys.remove(id, from: &packs) } label: { Image(systemName: "xmark").font(.system(size: 11)) }.foregroundStyle(Theme.muted) }
                        HStack(spacing: 6) { pnum(id, "length", "см"); Text("×"); pnum(id, "width", "см"); Text("×"); pnum(id, "height", "см"); pnum(id, "weight", "г") }.font(Theme.font(13))
                    }.padding(10).background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
                }
                Button("+ Добавить упаковку") { packKeys.append(Self.newPack(), to: &packs) }.font(Theme.font(13))
            }
            Field(label: "Вес вещи, если в карточке не указан, г", text: $weight, keyboard: .numberPad)
            VStack(alignment: .leading, spacing: 6) {
                Text("Упаковка, если в карточке не выбрана").font(Theme.font(14)).foregroundStyle(Theme.muted)
                Picker("Упаковка", selection: $defPack) { ForEach(packs.indices, id: \.self) { i in Text(packs[i]["name"] as? String ?? "").tag(packs[i]["id"] as? String ?? "") } }.pickerStyle(.menu).tint(Theme.ink)
            }
            Field(label: "Возвраты получает (имя или ИП)", text: $retName, placeholder: "ИП Фамилия Имя Отчество")
            VStack(alignment: .leading, spacing: 4) { Field(label: "Телефон для возвратов", text: $retPhone, placeholder: "+7 (___) ___-__-__", keyboard: .phonePad); Text("СДЭК позвонит, когда возврат придёт в ваш пункт").font(Theme.font(11.5)).foregroundStyle(Theme.dim) }
            Text("Услуги для покупателя (включите, если они есть в вашем договоре со СДЭК)").font(Theme.font(13)).foregroundStyle(Theme.muted)
            Toggle(isOn: $part) { VStack(alignment: .leading, spacing: 2) { Text("Частичный выкуп").font(Theme.font(14.5, .medium)); Text("Покупатель забирает только то, что подошло, остальное СДЭК везёт вам обратно").font(Theme.font(12)).foregroundStyle(Theme.muted) } }.tint(Theme.ink)
            Toggle(isOn: $tryOn) { VStack(alignment: .leading, spacing: 2) { Text("Примерка").font(Theme.font(14.5, .medium)); Text("Покупатель может примерить вещи при получении").font(Theme.font(12)).foregroundStyle(Theme.muted) } }.tint(Theme.ink)
            GhostButton(title: "Сохранить настройки отправки", height: 44) { Task { await save() } }
            if let s = state { Text(s.0).font(Theme.font(12.5)).foregroundStyle(s.1 ? Theme.ok : Theme.warn) }
        }
        .padding(16).softCard(20)
        .onAppear {
            guard !loaded else { return }
            let c = admin.data["settings"]["cdek"]
            point = c["shipmentPoint"].exists ? c["shipmentPoint"].dictAny : nil
            tariff = c["tariff"].int ?? 136; tariffDoor = c["tariffDoor"].int ?? 137
            let list = c["packs"].array.map(\.dictAny)
            packs = (list.isEmpty ? CdekShipCard.defPacks : list).sorted { vol($0) < vol($1) }
            packKeys.match(count: packs.count)   // список упаковок задаётся только здесь — ключи сразу под него
            defPack = c["defaultPack"].string ?? (packs.first?["id"] as? String ?? "")
            weight = String(c["pkg"]["weight"].int ?? 1000)
            retName = c["returnTo"]["name"].str; retPhone = c["returnTo"]["phone"].str.isEmpty ? "" : Fmt.phone(c["returnTo"]["phone"].str)
            part = c["services"]["partDeliv"].bool; tryOn = c["services"]["tryOn"].bool
            loaded = true
        }
        .sheet(isPresented: $cityPick) { CityPicker { c in cityPick = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { city = c } } }
        .sheet(item: $city) { c in
            PointPicker(city: c, cod: false) { pt in
                if pt.type == "postamat" { Toast.shared.show("Выберите пункт выдачи — в постамат посылку не сдать"); return }
                point = ["code": pt.code, "address": pt.address, "city": c.title, "cityCode": c.code]; city = nil
            }
        }
    }
    private static func newPack() -> [String: Any] {
        ["id": "pk" + String(Int(Date().timeIntervalSince1970 * 1000), radix: 36), "name": "", "length": 30, "width": 20, "height": 10, "weight": 50]
    }
    private func vol(_ x: [String: Any]) -> Int { let j = JSON(x); return (j["length"].int ?? 0) * (j["width"].int ?? 0) * (j["height"].int ?? 0) }
    /// Поле упаковки: читается и пишется по ключу упаковки. Упаковку уже удалили — поле пустое, запись не выполняется
    private func pstr(_ id: UUID, _ k: String) -> Binding<String> {
        Binding(get: { packKeys.row(id, in: packs)?[k] as? String ?? "" }, set: { v in setPack(id, k, v) })
    }
    private func setPack(_ id: UUID, _ k: String, _ v: Any) { var p = packs; if packKeys.update(id, in: &p, { $0[k] = v }) { packs = p } }
    private func pnum(_ id: UUID, _ k: String, _ unit: String) -> some View {
        HStack(spacing: 2) {
            TextField("0", text: Binding(get: { JSON(packKeys.row(id, in: packs)?[k]).int.map(String.init) ?? "" }, set: { setPack(id, k, Int($0.filter(\.isNumber)) ?? 0) })).keyboardType(.numberPad).frame(width: 40)
            Text(unit).foregroundStyle(Theme.dim)
        }
    }
    private func pick(_ t: String, _ opts: [(Int, String)], _ v: Binding<Int>, _ hint: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(t).font(Theme.font(14)).foregroundStyle(Theme.muted)
            Picker(t, selection: v) { ForEach(opts, id: \.0) { Text($0.1).tag($0.0) } }.pickerStyle(.menu).tint(Theme.ink)
            Text(hint).font(Theme.font(11.5)).foregroundStyle(Theme.dim)
        }
    }
    private func save() async {
        if packs.isEmpty { state = ("Нужна хотя бы одна упаковка", false); return }
        let ps = packs.map { x -> [String: Any] in var y = x; if (y["name"] as? String ?? "").trimmingCharacters(in: .whitespaces).isEmpty { y["name"] = "Упаковка" }; return y }
        var req: [String: Any] = ["check": false, "tariff": tariff, "tariffDoor": tariffDoor, "packs": ps, "defaultPack": defPack,
                                   "pkg": ["weight": weight, "length": 30, "width": 25, "height": 10], "services": ["partDeliv": part, "tryOn": tryOn], "returnTo": ["name": retName, "phone": retPhone]]
        req["shipmentPoint"] = point.map { $0 as Any } ?? NSNull()
        do {
            _ = try await AdminAPI.post("cdek", req); await Admin.shared.load()
            state = point != nil ? ("Сохранено", true) : ("Сохранено. Укажите пункт отгрузки — без него отправление не создать", false)
        } catch { state = (error.userMessage ?? "", false) }
    }
}
