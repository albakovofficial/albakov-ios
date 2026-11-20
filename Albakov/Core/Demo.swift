import Foundation
import os

#if DEBUG
/// Только для снимков экрана на GitHub (сборка Debug, в TestFlight и App Store этого кода нет).
/// Запуск с «-screen "/account?demo=staff"»: вымышленная покупательница с правами владельца, её заказы и данные панели.
/// «demo=buyer» — та же покупательница без прав панели (снимки для App Store).
/// Товары и цены — настоящие с сайта, а всё, что меняет данные (заказы, корзина, push, ответы), на сервер не уходит.
enum Demo {
    private static var screen: String { UserDefaults.standard.string(forKey: "screen") ?? "" }
    static var on: Bool { screen.contains("demo=staff") || screen.contains("demo=buyer") }
    private static var staff: Bool { screen.contains("demo=staff") }

    /// Витрина с сайта как есть: настройки, категории, акции, страницы — чтобы разделы панели на снимках были заполнены.
    /// Пишет ответ state, читают ответы заказов, поддержки и панели — из API.raw, вне главного потока и одновременно
    /// (этап L.2.8: раньше — два static var без защиты, гонка данных). Хранится как JSON (Data — Sendable) под замком
    /// и разбирается при чтении: словари [String: Any] не Sendable. До первого ответа state — пусто, как раньше
    private static let site = OSAllocatedUnfairLock<Data?>(initialState: nil)
    private static var pub: [String: Any] {
        site.withLock { $0 }.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
    }
    private static var products: [[String: Any]] { pub["products"] as? [[String: Any]] ?? [] }

