import Foundation

#if DEBUG
/// Только для снимков экрана на GitHub (сборка Debug, в TestFlight и App Store этого кода нет).
/// Запуск с «-screen "/account?demo=staff"»: вымышленная покупательница с правами владельца, её заказы и данные панели.
/// Товары и цены — настоящие с сайта, а всё, что меняет данные (заказы, корзина, push, ответы), на сервер не уходит.
enum Demo {
    static var on: Bool { (UserDefaults.standard.string(forKey: "screen") ?? "").contains("demo=staff") }

    private static var products: [[String: Any]] = []

    /// nil — запрос идёт на сервер как обычно
    static func answer(_ method: String, _ path: String, real: () async throws -> Data) async throws -> Data? {
        if path == "state" {
            let data = try await real()
            guard var j = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return data }
            products = ((j["data"] as? [String: Any])?["products"] as? [[String: Any]]) ?? []
            j["user"] = user; j["isAdmin"] = true
            return try JSONSerialization.data(withJSONObject: j)
        }
        if method == "POST" && path == "quote" { return nil }
        if path.hasPrefix("cdek/") { return nil }
        let parts = path.split(separator: "/").map(String.init)
        var out: [String: Any] = ["ok": true]
        switch (method, parts.first ?? "", parts.count) {
        case ("GET", "orders", 1): out["orders"] = orders
        case ("GET", "orders", 2): out["order"] = orders.first(where: { $0["id"] as? String == parts[1] }) ?? orders[0]
        case ("GET", "me", 1): out["user"] = user; out["bonusLog"] = bonusLog
        case ("GET", "me", _): out["prefs"] = ["orders": true, "support": true, "bonus": true, "promo": false]
        case ("GET", "support", 1): out["tickets"] = [ticket]; out["topics"] = ["Заказ", "Обмен и возврат", "Размер", "Другое"]
        case ("GET", "support", _): out["ticket"] = ticket
        case ("GET", "admin", _):
            switch parts.dropFirst().first ?? "" {
            case "data": out["data"] = ["perms": ["orders", "content", "finance", "marketing", "mail", "payment", "settings", "staff"], "role": "owner", "roleName": "Владелец",
                                        "orders": orders + [order("d4", "1045", status: "new", hoursAgo: 1, name: "Дмитрий Орлов", pay: "online", paid: true)],
                                        "products": products, "users": [user, ["id": "u2", "firstName": "Дмитрий", "lastName": "Орлов", "phone": "79991112233", "email": "dmitry@example.com", "bonus": 120]],
                                        "supportNew": 1] as [String: Any]
            case "support": out["tickets"] = [ticket]
            case "push": out["prefs"] = ["orders": true, "support": true, "stock": true]
            case "audit": out["items"] = [["at": iso(-0.5), "who": "Анна Смирнова", "text": "Заказ № 1043: статус «Передан в доставку»"], ["at": iso(-3), "who": "Анна Смирнова", "text": "Товар «\(firstName)»: остатки"]]
            default: break
            }
        default:
            if method == "GET" { return nil }   // остальные чтения — с сервера как есть
        }
        return try JSONSerialization.data(withJSONObject: out)
    }

    private static var user: [String: Any] {
        ["id": "demo", "firstName": "Анна", "lastName": "Смирнова", "phone": "79990000000", "email": "anna@example.com", "bonus": 450, "supportUnread": 1, "createdAt": iso(-24 * 40), "favorites": [], "cart": []]
    }
    private static var firstName: String { products.first?["name"] as? String ?? "Футболка" }
    private static func iso(_ hours: Double) -> String { ISO8601DateFormatter().string(from: Date().addingTimeInterval(hours * 3600)) }

    private static func order(_ id: String, _ number: String, status: String, hoursAgo: Double, name: String = "Анна Смирнова", pay: String, paid: Bool) -> [String: Any] {
        let p = products.first ?? [:]
        let color = (p["colors"] as? [[String: Any]])?.first ?? [:]
        let price = p["price"] as? Int ?? 3199
        let item: [String: Any] = ["productId": p["id"] ?? "", "slug": p["slug"] ?? "", "name": p["name"] ?? "Футболка", "colorId": color["id"] ?? "", "color": color["name"] ?? "Чёрный",
                                   "size": "M", "qty": 1, "price": price, "image": (color["images"] as? [String])?.first ?? ""]
        let names = name.split(separator: " ").map(String.init)
        return ["id": id, "number": number, "createdAt": iso(-hoursAgo), "status": status, "items": [item],
                "subtotal": price, "total": price, "saleDiscount": 0, "promoDiscount": 0, "bonusUsed": 0, "bonusEarn": price / 20,
                "delivery": ["name": "СДЭК, пункт выдачи", "price": 0, "city": "Москва", "address": "ул. Тверская, 7"],
                "payment": ["method": pay, "status": paid ? "paid" : "pending"],
                "customer": ["firstName": names.first ?? "", "lastName": names.last ?? "", "phone": "79990000000", "email": "anna@example.com"],
                "tracking": status == "shipped" ? ["number": "1234567890", "url": ""] : [:],
                "requestState": ["ok": status == "done", "why": status == "done" ? "" : "Обмен и возврат — после получения"],
                "history": [["at": iso(-hoursAgo), "text": "Заказ оформлен"]]]
    }
    private static var orders: [[String: Any]] {
        [order("d1", "1043", status: "shipped", hoursAgo: 26, pay: "online", paid: true),
         order("d2", "1031", status: "done", hoursAgo: 24 * 12, pay: "cod", paid: true)]
    }
    private static var bonusLog: [[String: Any]] {
        [["at": iso(-24 * 12), "amount": 160, "type": "earn", "orderNumber": "1031"], ["at": iso(-24 * 30), "amount": 290, "type": "welcome"]]
    }
    private static var ticket: [String: Any] {
        ["id": "t1", "number": "58", "name": "Анна Смирнова", "topic": "Размер", "status": "open", "unreadShop": true, "unread": true, "orderNumber": "1043", "createdAt": iso(-2),
         "messages": [["from": "user", "text": "Подскажите, M подойдёт на рост 170?", "at": iso(-2)], ["from": "shop", "text": "Да, M сядет свободно — это оверсайз.", "at": iso(-1)]]]
    }
}
#endif
