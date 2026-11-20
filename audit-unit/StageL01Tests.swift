import XCTest
import SwiftUI
@testable import Albakov

/// Этап L.0.1: равенство заказов. Экраны получают заказ свойством (OrderRow, OrderCard, PayLeftLabel, карточки PayTimer),
/// и SwiftUI не перерисовывает такой экран, если новый заказ «равен» прежнему. Раньше Order == сравнивал только id, status
/// и payStatus: после обновления заказа с теми же статусами экран мог показывать прежние срок оплаты, вещи, сумму, трек-номер —
/// тот же механизм, что у товаров в DEF-3 (этап I, ModelParsingTests.test07 и ShopStateTests.test11)
final class OrderEqualityTests: XCTestCase {
    /// Заказ в ожидании онлайн-оплаты; extra заменяет поля целиком
    static func orderJSON(_ extra: [String: Any] = [:]) -> [String: Any] {
        var j: [String: Any] = ["id": "o1", "number": "1042", "status": "new", "createdAt": "2026-11-20T10:00:00Z",
                                "payment": ["method": "online", "status": "pending"], "payUrl": "https://pay.example",
                                "payBy": "2026-11-20T10:15:00Z", "payExpired": false, "total": 5900, "subtotal": 5900,
                                "items": [["productId": "p1", "colorId": "col1", "size": "M", "qty": 1, "price": 5900]],
                                "customer": ["firstName": "Анна", "lastName": "Смирнова"],
                                "tracking": ["number": "", "url": ""]]
        j.merge(extra) { _, new in new }
        return j
    }

    func test01_SameDataIsEqual() {
        let a = Order(JSON(Self.orderJSON())), b = Order(JSON(Self.orderJSON()))
        XCTAssertEqual(a, b, "Тот же заказ с теми же данными — равен")
        XCTAssertEqual(a.hashValue, b.hashValue)
        XCTAssertNotEqual(a, Order(JSON(Self.orderJSON(["id": "o2"]))), "Другой заказ — не равен")
    }

    /// Каждое поле меняется само по себе, id, status и payStatus — прежние
    func test02_ContentChangeWithSameStatusesIsNotEqual() {
        let base = Order(JSON(Self.orderJSON()))
        let changes: [(String, [String: Any])] = [
            ("payBy", ["payBy": "2026-11-20T10:30:00Z"]),
            ("payExpired", ["payExpired": true]),
            ("paidAfterCancel", ["paidAfterCancel": true]),
            ("trackNumber", ["tracking": ["number": "1234567890", "url": "https://cdek.ru/track"]]),
            ("items", ["items": [["productId": "p1", "colorId": "col1", "size": "L", "qty": 2, "price": 5900]]]),
            ("total", ["total": 4900]),
            ("customer", ["customer": ["firstName": "Анна", "lastName": "Иванова"]]),
        ]
        for (field, extra) in changes {
            let changed = Order(JSON(Self.orderJSON(extra)))
            XCTAssertEqual([changed.id, changed.status, changed.payStatus], [base.id, base.status, base.payStatus], "Проверка «\(field)»: статусы должны совпадать")
            XCTAssertNotEqual(changed, base, "Изменилось «\(field)» при тех же id, status и payStatus — заказ считается прежним")
            XCTAssertEqual(changed.hashValue, base.hashValue, "Хеш — по id, как раньше")
        }
        // смена статусов по-прежнему делает заказ другим (как в ModelParsingTests.test04)
        XCTAssertNotEqual(base, Order(JSON(Self.orderJSON(["status": "processing"]))))
        XCTAssertNotEqual(base, Order(JSON(Self.orderJSON(["payment": ["method": "online", "status": "paid"]]))))
    }

    /// Экран, устроенный как OrderRow (заказ — свойство экрана), в списке ForEach: после замены заказа с теми же id и
    /// статусами, но другой суммой, должен показать новую сумму
    @MainActor
    func test03_RowShowsNewContentAfterReload() async throws {
        OrderProbe.seen = []
        let feed = OrderFeed()
        feed.orders = [Order(JSON(Self.orderJSON()))]
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene else {
            return XCTFail("Нет сцены приложения-хоста")
        }
        let host = UIHostingController(rootView: OrderProbeList(feed: feed))
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.layoutIfNeeded()
        let shown = try await until { OrderProbe.seen.last == 5900 }
        XCTAssertTrue(shown, "Экран не показал заказ: \(OrderProbe.seen)")
        feed.orders = [Order(JSON(Self.orderJSON(["total": 4900])))]
        _ = try await until(3) { OrderProbe.seen.last == 4900 }
        XCTAssertEqual(OrderProbe.seen.last, 4900, "После обновления заказа с теми же статусами экран показывает прежнюю сумму. Отрисовки: \(OrderProbe.seen)")
    }
}

@MainActor
private final class OrderFeed: ObservableObject {
    @Published var orders: [Order] = []
}

/// Устроен как OrderRow: заказ — свойство экрана. Записывает сумму при каждой отрисовке
private struct OrderProbe: View {
    @MainActor static var seen: [Int] = []
    let order: Order
    var body: some View {
        let _ = OrderProbe.seen.append(order.total)
        Text(Fmt.rub(order.total))
    }
}

/// Список, как «Мои заказы» и заказы в панели: ForEach по заказам
private struct OrderProbeList: View {
    @ObservedObject var feed: OrderFeed
    var body: some View { VStack { ForEach(feed.orders) { OrderProbe(order: $0) } } }
}
