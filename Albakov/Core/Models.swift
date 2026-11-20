import Foundation

// Данные магазина — те же, что получает сайт (GET /api/state). Разбираем бережно: нет поля — значение по умолчанию.

struct SizeStock: Hashable {
    let size: String
    let stock: Int
    init(_ j: JSON) { size = j["size"].str; stock = j["stock"].int ?? 0 }
}

struct PColor: Identifiable, Hashable {
    let id: String
    let name: String
    let hex: String
    let images: [String]
    let sizes: [SizeStock]
    let artKind: String, artTone: String
    init(_ j: JSON) {
        id = j["id"].str; name = j["name"].str; hex = j["hex"].str
        artKind = j["art"]["kind"].string ?? "tee"; artTone = j["art"]["tone"].string ?? (j["hex"].string ?? "#3a3632")
        images = j["images"].array.compactMap { $0.string }.filter { !$0.hasPrefix("data:") }
        sizes = j["sizes"].array.map(SizeStock.init)
    }
    var stock: Int { sizes.reduce(0) { $0 + $1.stock } }
}

struct Product: Identifiable, Hashable {
    let id: String, slug: String, name: String, categoryId: String, gender: String
    let price: Int, compareAt: Int
    let tags: [String]
    let colors: [PColor]
    let description: String, composition: String, care: String
    let fit: JSON, specs: JSON, look: [String]
    let active: Bool
    let createdAt: String
    let sku: String
    let preorder: Bool, preorderLimit: Int, preorderSold: Int, preorderText: String, preorderShip: String
    let badgeText: [String: String], badgeOff: [String]
    let raw: JSON

    init(_ j: JSON) {
        raw = j
        id = j["id"].str; slug = j["slug"].string ?? j["id"].str; name = j["name"].str
        categoryId = j["categoryId"].str; gender = j["gender"].str
        price = j["price"].int ?? 0; compareAt = j["compareAt"].int ?? 0
        tags = j["tags"].array.compactMap { $0.string }
        var cs = j["colors"].array.map(PColor.init)
        if cs.isEmpty {   // старый товар без цветов
            let old: [String: Any] = ["id": "col1", "art": j["art"].raw ?? [String: Any](), "name": j["color"].string ?? "Основной", "images": j["images"].raw ?? [Any](), "sizes": j["sizes"].raw ?? [Any]()]
            cs = [PColor(JSON(old))]
        }
        colors = cs
        description = j["description"].str; composition = j["composition"].str; care = j["care"].str; fit = j["fit"]; specs = j["specs"]; look = j["look"].array.compactMap { $0.string }
        active = j["active"].exists ? j["active"].bool : true
        createdAt = j["createdAt"].str; sku = j["sku"].str
        preorder = j["preorder"].bool; preorderLimit = j["preorderLimit"].int ?? 0; preorderSold = j["preorderSold"].int ?? 0
        preorderText = j["preorderText"].str; preorderShip = j["preorderShip"].str
        badgeText = j["badgeText"].dict.compactMapValues { $0.string }
        badgeOff = j["badgeOff"].array.compactMap { $0.string }
    }
    /// Равны — тот же товар с теми же данными с сервера (DEF-3, этап I). Раньше — по одному id: экраны, получившие товар
    /// свойством (ProductCard и др.), SwiftUI считал неизменными и после обновления витрины показывал прежние цену и остатки.
    /// Все поля товара — из raw, поэтому сравнивается он. Хеш — по id: равные товары по-прежнему с одинаковым хешем
    static func == (a: Product, b: Product) -> Bool { a.id == b.id && (a.raw.raw as? NSObject)?.isEqual(b.raw.raw) ?? (b.raw.raw == nil) }
    func hash(into h: inout Hasher) { h.combine(id) }

    var image: String { colors.first(where: { !$0.images.isEmpty })?.images.first ?? "" }
    func color(_ id: String?) -> PColor { colors.first { $0.id == id } ?? colors[0] }
    var stock: Int { colors.reduce(0) { $0 + $1.stock } }
    var preorderLeft: Int { !preorder ? 0 : preorderLimit > 0 ? max(0, preorderLimit - preorderSold) : Int.max }
    var available: Bool { stock > 0 || preorderLeft > 0 }
    /// «Унисекс» — взрослые разделы: в детском только детские товары (как Pricing.forGender на сайте)
    func forGender(_ g: String?) -> Bool { g == nil || gender == g || (g != "kids" && (gender.isEmpty || gender == "unisex")) }
}

