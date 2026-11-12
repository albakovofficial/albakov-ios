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
    init(_ j: JSON) {
        id = j["id"].str; name = j["name"].str; hex = j["hex"].str
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
    let description: String, composition: String, care: String, fit: String
    let sizeChartId: String
    let active: Bool
    let createdAt: String
    let sku: String
    let preorder: Bool, preorderLimit: Int, preorderSold: Int, preorderText: String
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
            let old: [String: Any] = ["id": "col1", "name": j["color"].string ?? "Основной", "images": j["images"].raw ?? [Any](), "sizes": j["sizes"].raw ?? [Any]()]
            cs = [PColor(JSON(old))]
        }
        colors = cs
        description = j["description"].str; composition = j["composition"].str; care = j["care"].str; fit = j["fit"].str
        sizeChartId = j["sizeChartId"].str
        active = j["active"].exists ? j["active"].bool : true
        createdAt = j["createdAt"].str; sku = j["sku"].str
        preorder = j["preorder"].bool; preorderLimit = j["preorderLimit"].int ?? 0; preorderSold = j["preorderSold"].int ?? 0
        preorderText = j["preorderText"].str
        badgeText = j["badgeText"].dict.compactMapValues { $0.string }
        badgeOff = j["badgeOff"].array.compactMap { $0.string }
    }
    static func == (a: Product, b: Product) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    var image: String { colors.first(where: { !$0.images.isEmpty })?.images.first ?? "" }
    func color(_ id: String?) -> PColor { colors.first { $0.id == id } ?? colors[0] }
    var stock: Int { colors.reduce(0) { $0 + $1.stock } }
    var preorderLeft: Int { !preorder ? 0 : preorderLimit > 0 ? max(0, preorderLimit - preorderSold) : Int.max }
    var available: Bool { stock > 0 || preorderLeft > 0 }
    func forGender(_ g: String?) -> Bool { g == nil || gender.isEmpty || gender == "unisex" || gender == g }
}

struct Category: Identifiable, Hashable {
    let id: String, name: String, slug: String, image: String, order: Int, gender: String
    init(_ j: JSON) { id = j["id"].str; name = j["name"].str; slug = j["slug"].str; image = j["image"].str; order = j["order"].int ?? 0; gender = j["gender"].str }
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
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .current
        if !startsAt.isEmpty, let d = f.date(from: startsAt + " 00:00:00"), now < d { return false }
        if !endsAt.isEmpty, let d = f.date(from: endsAt + " 23:59:59"), now > d { return false }
        return true
    }
}

struct Price { let price: Int; let oldPrice: Int; var percent: Int { oldPrice > 0 ? Int((1 - Double(price) / Double(oldPrice)) * 100 + 0.5) : 0 } }

struct SizeChart: Identifiable {
    let id: String, name: String, columns: [String], rows: [[String]], note: String
    init(_ j: JSON) { id = j["id"].str; name = j["name"].str; columns = j["columns"].array.map { $0.str }; rows = j["rows"].array.map { $0.array.map { $0.str } }; note = j["note"].str }
}

struct Page: Identifiable { let id: String, slug: String, title: String, body: String, group: String
    init(_ j: JSON) { id = j["id"].str; slug = j["slug"].str; title = j["title"].str; body = j["body"].str; group = j["group"].str }
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
    let id: String, eyebrow: String, title: String, text: String, image: String, btn1: (String, String), btn2: (String, String), gender: String
    init(_ j: JSON) {
        id = j["id"].str; eyebrow = j["eyebrow"].str; title = j["title"].str; text = j["text"].str; image = j["image"].str; gender = j["gender"].str
        btn1 = (j["btn1"]["label"].str, j["btn1"]["link"].str); btn2 = (j["btn2"]["label"].str, j["btn2"]["link"].str)
    }
}

struct Social: Identifiable, Hashable { let name: String; let url: String; var id: String { url } }

struct Settings {
    let storeName: String, tagline: String, announcement: String
    let phone: String, email: String, hours: String, address: String, appStore: String
    let socials: [Social]
    let delivery: [DeliveryMethod]
    let payOnline: Bool, payCod: Bool, onlineLabel: String, codLabel: String
    let bonusEnabled: Bool, bonusPercent: Int, bonusOnlineExtra: Int
    let slides: [Slide]
    let badges: [String: (text: String, color: String)]
    let gendersOpen: [String: Bool]
    let exchangeDays: Int
    let raw: JSON

