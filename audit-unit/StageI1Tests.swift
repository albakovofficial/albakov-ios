import XCTest
@testable import Albakov

/// Юнит-тесты этапа I.1: пустой номер заказа или обращения в ссылке — как отсутствующий.
/// Ссылка ведёт туда же, куда ссылка без номера (список заказов, обращений или раздел панели), а не на экран с пустым номером
@MainActor   // Router — на главном акторе (этап L.2.2)
final class RouterEmptyIdTests: XCTestCase {
    /// Все номера (id) в экранах стека — для проверки «пустых номеров нет нигде»
    private func ids(_ d: Dest) -> [String] {
        switch d {
        case .product(let x), .page(let x), .order(let x), .ticket(let x), .adminOrder(let x), .adminTicket(let x),
             .adminProduct(let x), .adminSection(let x): return [x]
        case .adminItem(let k, let x): return [k, x]
        default: return []
        }
    }
    private func opened(_ link: String) -> Router {
        let r = Router()
        if link.hasPrefix("albakov:") { r.open(URL(string: link)!) } else { r.open(path: link) }
        let all = r.home + r.catalog + r.favorites + r.cart + r.account
        XCTAssertFalse(all.flatMap(ids).contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, "\(link): экран с пустым номером \(all)")
        return r
    }

    /// Обращение покупателя: id нет, пустой, из пробелов — список обращений; верный — само обращение
    func test01_SupportTicketLink() {
        for link in ["/account?tab=support", "/account?tab=support&id", "/account?tab=support&id=", "/account?tab=support&id=%20%20",
                     "/account?tab=support&id=%0A", "albakov://account?tab=support&id="] {
            let r = opened(link)
            XCTAssertEqual(r.tab, .account, link); XCTAssertEqual(r.account, [.support], link)
        }
        XCTAssertEqual(opened("/account?tab=support&id=t1").account, [.support, .ticket("t1")])
        XCTAssertEqual(opened("/account?tab=support&id=%20t1").account, [.support, .ticket(" t1")], "Непустой номер передаётся как есть")
    }

    /// Заказ покупателя (/order/<номер>): номер из пробелов — как неполная ссылка «/order» (главная), верный — заказ.
    /// Ключ из ссылки с пустым номером не сохраняется
    func test02_OrderLink() {
        let before = UserDefaults.standard.object(forKey: "orderTokens")
        defer { UserDefaults.standard.set(before, forKey: "orderTokens") }
        OrderTokens.clear()
        for link in ["/order", "/order/", "/order/%20", "/order/%20%20?t=" + String(repeating: "ab", count: 16), "albakov://order/%20"] {
            let r = opened(link)
            XCTAssertEqual(r.tab, .home, link); XCTAssertEqual(r.home, [], link); XCTAssertEqual(r.account, [], link)
        }
        XCTAssertTrue(OrderTokens.all.isEmpty, "Ключ сохранён для пустого номера заказа")
        let r = opened("/order/o1")
        XCTAssertEqual(r.tab, .account); XCTAssertEqual(r.account, [.orders, .order("o1")])
        XCTAssertEqual(opened("albakov://order/42").account, [.orders, .order("42")])
    }

    /// Панель: заказ и обращение без номера, с пустым или из пробелов — список раздела; верный номер — сама запись
    func test03_AdminOrderAndTicketLinks() {
        for (s, list) in [("orders", Dest.adminOrders), ("support", Dest.adminSupport)] {
            for tail in ["", "&id", "&id=", "&id=%20", "&id=%20%20%0A"] {
                let link = "/admin?s=\(s)" + tail
                let r = opened(link)
                XCTAssertEqual(r.tab, .account, link); XCTAssertEqual(r.account, [.admin, list], link)
            }
        }
        XCTAssertEqual(opened("/admin?s=orders&id=7").account, [.admin, .adminOrders, .adminOrder("7")])
        XCTAssertEqual(opened("albakov://admin?s=support&id=t9").account, [.admin, .adminSupport, .adminTicket("t9")])
        XCTAssertEqual(opened("albakov://admin?s=orders&id=").account, [.admin, .adminOrders])
        // неверная форма ссылки на заказ панели: раздела «order» нет — главная панели, а не заказ с пустым номером
        XCTAssertEqual(opened("albakov://admin/order?id=").account, [.admin])
    }

    /// Прочие ссылки с номером ведут себя как раньше; пустой номер записи раздела — сам раздел
    func test04_OtherLinksUnchanged() {
        XCTAssertEqual(opened("/admin?s=products&id=p1").account, [.admin, .adminProducts, .adminProduct("p1")])
        XCTAssertEqual(opened("/admin?s=products&id=").account, [.admin, .adminProducts])
        XCTAssertEqual(opened("/admin?s=categories&id=c1").account, [.admin, .adminSection("categories"), .adminItem("categories", "c1")])
        XCTAssertEqual(opened("/admin?s=categories&id=").account, [.admin, .adminSection("categories")])
        XCTAssertEqual(opened("/admin?s=finance&id=x").account, [.admin, .adminSection("finance")])
        XCTAssertEqual(opened("/product/p1").home, [.product("p1")])
        XCTAssertEqual(opened("/catalog?cat=").catalog, [.catalog(cat: "", tag: nil, sale: false)], "Каталог — без изменений этапа I.1")
        XCTAssertEqual(opened("/account?tab=orders&id=").account, [.orders])
    }
}