struct Category: Identifiable, Hashable {
    let id: String, name: String, slug: String, image: String, order: Int, gender: String, artKind: String, artTone: String
    init(_ j: JSON) {
        id = j["id"].str; name = j["name"].str; slug = j["slug"].str; image = j["image"].str; order = j["order"].int ?? 0; gender = j["gender"].str
        artKind = j["art"]["kind"].string ?? "tee"; artTone = j["art"]["tone"].string ?? "#3b3b3f"
    }
}

struct Promotion {
    let id: String, title: String, type: String, value: Double, scope: String
    let categoryIds: [String], productIds: [String], startsAt: String, endsAt: String, active: Bool
    init(_ j: JSON) {
        id = j["id"].str; title = j["title"].str; type = j["type"].str; value = j["value"].double ?? 0; scope = j["scope"].str
        categoryIds = j["categoryIds"].array.compactMap { $0.string }; productIds = j["productIds"].array.compactMap { $0.string }
        startsAt = j["startsAt"].str; endsAt = j["endsAt"].str; active = j["active"].bool
    }
    func applies(to p: Product) -> Bool {
        switch scope {
        case "all": return true
        case "categories": return categoryIds.contains(p.categoryId)
        case "products": return productIds.contains(p.id)
        default: return false
        }
    }
    func inWindow(_ now: Date) -> Bool {
        guard active else { return false }
        let f = Promotion.moscow
        if !startsAt.isEmpty, let d = f.date(from: startsAt + " 00:00:00"), now < d { return false }
        if !endsAt.isEmpty, let d = f.date(from: endsAt + " 23:59:59"), now > d { return false }
        return true
    }
    /// Даты акций — по Москве, как на сервере и сайте: цена на карточке совпадает с ценой в корзине в любом поясе (аудит V-3, 16.11).
    /// Один разборщик на все вызовы: inWindow зовётся для каждого товара и каждой акции при каждом расчёте цены —
    /// раньше форматтер создавался на каждый вызов (аудит Q-B6). После создания не меняется; разбор потокобезопасен
    private static let moscow: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "Europe/Moscow") ?? .current
        return f
    }()
}

struct Price { let price: Int; let oldPrice: Int; var promoTitle = ""; var promoEnds = ""; var percent: Int { oldPrice > 0 ? Int((1 - Double(price) / Double(oldPrice)) * 100 + 0.5) : 0 } }

struct Page: Identifiable { let id: String, slug: String, title: String, body: String, group: String, inFooter: Bool
    init(_ j: JSON) { id = j["id"].str; slug = j["slug"].str; title = j["title"].str; body = j["body"].str; group = j["group"].str; inFooter = !j["inFooter"].exists || j["inFooter"].bool }
}

extension Settings {
    /// Подстановки в текстах страниц, как на сайте (fillDoc): {магазин}, {продавец} — реквизиты из панели, {почта}, {телефон}, {адрес}, {сайт}
    func fill(_ text: String) -> String {
        let legal = raw["legal"].str
        let map = ["магазин": storeName, "продавец": legal.isEmpty ? storeName : legal, "почта": email, "телефон": phone, "адрес": address, "сайт": "albakovofficial.ru"]
        var out = text
        for (k, v) in map { out = out.replacingOccurrences(of: "{\(k)}", with: v.isEmpty ? "—" : v) }
        return out
    }
}

struct DeliveryMethod: Identifiable, Hashable {
    let id: String, name: String, desc: String, price: Int, freeFrom: Int, needsAddress: Bool, cdekDoor: Bool, pickupPoint: Bool?, priceAuto: Bool
    init(_ j: JSON) {
        id = j["id"].str; name = j["name"].str; desc = j["desc"].str; price = j["price"].int ?? 0; freeFrom = j["freeFrom"].int ?? 0
        needsAddress = j["needsAddress"].exists ? j["needsAddress"].bool : true; cdekDoor = j["cdekDoor"].bool
        pickupPoint = j["pickupPoint"].exists ? j["pickupPoint"].bool : nil; priceAuto = j["priceAuto"].bool
    }
    // Как на сайте (Pricing.isPvzMethod / isDoorMethod)
    var isPvz: Bool {
        if !needsAddress || cdekDoor { return false }
        if let pp = pickupPoint { return pp }
        let n = name.lowercased(), all = (name + " " + desc).lowercased()
        return (n.contains("сдэк") || n.contains("cdek")) && ["пункт", "пвз", "постамат", "выдач"].contains { all.contains($0) }
    }
    var isDoor: Bool { needsAddress && cdekDoor }
}

