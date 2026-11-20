#if DEBUG
import XCTest
@testable import Albakov

// Этап L.2.8: витрина демонстрационного режима (снимки экранов) — под замком вместо двух static var. Demo.answer
// вызывают здесь напрямую: включать Demo.on (UserDefaults «screen») в тестах нельзя — его читают и экраны приложения

/// Ответ state: витрина с одним товаром (два размера — Demo дорисует таблицу мерок) и настройкой магазина
private func state(_ name: String, price: Int) -> Data {
    let product: [String: Any] = ["id": "p-\(name)", "slug": name, "name": name, "price": price, "sku": "SKU-\(name)",
                                  "colors": [["id": "c1", "name": "Белый", "images": ["uploads/\(name).jpg"], "sizes": [["size": "S"], ["size": "M"]]]]]
    let body: [String: Any] = ["ok": true, "data": ["settings": ["shopName": "ALBAKOV"], "products": [product]], "user": NSNull(), "isAdmin": false]
    return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
}
/// Ответ Demo как свободный JSON
private func demo(_ method: String, _ path: String, real: Data = Data()) async throws -> JSON {
    let d = try await Demo.answer(method, path, real: { real })
    return JSON(data: try XCTUnwrap(d, "Demo пропустил запрос \(method) \(path) на сервер"))
}

final class DemoSiteTests: XCTestCase {
    /// Витрина из ответа state попадает в state (с таблицей мерок и вымышленной покупательницей) и дальше — в заказы,
    /// панель и журнал: как и до этапа L.2.8
    func test01_StateFeedsOrdersAndPanel() async throws {
        let s = try await demo("GET", "state", real: state("Футболка-L28", price: 4200))
        XCTAssertEqual(s["data"]["products"][0]["name"].str, "Футболка-L28")
        XCTAssertEqual(s["data"]["products"][0]["fit"]["rows"].array.count, 2, "Таблица мерок не дорисована")
        XCTAssertEqual(s["data"]["settings"]["shopName"].str, "ALBAKOV")
        XCTAssertEqual(s["user"]["id"].str, "demo")

        let orders = try await demo("GET", "orders")
        XCTAssertEqual(orders["orders"].array.count, 2)
        XCTAssertEqual(orders["orders"][0]["items"][0]["name"].str, "Футболка-L28")
        XCTAssertEqual(orders["orders"][0]["items"][0]["price"].int, 4200)
        XCTAssertEqual(orders["orders"][0]["items"][0]["image"].str, "uploads/Футболка-L28.jpg")

        let panel = try await demo("GET", "admin/data")
        XCTAssertEqual(panel["data"]["settings"]["shopName"].str, "ALBAKOV", "Настройки витрины не дошли до панели")
        XCTAssertEqual(panel["data"]["products"][0]["name"].str, "Футболка-L28")
        XCTAssertEqual(panel["data"]["products"][0]["fit"]["rows"].array.count, 2)
        XCTAssertEqual(panel["data"]["orders"].array.count, 3)

        let audit = try await demo("GET", "admin/audit")
        XCTAssertTrue(audit["items"][1]["text"].str.contains("Футболка-L28"))
    }

    /// Ответы state и чтения витрины одновременно (как при запуске снимка: витрина грузится, экран уже просит заказы
    /// и панель): каждое чтение видит целиком одну из витрин, без сбоев
    func test02_ConcurrentStateAndReads() async throws {
        let a = state("A-L28", price: 1000), b = state("B-L28", price: 2000)
        _ = try await demo("GET", "state", real: a)
        let names = try await withThrowingTaskGroup(of: String?.self) { g in
            for i in 0..<60 {
                switch i % 3 {
                case 0: g.addTask { _ = try await Demo.answer("GET", "state", real: { i % 2 == 0 ? a : b }); return nil }
                case 1: g.addTask { JSON(data: try await Demo.answer("GET", "admin/data", real: { Data() }) ?? Data())["data"]["products"][0]["name"].string }
                default: g.addTask { JSON(data: try await Demo.answer("GET", "orders", real: { Data() }) ?? Data())["orders"][0]["items"][0]["name"].string }
                }
            }
            var r = [String?](); for try await x in g { r.append(x) }
            return r
        }
        let reads = names.compactMap { $0 }
        XCTAssertEqual(reads.count, 40)
        XCTAssertTrue(reads.allSatisfy { $0 == "A-L28" || $0 == "B-L28" }, "Чтение увидело не ту витрину: \(Set(reads))")
    }
}
#endif