    init(_ j: JSON) {
        raw = j
        storeName = j["storeName"].string ?? "ALBAKOV"; tagline = j["tagline"].str; announcement = j["announcement"].str
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
    }
}

struct User {
    let id: String, firstName: String, lastName: String, phone: String, email: String, bonus: Int, supportUnread: Int
    let favorites: [String]
    let cart: [CartLine]
    init?(_ j: JSON) {
        guard let id = j["id"].string else { return nil }
        self.id = id; firstName = j["firstName"].str; lastName = j["lastName"].str; phone = j["phone"].str; email = j["email"].str
        bonus = j["bonus"].int ?? 0; supportUnread = j["supportUnread"].int ?? 0
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
    let items: [OrderItem]
    let subtotal: Int, total: Int, saleDiscount: Int, promoDiscount: Int, promoCode: String, bonusUsed: Int, bonusEarn: Int
    let deliveryName: String, deliveryPrice: Int, city: String, address: String
    let payMethod: String, payStatus: String
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
        promoCode = j["promoCode"].str; bonusUsed = j["bonusUsed"].int ?? 0; bonusEarn = j["bonusEarn"].int ?? 0
        let d = j["delivery"]
        deliveryName = d["name"].str; deliveryPrice = d["price"].int ?? 0; city = d["city"].str; address = d["address"].str
        payMethod = j["payment"]["method"].str; payStatus = j["payment"]["status"].str
        let c = j["customer"]
        customerName = [c["firstName"].str, c["lastName"].str].filter { !$0.isEmpty }.joined(separator: " ")
        phone = c["phone"].str; email = c["email"].str; comment = j["comment"].str
        trackNumber = j["tracking"]["number"].str; trackURL = j["tracking"]["url"].str; cdekStatus = j["cdek"]["statusName"].string ?? j["cdek"]["status"].str
        requestOk = j["requestState"]["ok"].bool; requestWhy = j["requestState"]["why"].str
        adminNote = j["adminNote"].str
        history = j["history"].array.map { (ISO.date($0["at"].str), $0["text"].str) }
    }
    static func == (a: Order, b: Order) -> Bool { a.id == b.id && a.status == b.status && a.payStatus == b.payStatus }
    func hash(into h: inout Hasher) { h.combine(id) }

    static let statusRu = ["new": "Принят", "processing": "Собирается", "shipped": "В пути", "done": "Получен", "canceled": "Отменён", "returned": "Возврат"]
    static let statusAdminRu = ["new": "Новый", "processing": "Собирается", "shipped": "Передан в доставку", "done": "Выполнен", "canceled": "Отменён", "returned": "Возврат"]
    var statusText: String { Order.statusRu[status] ?? status }
    var payMethodText: String {
        switch payMethod {
        case "online": return "Онлайн"
        case "cod": return "При получении"
        default: return "Бонусами или сертификатом"
        }
    }
    var payStatusText: String {
        if paid { return "оплачен" }
        if payStatus == "refunded" { return "деньги возвращены" }
        return "не оплачен"
    }
    var paid: Bool { payStatus == "paid" }
}

struct OrderItem: Hashable {
    let productId: String, slug: String, name: String, colorId: String, color: String, size: String, qty: Int, price: Int, image: String
    init(_ j: JSON) {
        productId = j["productId"].str; slug = j["slug"].str; name = j["name"].str; colorId = j["colorId"].str; color = j["color"].str
        size = j["size"].str; qty = j["qty"].int ?? 1; price = j["price"].int ?? 0; image = j["image"].str
    }
}

enum ISO {
    private static let f1: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
    private static let f2 = ISO8601DateFormatter()
    static func date(_ s: String) -> Date? { f1.date(from: s) ?? f2.date(from: s) }
}

enum Fmt {
    private static let money: NumberFormatter = { let f = NumberFormatter(); f.numberStyle = .decimal; f.groupingSeparator = "\u{00A0}"; f.maximumFractionDigits = 0; return f }()
    static func rub(_ n: Int) -> String { (money.string(from: NSNumber(value: n)) ?? "\(n)") + "\u{00A0}₽" }
    static func date(_ d: Date?, time: Bool = false) -> String {
        guard let d else { return "" }
        let f = DateFormatter(); f.locale = Locale(identifier: "ru_RU"); f.dateFormat = time ? "d MMMM, HH:mm" : "d MMMM yyyy"
        return f.string(from: d)
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