struct Slide: Identifiable {
    let id: String, eyebrow: String, title: String, image: String, gender: String
    var text: String, btn1: (String, String), btn2: (String, String)
    let startsAt: String, endsAt: String, promotionId: String, audience: String, code: String
    init(_ j: JSON) {
        id = j["id"].str; eyebrow = j["eyebrow"].str; title = Fmt.plain(j["title"].str); text = j["text"].str; image = j["image"].str; gender = j["gender"].str
        btn1 = (j["btn1"]["label"].str, j["btn1"]["link"].str); btn2 = (j["btn2"]["label"].str, j["btn2"]["link"].str)
        startsAt = j["startsAt"].str; endsAt = j["endsAt"].str; promotionId = j["promotionId"].str; audience = j["audience"].str; code = j["code"].str
    }
    private var toRegister: Bool { (btn1.1 + " " + btn2.1).contains("tab=register") }
    /// Кому показывать (как slideAudience на сайте): «guest» — только без входа, «user» — только вошедшим, «all» — всем.
    /// Не задано: слайд с кнопкой «Регистрация» — новым покупателям («new»): гостям и вошедшим, кто ещё не пользовался скидкой.
    var who: String {
        if ["guest", "user", "all"].contains(audience) { return audience }
        return toRegister ? "new" : "all"
    }
    /// Виден ли слайд сейчас: раздел, срок, связанная акция и кому показывать — как slideVisible на сайте
    func visible(gender g: String?, user: User?, promos: [Promotion], now: Date = Date()) -> Bool {
        if !gender.isEmpty, let g, gender != g { return false }
        let win = Promotion(JSON(["active": true, "startsAt": startsAt, "endsAt": endsAt]))
        if !win.inWindow(now) { return false }
        if !promotionId.isEmpty { guard let p = promos.first(where: { $0.id == promotionId }), p.inWindow(now) else { return false } }
        switch who {
        case "guest": return user == nil
        case "user": return user != nil
        case "new":
            guard let u = user else { return true }
            return !u.hasOrders && (code.isEmpty || !u.usedPromos.contains(code.uppercased()))
        default: return true
        }
    }
    /// Вошедшему слайд с регистрацией — без неё: кнопка «Выбрать вещи», в тексте без «Зарегистрируйтесь» (как slideForUser на сайте)
    func forUser(_ user: User?) -> Slide {
        guard user != nil, toRegister else { return self }
        var x = self
        if btn1.1.contains("tab=register") { x.btn1 = ("Выбрать вещи", "#/catalog") }
        if btn2.1.contains("tab=register") { x.btn2 = ("", "") }
        var t = text
        if let r = t.range(of: #"(?i)зарегистрируйтесь\s*(и\s*)?"#, options: .regularExpression) { t.removeSubrange(r) }
        t = t.trimmingCharacters(in: .whitespaces)
        x.text = t.isEmpty ? "" : t.prefix(1).uppercased() + t.dropFirst()
        return x
    }
}

struct Social: Identifiable, Hashable { let name: String; let url: String; var id: String { url } }

/// Разделы магазина (13.63): женщинам, мужчинам, детям
enum Sections {
    static let all: [(key: String, name: String)] = [("women", "Женщинам"), ("men", "Мужчинам"), ("kids", "Детям")]
    static func name(_ g: String?) -> String { all.first { $0.key == g }?.name ?? "Вся коллекция" }
}

struct Settings {
    let storeName: String, tagline: String
    let phone: String, email: String, hours: String, address: String, appStore: String
    let socials: [Social]
    let delivery: [DeliveryMethod]
    let payOnline: Bool, payCod: Bool, onlineLabel: String, codLabel: String
    let bonusEnabled: Bool, bonusPercent: Int, bonusOnlineExtra: Int
    let slides: [Slide]
    let badges: [String: (text: String, color: String)]
    let gendersOpen: [String: Bool]
    let exchangeDays: Int
    let nav: [(label: String, link: String)]
    let raw: JSON