    /// nil — запрос идёт на сервер как обычно
    static func answer(_ method: String, _ path: String, real: () async throws -> Data) async throws -> Data? {
        if path == "state" {
            let data = try await real()
            guard var j = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return data }
            var pub = (j["data"] as? [String: Any]) ?? [:]
            pub["products"] = ((pub["products"] as? [[String: Any]]) ?? []).map(withFit); j["data"] = pub
            let snapshot = try JSONSerialization.checkedData(pub)
            site.withLock { $0 = snapshot }
            j["user"] = user; j["isAdmin"] = staff
            return try JSONSerialization.checkedData(j)
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
        case ("GET", "support", 1): out["tickets"] = [ticket, closedTicket]; out["topics"] = ["Заказ", "Доставка", "Размер и посадка", "Возврат и обмен", "Другое"]
        case ("GET", "support", _): out["ticket"] = ticket.merging(["messages": ((ticket["messages"] as? [[String: Any]]) ?? []).filter { $0["from"] as? String != "note" }]) { _, new in new }
        case ("GET", "admin", _):
            switch parts.dropFirst().first ?? "" {
            case "data": out["data"] = pub.merging(["perms": ["orders", "content", "finance", "marketing", "mail", "payment", "settings", "staff"], "role": "owner", "roleName": "Владелец",
                                        "orders": orders + [order("d4", "1045", status: "new", hoursAgo: 1, name: "Дмитрий Орлов", pay: "online", paid: true)],
                                        "products": products, "users": [user, ["id": "u2", "firstName": "Дмитрий", "lastName": "Орлов", "phone": "79991112233", "email": "dmitry@example.com", "bonus": 120]],
                                        "supportNew": 1, "promocodes": [Any](), "waitlist": [Any]()] as [String: Any]) { _, new in new }
            case "support":
                if parts.count > 2 {
                    out["ticket"] = ticket
                    out["customer"] = ["id": "demo", "name": "Анна Смирнова", "email": "anna@example.com", "phone": "79990000000", "createdAt": iso(-24 * 40), "bonus": 450,
                                       "orders": orders.map { ["id": $0["id"] ?? "", "number": $0["number"] ?? "", "status": $0["status"] ?? "", "total": $0["total"] ?? 0, "createdAt": $0["createdAt"] ?? ""] },
                                       "tickets": [["id": "t0", "number": "1031", "topic": "Доставка", "status": "closed", "updatedAt": iso(-24 * 9)]]] as [String: Any]
                } else {
                    out["tickets"] = [ticket, closedTicket]
                    out["templates"] = [["id": "size", "title": "Подбор размера", "text": "Подскажите рост и обычный размер — подберём по меркам изделия."],
                                        ["id": "exchange", "title": "Как оформить обмен", "text": "Обменять размер можно в личном кабинете: «Заказы» → заказ → «Обмен и возврат»."]]
                }
            case "push": out["prefs"] = ["orders": true, "support": true, "stock": true]
            case "audit": out["items"] = [["at": iso(-0.5), "who": "Анна Смирнова", "text": "Заказ № 1043: статус «Передан в доставку»"], ["at": iso(-3), "who": "Анна Смирнова", "text": "Товар «\(firstName)»: остатки"]]
            default: break
            }
        default:
            if method == "GET" { return nil }   // остальные чтения — с сервера как есть
        }
        return try JSONSerialization.checkedData(out)
    }

    /// Таблица размеров для снимков, если у товара на сайте её ещё нет: мерки оверсайз-футболки по размерам товара
    private static func withFit(_ p: [String: Any]) -> [String: Any] {
        if let rows = (p["fit"] as? [String: Any])?["rows"] as? [Any], !rows.isEmpty { return p }
        let base: [String: [Double]] = ["XS": [54, 68, 22], "S": [56, 70, 23], "M": [58, 72, 24], "L": [60, 74, 25], "XL": [62, 76, 26], "2XL": [64, 78, 27], "XXL": [64, 78, 27], "3XL": [66, 80, 28]]
        var sizes: [String] = []
        for c in (p["colors"] as? [[String: Any]]) ?? [] { for s in (c["sizes"] as? [[String: Any]]) ?? [] { if let z = s["size"] as? String, base[z] != nil, !sizes.contains(z) { sizes.append(z) } } }
        guard sizes.count >= 2 else { return p }
        var out = p
        out["fit"] = ["rows": sizes.map { z in let m = base[z]!; return ["size": z, "w": m[0], "l": m[1], "sl": m[2]] }, "cols": [String](), "note": ""]
        return out
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
                                   "size": "M", "qty": 1, "price": price, "image": (color["images"] as? [String])?.first ?? "", "sku": p["sku"] ?? "ALB-0001"]
        let names = name.split(separator: " ").map(String.init)
        return ["id": id, "number": number, "createdAt": iso(-hoursAgo), "status": status, "items": [item],
                "subtotal": price, "total": price, "saleDiscount": 0, "promoDiscount": 0, "bonusUsed": 0, "bonusEarn": price / 20,
                "delivery": ["name": "СДЭК, пункт выдачи", "price": 0, "city": "Москва", "address": "ул. Тверская, 7"],
                "payment": ["method": pay, "status": paid ? "paid" : "pending"],
                "payUrl": pay == "online" && !paid ? "https://yoomoney.ru/checkout/demo" : "", "payBy": pay == "online" && !paid ? iso(0.2) : "",
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
        let o = orders[0], it = (o["items"] as? [[String: Any]])?.first ?? [:]
        return ["id": "t1", "number": "1043", "name": "Анна Смирнова", "phone": "79990000000", "email": "anna@example.com", "topic": "Размер и посадка", "status": "answered", "unreadShop": false, "unread": true,
                "orderId": "d1", "orderNumber": "1043", "createdAt": iso(-2), "updatedAt": iso(-1), "firstReplyAt": iso(-1.8), "shopReadAt": iso(-1.8), "userReadAt": iso(-1),
                "assignee": ["id": "demo", "name": "Анна"],
                "order": ["id": "d1", "number": "1043", "status": "shipped", "total": o["total"] ?? 0, "items": 1, "name": it["name"] ?? "", "color": it["color"] ?? "", "size": "L", "image": it["image"] ?? ""],
                "messages": [["from": "user", "text": "Здравствуйте! Рост 182, вес 78. Футболка L села великовато — может, поменять на M?", "at": iso(-2), "files": [String]()],
                             ["from": "note", "text": "Резерв M отложен до пятницы", "at": iso(-1.9), "by": "Анна", "files": [String]()],
                             ["from": "shop", "text": "Здравствуйте! Оверсайз задуман свободным — советуем M, обмен бесплатный.", "at": iso(-1.8), "by": "Анна", "files": [String]()]]]
    }
    private static var closedTicket: [String: Any] {
        ["id": "t0", "number": "1031", "name": "Анна Смирнова", "topic": "Доставка", "status": "closed", "unread": false, "orderNumber": "1031", "createdAt": iso(-24 * 10), "updatedAt": iso(-24 * 9),
         "messages": [["from": "user", "text": "Спасибо, всё получила!", "at": iso(-24 * 9), "files": [String]()]]]
    }
}
#endif