    init(_ j: JSON) {
        raw = j
        storeName = j["storeName"].string ?? "ALBAKOV"; tagline = j["tagline"].str
        let c = j["contacts"]
        phone = c["phone"].str; email = c["email"].str; hours = c["hours"].str; address = c["address"].str; appStore = c["appStore"].str
        socials = j["socials"].array.map { Social(name: $0["name"].str, url: $0["url"].str) }.filter { $0.url.hasPrefix("http") && URL(string: $0.url) != nil }
        delivery = j["delivery"]["methods"].array.map(DeliveryMethod.init)
        let p = j["payment"]
        payOnline = p["online"].bool; payCod = p["cod"].exists ? p["cod"].bool : true
        onlineLabel = p["onlineLabel"].string ?? "Картой или СБП онлайн"; codLabel = p["codLabel"].string ?? "При получении"
        let b = j["bonus"]
        bonusEnabled = b["enabled"].bool; bonusPercent = b["percent"].int ?? 0; bonusOnlineExtra = b["onlineExtra"].int ?? 0
        let sl = j["slider"]
        slides = sl["enabled"].exists && !sl["enabled"].bool ? [] : sl["slides"].array.filter { !$0["active"].exists || $0["active"].bool }.map(Slide.init)
        var bd: [String: (text: String, color: String)] = [:]
        for (k, v) in j["badges"].dict { bd[k] = (text: v["text"].str, color: v["color"].string ?? "#141414") }
        badges = bd
        var g: [String: Bool] = [:]
        for (k, v) in j["genders"].dict { g[k] = v["open"].exists ? v["open"].bool : true }
        gendersOpen = g
        exchangeDays = j["exchange"]["days"].int ?? 14
        nav = j["nav"].array.map { (label: $0["label"].str, link: $0["link"].str) }.filter { !$0.label.isEmpty && !$0.link.isEmpty && $0.link != "#" }
    }
}

struct User {
    let id: String, firstName: String, lastName: String, phone: String, email: String, bonus: Int, supportUnread: Int, createdAt: String
    let favorites: [String]
    let cart: [CartLine]
    /// Есть ли заказы и какие промокоды уже использованы — для слайда «скидка новым покупателям»
    let hasOrders: Bool, usedPromos: [String]
    init?(_ j: JSON) {
        guard let id = j["id"].string else { return nil }
        hasOrders = j["hasOrders"].bool; usedPromos = j["usedPromos"].array.compactMap { $0.string?.uppercased() }
        self.id = id; firstName = j["firstName"].str; lastName = j["lastName"].str; phone = j["phone"].str; email = j["email"].str
        bonus = j["bonus"].int ?? 0; supportUnread = j["supportUnread"].int ?? 0; createdAt = j["createdAt"].str
        favorites = j["favorites"].array.compactMap { $0.string }
        cart = j["cart"].array.compactMap(CartLine.init)
    }
    var name: String { [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ") }
}

struct CartLine: Codable, Hashable, Identifiable {
    var productId: String, colorId: String, size: String, qty: Int
    var id: String { productId + "|" + colorId + "|" + size }
    init(productId: String, colorId: String, size: String, qty: Int) { self.productId = productId; self.colorId = colorId; self.size = size; self.qty = qty }
    init?(_ j: JSON) { guard let p = j["productId"].string else { return nil }; productId = p; colorId = j["colorId"].str; size = j["size"].str; qty = max(1, j["qty"].int ?? 1) }
    var dict: [String: Any] { ["productId": productId, "colorId": colorId, "size": size, "qty": qty] }
}

// Заказ — как его видит покупатель (и, с заметками и историей, панель)
struct Order: Identifiable, Hashable {
    let id: String, number: String, createdAt: Date?, status: String
    /// "gift" — заказ подарочного сертификата
    let kind: String
    let items: [OrderItem]
    let subtotal: Int, total: Int, saleDiscount: Int, promoDiscount: Int, promoCode: String, bonusUsed: Int, giftUsed: Int, bonusEarn: Int
    let deliveryName: String, deliveryPrice: Int, city: String, address: String
    let payMethod: String, payStatus: String, payUrl: String
    /// Срок оплаты (1.0.3): 15 минут с оформления; вышел — заказ отменён, вещи вернулись в продажу
    let payBy: Date?, payExpired: Bool
    /// Оплата пришла после отмены по времени, а вещи уже купили — деньги вернёт магазин; resumeMissing — что именно купили
    let paidAfterCancel: Bool, resumeMissing: [String]
    let customerName: String, phone: String, email: String, comment: String
    let trackNumber: String, trackURL: String, cdekStatus: String
    let requestOk: Bool, requestWhy: String
    let adminNote: String
    let history: [(at: Date?, text: String)]
    let raw: JSON

    init(_ j: JSON) {
        raw = j
        id = j["id"].str; number = j["number"].str; createdAt = ISO.date(j["createdAt"].str); status = j["status"].str
        items = j["items"].array.map(OrderItem.init)
        subtotal = j["subtotal"].int ?? 0; total = j["total"].int ?? 0; saleDiscount = j["saleDiscount"].int ?? 0; promoDiscount = j["promoDiscount"].int ?? 0
        promoCode = j["promoCode"].str; bonusUsed = j["bonusUsed"].int ?? 0; giftUsed = j["giftUsed"].int ?? 0; bonusEarn = j["bonusEarn"].int ?? 0
        let d = j["delivery"]
        deliveryName = d["name"].str; deliveryPrice = d["price"].int ?? 0; city = d["city"].str; address = d["address"].str
        payMethod = j["payment"]["method"].str; payStatus = j["payment"]["status"].str; payUrl = j["payUrl"].str
        payBy = ISO.date(j["payBy"].str); payExpired = j["payExpired"].bool
        kind = j["kind"].string ?? "order"
        paidAfterCancel = j["paidAfterCancel"].bool; resumeMissing = j["resumeMissing"].array.map { $0.str }
        let c = j["customer"]
        customerName = [c["firstName"].str, c["lastName"].str].filter { !$0.isEmpty }.joined(separator: " ")
        phone = c["phone"].str; email = c["email"].str; comment = j["comment"].str
        trackNumber = j["tracking"]["number"].str; trackURL = j["tracking"]["url"].str; cdekStatus = j["cdek"]["statusName"].string ?? j["cdek"]["status"].str
        requestOk = j["requestState"]["ok"].bool; requestWhy = j["requestState"]["why"].str
        adminNote = j["adminNote"].str
        history = j["history"].array.map { (ISO.date($0["at"].str), $0["text"].str) }
    }
    /// Равны — тот же заказ с теми же данными с сервера (этап L.0.1, как Product после DEF-3). Раньше — по id, status и payStatus:
    /// экраны, получившие заказ свойством (OrderRow, PayLeftLabel и др.), SwiftUI считал неизменными и после обновления заказа
    /// с теми же статусами показывал прежние срок оплаты, вещи, сумму. Все поля заказа — из raw, поэтому сравнивается он.
    /// Хеш — по id: равные заказы по-прежнему с одинаковым хешем
    static func == (a: Order, b: Order) -> Bool { a.id == b.id && (a.raw.raw as? NSObject)?.isEqual(b.raw.raw) ?? (b.raw.raw == nil) }
    func hash(into h: inout Hasher) { h.combine(id) }

    static let statusRu = ["new": "Принят", "processing": "Собирается", "shipped": "В пути", "done": "Получен", "canceled": "Отменён", "returned": "Возврат"]
    static let statusAdminRu = ["new": "Новый", "processing": "Собирается", "shipped": "Передан в доставку", "done": "Выполнен", "canceled": "Отменён", "returned": "Возврат"]
    var statusText: String { Order.statusRu[status] ?? status }
    var payMethodText: String {
        switch payMethod {
        case "online": return "Онлайн"
        case "cod": return "При получении"
        case "gift": return "Подарочным сертификатом"
        case "bonus": return "Бонусами"
        default: return "Бонусами или сертификатом"
        }
    }
    var payStatusText: String {
        if paid { return "оплачен" }
        if payStatus == "refunded" { return "деньги возвращены" }
        if payStatus == "canceled" { return "оплата не прошла" }
        return "не оплачен"
    }
    var paid: Bool { payStatus == "paid" }
    /// Онлайн-оплата ещё не прошла и её можно продолжить (1.0.2): ссылка ЮKassa сохранена в заказе
    /// Время вышло, но деньги пришли — в корзину не возвращаем, показываем «Оплата пришла после отмены»
    var paidLate: Bool { payExpired && (paidAfterCancel || payStatus == "paid" || payStatus == "refunded") }
    var awaitingPay: Bool { payMethod == "online" && payStatus == "pending" && status != "canceled" && !payUrl.isEmpty }
    /// Секунд до конца срока оплаты по часам сервера (skew = серверное время − время телефона)
    func payLeft(at now: Date, skew: TimeInterval) -> TimeInterval { guard let payBy else { return .infinity }; return payBy.timeIntervalSince(now.addingTimeInterval(skew)) }
}

struct OrderItem: Hashable {
    let productId: String, slug: String, name: String, colorId: String, color: String, size: String, qty: Int, price: Int, image: String
    let sku: String, artKind: String, artTone: String
    /// Время на оплату вышло: сколько этой вещи в наличии прямо сейчас (с сервера; nil — сервер не прислал)
    let stockNow: Int?
    init(_ j: JSON) {
        productId = j["productId"].str; slug = j["slug"].str; name = j["name"].str; colorId = j["colorId"].str; color = j["color"].str
        size = j["size"].str; qty = j["qty"].int ?? 1; price = j["price"].int ?? 0; image = j["image"].str
        stockNow = j["stockNow"].int
        sku = j["sku"].str; artKind = j["art"]["kind"].string ?? "tee"; artTone = j["art"]["tone"].string ?? "#3a3632"
    }
    /// «Молочный · XS · 1 шт. · арт. ALB-0010»
    var meta: String { [color, size, "\(qty) шт.", sku.isEmpty ? "" : "арт. " + sku].filter { !$0.isEmpty }.joined(separator: " · ") }
}

enum ISO {
    private static let f1: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
    private static let f2 = ISO8601DateFormatter()
    static func date(_ s: String) -> Date? { f1.date(from: s) ?? f2.date(from: s) }
    /// День «ГГГГ-ММ-ДД» без времени — в поясе телефона, григорианский календарь (en_US_POSIX): дни форм панели и подарочного
    /// сертификата, слайдов (ISO.day) и диапазона отчёта «Финансы». Форматтер один на приложение (этап K: та же настройка
    /// повторялась в восьми местах). Пояс — autoupdatingCurrent: сменили пояс на телефоне — день считается в новом, как у
    /// форматтера, создаваемого заново при каждом вызове
    static let ymd: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .autoupdatingCurrent
        return f
    }()
}

enum Fmt {
    private static let money: NumberFormatter = { let f = NumberFormatter(); f.numberStyle = .decimal; f.groupingSeparator = "\u{00A0}"; f.maximumFractionDigits = 0; return f }()
    /// Новый форматтер дат для экранов: по-русски, в поясе телефона. Вызывающие хранят его в static let — он создаётся
    /// один раз и после этого не меняется (аудит Q-B6): даты стоят в строках списков, раньше форматтер создавался на каждую
    static func ruDates(_ format: String) -> DateFormatter {
        let f = DateFormatter(); f.locale = Locale(identifier: "ru_RU"); f.timeZone = .autoupdatingCurrent; f.dateFormat = format
        return f
    }
    private static let day = ruDates("d MMMM yyyy"), dayTime = ruDates("d MMMM, HH:mm")
    /// «ноября 2026» — для «С нами с ноября 2026» (родительный падеж — по своему списку месяцев;
    /// созданный здесь раньше форматтер не использовался — убран, аудит Q-B6)
    static func monthYear(_ iso: String) -> String {
        guard let d = ISO.date(iso) else { return "" }
        let months = ["января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря"]
        return months[Calendar.current.component(.month, from: d) - 1] + " " + String(Calendar.current.component(.year, from: d))
    }
    static func num(_ n: Int) -> String { money.string(from: NSNumber(value: n)) ?? "\(n)" }
    static func rub(_ n: Int) -> String { (money.string(from: NSNumber(value: n)) ?? "\(n)") + "\u{00A0}₽" }
    /// Заголовки из панели: «*слово*» на сайте выделяется без курсива — в приложении звёздочки просто убираем
    static func plain(_ s: String) -> String { s.replacingOccurrences(of: #"\*(.+?)\*"#, with: "$1", options: .regularExpression) }
    static func date(_ d: Date?, time: Bool = false) -> String {
        guard let d else { return "" }
        return (time ? dayTime : day).string(from: d)
    }
    static func phone(_ digits: String) -> String {
        let d = digits.filter(\.isNumber)
        guard d.count == 11 else { return digits }
        let a = Array(d)
        return "+7 (\(String(a[1...3]))) \(String(a[4...6]))-\(String(a[7...8]))-\(String(a[9...10]))"
    }
    static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let m10 = n % 10, m100 = n % 100
        if m10 == 1 && m100 != 11 { return one }
        if (2...4).contains(m10) && !(12...14).contains(m100) { return few }
        return many
    }
}
