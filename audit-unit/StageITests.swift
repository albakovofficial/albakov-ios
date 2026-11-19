import XCTest
import SwiftUI
@testable import Albakov

/// Юнит-тесты этапа I: ссылки (Router), витрина и покупатель (Shop), модели, ответы сервера (API).
/// Только проверка, в приложение не входят. Сеть не используется: ответы сервера подменяет NetStub.

// MARK: - Подмена ответов сервера

/// Подменяет ответы сервера для API (этап I). Ответ выбирается по методу и пути («state», «me/cart»);
/// ответ можно придержать до сигнала теста — так проверяются запоздавшие ответы
final class NetStub: URLProtocol {
    struct Reply {
        var status = 200
        var body = Data()
        var error: URLError?
        var hold: DispatchSemaphore?
        static func json(_ object: Any, status: Int = 200) -> Reply {
            Reply(status: status, body: (try? JSONSerialization.data(withJSONObject: object)) ?? Data())
        }
        static func text(_ s: String, status: Int = 200) -> Reply { Reply(status: status, body: Data(s.utf8)) }
        static func fail(_ code: URLError.Code) -> Reply { Reply(error: URLError(code)) }
        func held(_ gate: DispatchSemaphore) -> Reply { var r = self; r.hold = gate; return r }
    }
    struct Seen { let method: String, path: String, query: String?, headers: [String: String], body: Data? }

    private static let lock = NSLock()
    private static var handler: (String, String) -> Reply = { _, _ in .json(["ok": true]) }
    private static var log: [Seen] = []

    /// Новый обработчик ответов; журнал запросов очищается
    static func reset(_ h: @escaping (_ method: String, _ path: String) -> Reply) { lock.lock(); handler = h; log = []; lock.unlock() }
    static func clearSeen() { lock.lock(); log = []; lock.unlock() }
    static var seen: [Seen] { lock.lock(); defer { lock.unlock() }; return log }
    static func paths(_ method: String? = nil) -> [String] { seen.filter { method == nil || $0.method == method }.map(\.path) }

    /// API, ответы которого подменяет NetStub; настройка сессии — та же, что у API.shared
    static func api() -> API {
        let c = API.configuration()
        c.protocolClasses = [NetStub.self]
        return API(base: URL(string: "https://stub.albakov.test")!, configuration: c)
    }

    private var stopped = false   // под NetStub.lock

    override class func canInit(with request: URLRequest) -> Bool { diag("NetStub.canInit \(request.httpMethod ?? "") \(request.url?.path ?? "")"); return true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        diag("NetStub.startLoading \(request.httpMethod ?? "") \(request.url?.path ?? "")")
        let req = request
        var path = req.url?.path ?? ""
        if path.hasPrefix("/api/") { path.removeFirst(5) }
        let method = req.httpMethod ?? "GET"
        let t0 = Date()
        let body = req.httpBody ?? req.httpBodyStream.map(NetStub.read)
        diag("NetStub тело прочитано: \(body?.count ?? -1) Б за \(Int(Date().timeIntervalSince(t0) * 1000)) мс, httpBody=\(req.httpBody != nil), поток=\(req.httpBodyStream != nil)")
        NetStub.lock.lock()
        NetStub.log.append(Seen(method: method, path: path, query: req.url?.query, headers: req.allHTTPHeaderFields ?? [:], body: body))
        let h = NetStub.handler
        NetStub.lock.unlock()
        let t1 = Date()
        let reply = h(method, path)
        diag("NetStub ответ готов за \(Int(Date().timeIntervalSince(t1) * 1000)) мс")
        // Ответ отдаётся в потоке клиента (URLSession), как требует URLProtocol: там же вызывается stopLoading,
        // поэтому проверка «запрос отменён» и ответ не разойдутся. Обычный ответ — сразу, здесь же (этап J: передача
        // через perform на поток клиента иногда не срабатывала — первый запрос ждал таймаут 25 с, Intel-Mac, ios.yml)
        guard let gate = reply.hold else { return deliver(Box(reply)) }
        let thread = Thread.current
        var modes = [RunLoop.Mode.default.rawValue, RunLoop.Mode.common.rawValue]
        if let m = RunLoop.current.currentMode, m != .default { modes.append(m.rawValue) }
        DispatchQueue.global().async {
            gate.wait()
            self.perform(#selector(self.deliver(_:)), on: thread, with: Box(reply), waitUntilDone: false, modes: modes)
        }
    }
    private final class Box: NSObject { let reply: Reply; init(_ r: Reply) { reply = r } }
    @objc private func deliver(_ object: NSObject) {
        NetStub.lock.lock(); let stop = stopped; NetStub.lock.unlock()
        diag("NetStub.deliver \(request.httpMethod ?? "") \(request.url?.path ?? "") stopped=\(stop) client=\(self.client != nil)")
        guard !stop, let client = self.client, let reply = (object as? Box)?.reply else { return }
        if let e = reply.error { client.urlProtocol(self, didFailWithError: e); return }
        guard let url = request.url, let resp = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: nil) else {
            client.urlProtocol(self, didFailWithError: URLError(.badURL)); return
        }
        client.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client.urlProtocol(self, didLoad: reply.body)
        client.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { diag("NetStub.stopLoading \(request.httpMethod ?? "") \(request.url?.path ?? "")"); NetStub.lock.lock(); stopped = true; NetStub.lock.unlock() }

    private static func read(_ s: InputStream) -> Data {
        s.open(); defer { s.close() }
        var d = Data(), buf = [UInt8](repeating: 0, count: 4096)
        while s.hasBytesAvailable {
            let n = s.read(&buf, maxLength: buf.count)
            if n <= 0 { break }
            d.append(buf, count: n)
        }
        return d
    }
}

/// DIAG J.2 (временно): сторож главного потока — раз в 50 мс отправляет отметку на главный поток и пишет, если она опоздала больше чем на 200 мс
final class DiagWatch: @unchecked Sendable {
    private let lock = NSLock(); private var on = true
    init() {
        Thread { [self] in
            while lock.withLock({ on }) {
                let sent = Date(), done = DispatchSemaphore(value: 0)
                DispatchQueue.main.async { done.signal() }
                if done.wait(timeout: .now() + 30) == .timedOut { diag("сторож: главный поток занят больше 30 с"); continue }
                let ms = Int(Date().timeIntervalSince(sent) * 1000)
                if ms > 200 { diag("сторож: главный поток был занят \(ms) мс") }
                usleep(50_000)
            }
        }.start()
    }
    func stop() { lock.withLock { on = false } }
}

/// Ждать условие (до timeout секунд), не блокируя главный поток: ответы и обновления экранов успевают прийти.
/// На главном потоке — условие читает состояние Shop и экранов
@MainActor
func until(_ timeout: TimeInterval = 5, _ ready: () -> Bool) async throws -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while !ready() {
        if Date() > end { return false }
        try await Task.sleep(nanoseconds: 20_000_000)
    }
    return true
}

/// Товар в виде ответа сервера: один цвет c1, размеры M, L, XL
func productJSON(_ id: String, _ price: Int, stock: Int = 5) -> [String: Any] {
    ["id": id, "name": "Футболка \(id)", "price": price, "categoryId": "c1",
     "colors": [["id": "c1", "name": "Чёрный", "hex": "#000000", "images": [String](),
                 "sizes": [["size": "M", "stock": stock], ["size": "L", "stock": stock], ["size": "XL", "stock": stock]]]]]
}

/// Ответ GET state: витрина, покупатель (nil — гость) и права панели
func stateReply(products: [[String: Any]] = [], user: [String: Any]? = nil, staff: Bool = false) -> NetStub.Reply {
    var j: [String: Any] = ["ok": true, "data": ["products": products, "settings": [String: Any]()], "isAdmin": staff]
    if let user { j["user"] = user }
    return .json(j)
}

// MARK: - I-2. Ссылки: сайт, albakov://, push

final class RouterLinkTests: XCTestCase {
    func test01_ProductOpensOnCurrentTabNotAccount() {
        let r = Router()
        r.open(path: "/product/p1")
        XCTAssertEqual(r.tab, .home); XCTAssertEqual(r.home, [.product("p1")])
        r.tab = .catalog
        r.open(path: "product/p2")
        XCTAssertEqual(r.tab, .catalog); XCTAssertEqual(r.catalog, [.product("p2")])
        // из кабинета товар открывается на главной: кабинет — для заказов и панели
        r.tab = .account
        r.open(path: "#/product/p3")
        XCTAssertEqual(r.tab, .home); XCTAssertEqual(r.home, [.product("p1"), .product("p3")])
        XCTAssertEqual(r.account, [])
    }

    func test02_SiteAndAppAddresses() {
        let r = Router()
        r.open(URL(string: "https://albakovofficial.ru/catalog?cat=tees&tag=new")!)
        XCTAssertEqual(r.tab, .catalog); XCTAssertEqual(r.catalog, [.catalog(cat: "tees", tag: "new", sale: false)])
        r.open(URL(string: "https://www.albakovofficial.ru/sale")!)
        XCTAssertEqual(r.catalog, [.catalog(cat: nil, tag: nil, sale: true)])
        r.open(path: "/catalog")
        XCTAssertEqual(r.catalog, [])
        r.open(URL(string: "albakov://cart")!)
        XCTAssertEqual(r.tab, .cart); XCTAssertEqual(r.cart, [])
        r.open(URL(string: "albakov://checkout")!)
        XCTAssertEqual(r.cart, [.checkout])
        r.open(URL(string: "albakov://product/p9")!)
        XCTAssertEqual(r.tab, .cart); XCTAssertEqual(r.cart, [.checkout, .product("p9")])
        r.open(path: "https://albakovofficial.ru/account?tab=bonus")
        XCTAssertEqual(r.tab, .account); XCTAssertEqual(r.account, [.bonus])
        r.open(path: "/account?tab=support&id=t5")
        XCTAssertEqual(r.account, [.support, .ticket("t5")])
        r.open(path: "/favorites")
        XCTAssertEqual(r.tab, .favorites)
        r.open(path: "/menu")
        XCTAssertTrue(r.menuOpen)
    }

    /// Ключ заказа из письма или push сохраняется, только если похож на настоящий (16–64 шестнадцатеричных знака)
    func test03_OrderLinkKeepsOnlyValidKey() {
        let before = UserDefaults.standard.object(forKey: "orderTokens")
        defer { UserDefaults.standard.set(before, forKey: "orderTokens") }
        OrderTokens.clear()
        let r = Router(), key = String(repeating: "ab", count: 16)
        r.open(path: "/order/o1?t=\(key)")
        XCTAssertEqual(r.tab, .account); XCTAssertEqual(r.account, [.orders, .order("o1")])
        XCTAssertEqual(OrderTokens.all["o1"], key)
        for bad in ["zz" + String(repeating: "a", count: 30), "abc", String(repeating: "a", count: 65), ""] {
            r.open(path: "/order/o2?t=\(bad)")
        }
        XCTAssertNil(OrderTokens.all["o2"], "Сохранён ключ неверного вида")
        XCTAssertEqual(r.account, [.orders, .order("o2")], "Заказ без ключа всё равно открывается")
    }

    /// Неизвестная, пустая или неполная ссылка — главная с пустым стеком, без падения
    func test04_UnknownOrIncompleteLinksGoHome() {
        for link in ["/nonsense", "", "/", "#", "/product", "/order", "/page", "/%ZZ", "/admin-x"] {
            let r = Router()
            r.tab = .cart; r.home = [.search]
            r.open(path: link)
            XCTAssertEqual(r.tab, .home, link); XCTAssertEqual(r.home, [], link)
        }
    }

    /// Повторная ссылка (то же уведомление дважды) не наращивает стек: экран открывается заново
    func test05_RepeatedLinksReplaceStack() {
        let r = Router()
        for _ in 0..<3 { r.open(path: "/admin?s=orders&id=7") }
        XCTAssertEqual(r.account, [.admin, .adminOrders, .adminOrder("7")])
        for _ in 0..<3 { r.open(path: "/account?tab=support&id=t1") }
        XCTAssertEqual(r.account, [.support, .ticket("t1")])
        for _ in 0..<3 { r.open(path: "/catalog?cat=a") }
        XCTAssertEqual(r.catalog, [.catalog(cat: "a", tag: nil, sale: false)])
        r.open(path: "/order/o1"); r.open(path: "/order/o1")
        XCTAssertEqual(r.account, [.orders, .order("o1")])
    }

    /// Ссылки панели ведут только на экраны панели (Dest.isAdmin) — их закрывает проверка доступа AdminGate (этап H).
    /// Новый Router — то же, что холодный запуск из push: ссылка разбирается до загрузки витрины
    func test06_AdminLinksLeadOnlyToGatedScreens() {
        let links = ["/admin", "/admin?s=orders", "/admin?s=orders&id=7", "/admin?s=support&id=t", "/admin?s=products&id=p1",
                     "/admin?s=audit", "/admin?s=push", "/admin?s=customers", "/admin?s=categories&id=c1", "/admin?s=promotions",
                     "/admin?s=finance", "/admin?s=finance&id=x", "#/admin?s=orders", "albakov://admin?s=orders",
                     "https://albakovofficial.ru/admin?s=orders&id=7"]
        for link in links {
            let r = Router()
            if link.hasPrefix("albakov:") || link.hasPrefix("https:") { r.open(URL(string: link)!) } else { r.open(path: link) }
            XCTAssertEqual(r.tab, .account, link)
            XCTAssertEqual(r.account.first, .admin, link)
            XCTAssertTrue(r.account.allSatisfy(\.isAdmin), "\(link): \(r.account)")
        }
        let r = Router()
        r.open(path: "/admin?s=orders&id=7")
        XCTAssertEqual(r.account, [.admin, .adminOrders, .adminOrder("7")])
        r.open(path: "/admin?s=categories&id=c1")
        XCTAssertEqual(r.account, [.admin, .adminSection("categories"), .adminItem("categories", "c1")])
        r.open(path: "/admin?s=finance&id=x")
        XCTAssertEqual(r.account, [.admin, .adminSection("finance")], "id у раздела без записей — не запись")
        // ссылки покупателя экранов панели не открывают
        for link in ["/account", "/account?tab=orders", "/account?tab=support&id=1", "/order/1", "/product/admin", "/catalog?cat=admin", "/checkout"] {
            let x = Router()
            x.open(path: link)
            XCTAssertFalse((x.home + x.catalog + x.favorites + x.cart + x.account).contains(where: \.isAdmin), link)
        }
    }
}

// MARK: - I-4. Модели: разбор ответов сервера

final class ModelParsingTests: XCTestCase {
    func test01_ProductMissingFieldsGetDefaults() {
        let p = Product(JSON(["id": "p1"]))
        XCTAssertEqual(p.slug, "p1"); XCTAssertEqual(p.name, ""); XCTAssertEqual(p.price, 0); XCTAssertEqual(p.compareAt, 0)
        XCTAssertTrue(p.active, "Без поля active товар показывается")
        XCTAssertEqual(p.colors.map(\.id), ["col1"]); XCTAssertEqual(p.colors[0].name, "Основной")
        XCTAssertEqual(p.stock, 0); XCTAssertFalse(p.available); XCTAssertEqual(p.image, "")
        XCTAssertEqual(p.color("нет такого").id, "col1")
        let empty = Product(JSON(nil))
        XCTAssertEqual(empty.id, ""); XCTAssertEqual(empty.colors.count, 1)
    }

    func test02_ProductValuesAndLimits() {
        let p = Product(JSON(["id": "p1", "price": "1500", "compareAt": 1990.0, "active": false, "tags": ["new", 5, NSNull()],
                              "colors": [["id": "c1", "images": ["data:image/png;base64,AAA", "uploads/a.jpg"],
                                          "sizes": [["size": "M", "stock": 2], ["size": "L", "stock": "3"], ["size": "XL"]]]],
                              "preorder": true, "preorderLimit": 5, "preorderSold": 7]))
        XCTAssertEqual(p.price, 1500); XCTAssertEqual(p.compareAt, 1990); XCTAssertFalse(p.active)
        XCTAssertEqual(p.tags, ["new", "5"])
        XCTAssertEqual(p.colors[0].images, ["uploads/a.jpg"], "Картинка data: в карточку не попадает")
        XCTAssertEqual(p.colors[0].sizes.map(\.stock), [2, 3, 0]); XCTAssertEqual(p.stock, 5)
        XCTAssertEqual(p.preorderLeft, 0, "Предзаказ сверх лимита — не отрицательный остаток")
        XCTAssertTrue(p.available)
        let unlimited = Product(JSON(["id": "p2", "preorder": true]))
        XCTAssertEqual(unlimited.preorderLeft, Int.max); XCTAssertTrue(unlimited.available)
    }

    func test03_CartLineAndUser() throws {
        XCTAssertNil(CartLine(JSON(["colorId": "c1"])), "Строка корзины без товара отбрасывается")
        XCTAssertEqual(CartLine(JSON(["productId": "p1", "qty": 0]))?.qty, 1)
        XCTAssertEqual(CartLine(JSON(["productId": "p1", "qty": -3]))?.qty, 1)
        XCTAssertEqual(CartLine(JSON(["productId": "p1", "qty": 4]))?.qty, 4)
        XCTAssertEqual(CartLine(JSON(["productId": "p1"]))?.id, "p1||")
        let lines = [CartLine(productId: "p1", colorId: "c1", size: "M", qty: 2)]
        XCTAssertEqual(try JSONDecoder().decode([CartLine].self, from: JSONEncoder().encode(lines)), lines, "Корзина на телефоне читается так же, как записана")
        XCTAssertNil(User(JSON(["firstName": "Анна"])), "Без id — не покупатель")
        let u = User(JSON(["id": 42, "firstName": "Анна", "usedPromos": ["welcome", 7], "cart": [["productId": "p1"], ["qty": 2]], "bonus": "120"]))
        XCTAssertEqual(u?.id, "42"); XCTAssertEqual(u?.name, "Анна"); XCTAssertEqual(u?.usedPromos, ["WELCOME", "7"])
        XCTAssertEqual(u?.cart.count, 1); XCTAssertEqual(u?.bonus, 120)
    }

    func test04_OrderDatesStatusesAndPayment() {
        let o = Order(JSON(["id": "o1", "number": 1042, "createdAt": "2026-11-18T10:00:00.123Z", "payBy": "2026-11-18T10:15:00Z", "status": "new",
                            "payment": ["method": "online", "status": "pending"], "payUrl": "https://pay.example", "items": [["productId": "p1"]], "total": "5900"]))
        XCTAssertEqual(o.number, "1042"); XCTAssertNotNil(o.createdAt); XCTAssertEqual(o.kind, "order")
        XCTAssertEqual(o.items.first?.qty, 1); XCTAssertEqual(o.total, 5900)
        XCTAssertTrue(o.awaitingPay); XCTAssertFalse(o.paid); XCTAssertEqual(o.payStatusText, "не оплачен"); XCTAssertEqual(o.statusText, "Принят")
        if let by = o.payBy {
            XCTAssertEqual(o.payLeft(at: by.addingTimeInterval(-60), skew: 0), 60, accuracy: 0.001)
            XCTAssertEqual(o.payLeft(at: by.addingTimeInterval(-60), skew: 30), 30, accuracy: 0.001, "Срок — по часам сервера")
        } else { XCTFail("payBy не разобран") }
        XCTAssertNil(Order(JSON(["createdAt": "18.11.2026"])).createdAt)
        XCTAssertEqual(Order(JSON(["id": "x"])).payLeft(at: Date(), skew: 0), .infinity)
        XCTAssertEqual(Order(JSON(["status": "lost"])).statusText, "lost", "Неизвестный статус — как есть, без падения")
        // смена оплаты делает заказ «другим» — списки и экраны его обновляют
        let pending = Order(JSON(["id": "o1", "status": "new", "payment": ["status": "pending"]]))
        XCTAssertNotEqual(pending, Order(JSON(["id": "o1", "status": "new", "payment": ["status": "paid"]])))
        XCTAssertNotEqual(pending, Order(JSON(["id": "o1", "status": "canceled", "payment": ["status": "pending"]])))
        XCTAssertTrue(Order(JSON(["payExpired": true, "paidAfterCancel": true])).paidLate)
        XCTAssertFalse(Order(JSON(["payExpired": true, "payment": ["status": "canceled"]])).paidLate)
    }

    /// Как на сайте (Pricing.isPvzMethod / isDoorMethod)
    func test05_DeliveryMethodKinds() {
        func m(_ j: [String: Any]) -> DeliveryMethod { DeliveryMethod(JSON(j)) }
        XCTAssertTrue(m(["name": "СДЭК — пункт выдачи"]).isPvz)
        XCTAssertTrue(m(["name": "CDEK", "desc": "постамат"]).isPvz)
        XCTAssertFalse(m(["name": "СДЭК курьер", "cdekDoor": true]).isPvz); XCTAssertTrue(m(["name": "СДЭК курьер", "cdekDoor": true]).isDoor)
        XCTAssertFalse(m(["name": "Самовывоз", "needsAddress": false]).isPvz); XCTAssertFalse(m(["name": "Самовывоз", "needsAddress": false]).isDoor)
        XCTAssertTrue(m(["name": "Почта", "pickupPoint": true]).isPvz, "Явная отметка пункта выдачи важнее названия")
        XCTAssertFalse(m(["name": "СДЭК пункт выдачи", "pickupPoint": false]).isPvz)
    }

    func test06_JSONAccessNeverCrashes() {
        let j = JSON(data: Data(#"{"a":null,"b":[1,"2",true],"c":"7","d":1.5}"#.utf8))
        XCTAssertFalse(j["a"].exists); XCTAssertFalse(j["нет"]["глубже"][3].exists)
        XCTAssertEqual(j["b"][0].int, 1); XCTAssertEqual(j["b"][1].int, 2); XCTAssertTrue(j["b"][2].bool)
        XCTAssertFalse(j["b"][5].exists); XCTAssertFalse(j["b"][-1].exists)
        XCTAssertEqual(j["c"].int, 7); XCTAssertEqual(j["d"].double, 1.5); XCTAssertEqual(j["d"].int, 1)
        XCTAssertFalse(JSON(data: Data("<html>".utf8)).exists)
    }

    /// DEF-3: товар с той же id, но другими ценой или остатком не равен прежнему — иначе SwiftUI не обновит экран
    /// (см. ShopStateTests.test11). Хеш — по id, как раньше: равные товары по-прежнему с одинаковым хешем
    func test07_ProductEqualityFollowsData() {
        let a = Product(JSON(productJSON("p1", 1000)))
        XCTAssertEqual(a, Product(JSON(productJSON("p1", 1000))))
        XCTAssertNotEqual(a, Product(JSON(productJSON("p1", 2000))), "Новая цена — «тот же» товар (DEF-3)")
        XCTAssertNotEqual(a, Product(JSON(productJSON("p1", 1000, stock: 0))), "Новый остаток — «тот же» товар (DEF-3)")
        XCTAssertNotEqual(a, Product(JSON(productJSON("p2", 1000))))
        XCTAssertEqual(a.hashValue, Product(JSON(productJSON("p1", 2000))).hashValue)
    }
}

// MARK: - I-5. Ответы сервера: API.send

final class APIResponseTests: XCTestCase {
    private let api = NetStub.api()

    func test01_SuccessAndRequestContract() async throws {
        NetStub.reset { _, _ in .json(["ok": true, "count": 3]) }
        let j = try await api.json("GET", "state", query: ["q": "1"])
        XCTAssertEqual(j["count"].int, 3)
        _ = try await api.json("POST", "orders", body: ["a": 1])
        let seen = NetStub.seen
        XCTAssertEqual(seen.map { $0.method + " " + $0.path }, ["GET state", "POST orders"])
        XCTAssertEqual(seen.first?.query, "q=1")
        XCTAssertNil(seen.first?.headers["Content-Type"], "Запрос без тела — без Content-Type")
        XCTAssertNil(seen.first?.body)
        XCTAssertEqual(seen.last?.headers["Content-Type"], "application/json")
        XCTAssertEqual(JSON(data: seen.last?.body ?? Data())["a"].int, 1)
        let c = API.configuration()
        XCTAssertEqual(c.httpAdditionalHeaders as? [String: String], ["Accept": "application/json", "X-Albakov-App": "ios"])
        XCTAssertEqual(c.timeoutIntervalForRequest, 25)
        XCTAssertEqual(c.requestCachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertTrue(c.httpShouldSetCookies)
    }

    func test02_ServerErrorsBecomeAPIError() async {
        let cases: [(reply: NetStub.Reply, message: String, status: Int)] = [
            (.json(["ok": false, "error": "Нет такого размера"]), "Нет такого размера", 200),
            (.json(["ok": false]), "Что-то пошло не так. Попробуйте ещё раз.", 200),
            (.json(["ok": false, "error": "Слишком много попыток"], status: 429), "Слишком много попыток", 429),
            (.json(["ok": true], status: 500), "Что-то пошло не так. Попробуйте ещё раз.", 500),
            (.text("<html>502 Bad Gateway</html>", status: 502), "Сервер магазина не ответил. Попробуйте позже.", 502),
            (.text("", status: 404), "Сервер магазина не ответил. Попробуйте позже.", 404),
        ]
        for (i, c) in cases.enumerated() {
            NetStub.reset { _, _ in c.reply }
            do {
                _ = try await api.raw("GET", "case\(i)")
                XCTFail("Ответ \(c.status) не стал ошибкой")
            } catch let e as APIError {
                XCTAssertEqual(e.message, c.message, "случай \(i)"); XCTAssertEqual(e.status, c.status, "случай \(i)")
            } catch {
                XCTFail("случай \(i): \(error)")
            }
        }
    }

    /// Не JSON вместо ответа магазина (страница, пустой ответ) — ошибка, а не пустые данные (DEF-I1).
    /// Файлы (CSV остатков, PDF накладных) берутся через raw — без разбора
    func test03_NotJSONIsAnError() async throws {
        NetStub.reset { _, _ in .text("<!doctype html><html>Технические работы</html>") }
        let file = try await api.raw("GET", "admin/products/stock.csv")
        XCTAssertFalse(file.isEmpty)
        for body in ["<!doctype html><html>Технические работы</html>", ""] {
            NetStub.reset { _, _ in .text(body) }
            do {
                let j = try await api.json("GET", "state")
                XCTFail("Ответ «\(body.prefix(20))» принят за данные: \(String(describing: j.raw))")
            } catch let e as APIError {
                XCTAssertEqual(e.status, -1); XCTAssertNotNil(e.userMessage)
            } catch {
                XCTFail("\(error)")
            }
        }
    }

    func test04_NetworkErrors() async {
        let offline: [URLError.Code] = [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed]
        for code in offline {
            NetStub.reset { _, _ in .fail(code) }
            do {
                _ = try await api.raw("GET", "state"); XCTFail("\(code): нет ошибки")
            } catch let e as APIError {
                XCTAssertEqual(e.status, 0, "\(code)"); XCTAssertEqual(e.message, APIError.offline.message, "\(code)")
            } catch {
                XCTFail("\(code): \(error)")
            }
        }
        // остальные ошибки связи (например, сертификат) — как есть, с текстом системы
        NetStub.reset { _, _ in .fail(.secureConnectionFailed) }
        do {
            _ = try await api.raw("GET", "state"); XCTFail("нет ошибки")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .secureConnectionFailed); XCTAssertNotNil(error.userMessage)
        }
    }

    /// Ушли с экрана — запрос отменён: это не ошибка для покупателя (userMessage == nil)
    func test05_CancelledRequestIsSilent() async throws {
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        NetStub.reset { _, _ in NetStub.Reply.json(["ok": true]).held(gate) }
        let api = self.api
        let t = Task { try await api.json("GET", "orders") }
        let sent = try await until { NetStub.paths().contains("orders") }
        XCTAssertTrue(sent)
        t.cancel()
        do {
            _ = try await t.value
            XCTFail("Отменённый запрос вернул данные")
        } catch {
            XCTAssertTrue(error.isCancel, "\(error)"); XCTAssertNil(error.userMessage)
        }
    }
}

// MARK: - I-3. Витрина и покупатель: Shop

/// Тесты работают с Shop.shared приложения-хоста: ждут его первую загрузку, подставляют NetStub вместо сервера,
/// а в конце возвращают прежние покупателя, корзину, избранное, записи на телефоне и сервер
@MainActor
final class ShopStateTests: XCTestCase {
    private var shop: Shop { Shop.shared }
    private let line = CartLine(productId: "p1", colorId: "c1", size: "M", qty: 2)
    private var keys: [String] { ["expiredBack2", "expiredUndo", "orderTokens", CheckoutView.draftStore, "cart", "favorites"] }

    private func stubbed(_ body: () async throws -> Void) async throws {
        let hostReady = try await until(30) { Shop.shared.loaded || Shop.shared.loadError != nil }
        XCTAssertTrue(hostReady, "Хост не закончил первую загрузку витрины")
        let was = (api: shop.api, user: shop.user, staff: shop.isStaff, cart: shop.cart, favorites: shop.favorites)
        let d = UserDefaults.standard, saved = keys.map { d.object(forKey: $0) }
        shop.api = NetStub.api()
        NetStub.reset { _, _ in .json(["ok": true]) }
        shop.setUser(nil, staff: false); shop.cart = []; shop.favorites = []; shop.buyNow = nil
        for k in keys { d.removeObject(forKey: k) }
        NetStub.clearSeen()
        defer {
            shop.setUser(was.user, staff: was.staff); shop.cart = was.cart; shop.favorites = was.favorites; shop.buyNow = nil
            for (k, v) in zip(keys, saved) { d.set(v, forKey: k) }
            shop.api = was.api   // отложенные отправки корзины уже взяли NetStub — на сервер не уходят
        }
        try await body()
    }

    func test01_LoadMergesAccountCartAndFavorites() async throws {
        try await stubbed {
            let b = CartLine(productId: "p2", colorId: "c1", size: "L", qty: 1)
            shop.cart = [line]; shop.favorites = ["p1"]
            var inAccount = line.dict; inAccount["qty"] = 5
            NetStub.reset { _, p in p == "state" ? stateReply(products: [productJSON("p1", 1000), productJSON("p2", 1500)],
                                                               user: ["id": "u1", "cart": [inAccount, b.dict], "favorites": ["p2", "p1"]]) : .json(["ok": true]) }
            let watch = DiagWatch(); defer { watch.stop() }
            diag("test01: load начат")
            await shop.load()
            diag("test01: load завершён, user=\(shop.user?.id ?? "nil") cart=\(shop.cart.count)")
            XCTAssertEqual(shop.user?.id, "u1"); XCTAssertFalse(shop.isStaff)
            XCTAssertEqual(shop.products.map(\.id), ["p1", "p2"])
            XCTAssertEqual(shop.cart, [line, b], "Строка с телефона остаётся как есть, новая из аккаунта добавляется")
            XCTAssertEqual(shop.favorites, ["p1", "p2"])
            // объединённая корзина уходит в аккаунт
            let synced = try await until(3) { NetStub.paths("PUT").contains("me/cart") }
            diag("test01: ожидание PUT окончено, synced=\(synced), запросы=\(NetStub.seen.map { $0.method + " " + $0.path })")
            XCTAssertTrue(synced, "Объединённая корзина не ушла в аккаунт")
            if !synced { try await Task.sleep(nanoseconds: 8_000_000_000) }   // DIAG: дать опоздавшему PUT дойти и попасть в журнал
            diagFlush()
            let put = NetStub.seen.last { $0.method == "PUT" && $0.path == "me/cart" }
            XCTAssertEqual(JSON(data: put?.body ?? Data())["lines"].array.compactMap(CartLine.init), [line, b])
        }
    }

    /// Выход, пока ответ state ещё в пути: опоздавший ответ не возвращает прежнего покупателя, его корзину и права
    func test02_StaleStateAfterLogoutIgnored() async throws {
        try await stubbed {
            let gate = DispatchSemaphore(value: 0)
            defer { gate.signal() }
            let inAccount = line.dict
            NetStub.reset { _, p in p == "state" ? stateReply(user: ["id": "u1", "cart": [inAccount], "favorites": ["p9"]], staff: true).held(gate) : .json(["ok": true]) }
            let load = Task { await shop.load() }
            let sent = try await until { NetStub.paths().contains("state") }
            XCTAssertTrue(sent)
            await shop.logout()
            gate.signal()
            await load.value
            XCTAssertNil(shop.user); XCTAssertFalse(shop.isStaff)
            XCTAssertEqual(shop.cart, []); XCTAssertEqual(shop.favorites, [])
        }
    }

    /// Ответ state, запрошенный до входа (гость), пришёл после входа — вошедший не сбрасывается (ревью этапа H)
    func test03_StaleRefreshBeforeSignInIgnored() async throws {
        try await stubbed {
            let gate = DispatchSemaphore(value: 0)
            defer { gate.signal() }
            NetStub.reset { _, p in
                guard p == "state" else { return .json(["ok": true]) }
                return NetStub.paths().filter { $0 == "state" }.count == 1 ? stateReply().held(gate) : stateReply(user: ["id": "u2"])
            }
            let early = Task { await shop.refreshUser() }
            let first = try await until { NetStub.paths().contains("state") }
            XCTAssertTrue(first)
            shop.signedIn(JSON(["user": ["id": "u2"], "isAdmin": false]))
            let second = try await until { NetStub.paths().filter { $0 == "state" }.count == 2 }
            XCTAssertTrue(second)
            try await Task.sleep(nanoseconds: 300_000_000)   // ответ после входа применён
            gate.signal()
            await early.value
            XCTAssertEqual(shop.user?.id, "u2", "Ответ, запрошенный до входа, сбросил вошедшего")
        }
    }

    /// Выход очищает телефон (корзина, избранное, черновик, ключи заказов), а на сервер пустые списки не уходят (аудит F-1)
    func test04_LogoutClearsPhoneNotAccount() async throws {
        try await stubbed {
            shop.setUser(User(JSON(["id": "u1"])), staff: true)
            shop.cart = [line]; shop.favorites = ["p1"]; shop.buyNow = [line]
            UserDefaults.standard.set(["firstName": "Анна"], forKey: CheckoutView.draftStore)
            OrderTokens.save("o1", String(repeating: "a", count: 32))
            let synced = try await until(3) { NetStub.paths("PUT").contains("me/cart") && NetStub.paths("PUT").contains("me/favorites") }
            XCTAssertTrue(synced)
            NetStub.clearSeen()
            await shop.logout()
            XCTAssertNil(shop.user); XCTAssertFalse(shop.isStaff)
            XCTAssertEqual(shop.cart, []); XCTAssertEqual(shop.favorites, []); XCTAssertNil(shop.buyNow)
            XCTAssertNil(UserDefaults.standard.object(forKey: CheckoutView.draftStore)); XCTAssertTrue(OrderTokens.all.isEmpty)
            let onPhone = UserDefaults.standard.data(forKey: "cart").flatMap { try? JSONDecoder().decode([CartLine].self, from: $0) }
            XCTAssertEqual(onPhone, [])
            try await Task.sleep(nanoseconds: 1_200_000_000)
            XCTAssertEqual(NetStub.seen.map { $0.method + " " + $0.path }, ["POST auth/logout"], "Выход стёр корзину или избранное в аккаунте")
        }
    }

    /// Корзина: строки одного размера объединяются, количество — от 1 до 20; запись на телефоне и одна отправка
    /// после серии быстрых изменений; у гостя — только телефон
    func test05_CartSavedAndSyncedOnce() async throws {
        try await stubbed {
            let p = Product(JSON(productJSON("p1", 1000)))
            shop.add(p, color: "c1", size: "M")
            try await Task.sleep(nanoseconds: 1_000_000_000)
            XCTAssertTrue(NetStub.seen.isEmpty, "Корзина гостя ушла на сервер")
            shop.setUser(User(JSON(["id": "u1"])), staff: false)
            let merged = try await until(3) { NetStub.paths("PUT").contains("me/cart") }
            XCTAssertTrue(merged)
            NetStub.clearSeen()
            shop.add(p, color: "c1", size: "M"); shop.add(p, color: "c1", size: "L"); shop.add(p, color: "c1", size: "XL", qty: 3)
            XCTAssertEqual(shop.cart.map(\.qty), [2, 1, 3]); XCTAssertEqual(shop.cartCount, 6)
            let sent = try await until(5) { NetStub.paths("PUT").contains("me/cart") }
            XCTAssertTrue(sent, "Корзина не ушла в аккаунт")
            try await Task.sleep(nanoseconds: 1_000_000_000)   // лишний запрос успел бы прийти
            let puts = NetStub.seen.filter { $0.method == "PUT" && $0.path == "me/cart" }
            XCTAssertEqual(puts.count, 1, "Серия быстрых изменений — один запрос")
            XCTAssertEqual(JSON(data: puts.first?.body ?? Data())["lines"].array.compactMap(CartLine.init), shop.cart)
            let onPhone = UserDefaults.standard.data(forKey: "cart").flatMap { try? JSONDecoder().decode([CartLine].self, from: $0) }
            XCTAssertEqual(onPhone, shop.cart, "На телефоне — не та корзина, что на экране")
            shop.setQty(shop.cart[0], 25); XCTAssertEqual(shop.cart[0].qty, 20)
            shop.setQty(shop.cart[0], 0); XCTAssertEqual(shop.cart.map(\.size), ["L", "XL"])
        }
    }

    /// Обновление того же покупателя не объединяет корзину заново: убранная вещь не возвращается из аккаунта,
    /// а права панели без покупателя не выдаются
    func test06_RefreshSameUserDoesNotMergeAgain() async throws {
        try await stubbed {
            let b = CartLine(productId: "p2", colorId: "c1", size: "L", qty: 1)
            NetStub.reset { _, p in p == "state" ? stateReply(user: ["id": "u1", "cart": [b.dict]]) : .json(["ok": true]) }
            await shop.load()
            XCTAssertEqual(shop.cart, [b])
            shop.cart = []
            await shop.refreshUser()
            XCTAssertEqual(shop.cart, [], "Обновление того же покупателя вернуло убранную вещь")
            shop.setUser(nil, staff: true)
            XCTAssertFalse(shop.isStaff, "Права панели без покупателя")
        }
    }

    /// Время на оплату вышло: вещи возвращаются в корзину один раз; оплата пришла позже — возвращённое убирается
    func test07_ExpiredOrderReturnedOnceAndUndone() async throws {
        try await stubbed {
            NetStub.reset { _, p in p == "state" ? stateReply(products: [productJSON("p1", 1000, stock: 3)]) : .json(["ok": true]) }
            await shop.load()
            let item: [String: Any] = ["productId": "p1", "colorId": "c1", "size": "M", "qty": 2]
            let expired = Order(JSON(["id": "e1", "payExpired": true, "status": "canceled", "items": [item], "payment": ["method": "online", "status": "canceled"]]))
            shop.returnExpired(expired)
            XCTAssertEqual(shop.cart, [CartLine(productId: "p1", colorId: "c1", size: "M", qty: 2)])
            shop.returnExpired(expired)
            XCTAssertEqual(shop.cart.first?.qty, 2, "Вещи вернулись в корзину дважды")
            shop.cart = []
            shop.returnExpired(expired)
            XCTAssertEqual(shop.cart, [], "Убранные покупателем вещи вернулись снова")
            let e2 = Order(JSON(["id": "e2", "payExpired": true, "status": "canceled", "items": [item], "payment": ["status": "canceled"]]))
            shop.returnExpired(e2)
            XCTAssertEqual(shop.cart.count, 1)
            shop.returnExpired(Order(JSON(["id": "e2", "payExpired": false, "status": "new", "items": [item], "payment": ["status": "paid"]])))
            XCTAssertEqual(shop.cart, [], "Заказ возобновился, а вещи остались в корзине — купили бы второй раз")
        }
    }

    /// DEF-4: из истории «уже вернули в корзину» при переполнении уходят самые старые заказы, а не случайные
    func test08_ExpiredHistoryKeepsNewest() async throws {
        try await stubbed {
            for i in 0..<250 { shop.returnExpired(Order(JSON(["id": "h\(i)", "payExpired": true, "status": "canceled"]))) }
            let kept = UserDefaults.standard.stringArray(forKey: "expiredBack2") ?? []
            XCTAssertEqual(kept.count, 200)
            let lost = (50..<250).map { "h\($0)" }.filter { !kept.contains($0) }
            XCTAssertTrue(lost.isEmpty, "Из истории пропали недавние заказы (\(lost.count)): \(lost.prefix(5))")
        }
    }

    /// DEF-I1: страница или пустой ответ вместо ответа магазина не стирает каталог и не сбрасывает вход
    func test09_BrokenStateKeepsShop() async throws {
        try await stubbed {
            NetStub.reset { _, p in p == "state" ? stateReply(products: [productJSON("p1", 1000)], user: ["id": "u1"]) : .json(["ok": true]) }
            await shop.load()
            XCTAssertEqual(shop.products.map(\.id), ["p1"]); XCTAssertEqual(shop.user?.id, "u1")
            NetStub.reset { _, p in p == "state" ? .text("<html>Технические работы</html>") : .json(["ok": true]) }
            await shop.load()
            XCTAssertEqual(shop.products.map(\.id), ["p1"], "Страница вместо ответа магазина стёрла каталог")
            XCTAssertEqual(shop.user?.id, "u1", "Страница вместо ответа магазина сбросила вход")
            XCTAssertNotNil(shop.loadError)
        }
    }

    /// 401 от панели: сеанс сотрудника истёк — витрина перепроверяет вход, права снимаются (этап H). 401 кабинета — без этого
    func test10_AdminUnauthorizedRechecksUser() async throws {
        try await stubbed {
            shop.setUser(User(JSON(["id": "u1"])), staff: true)
            NetStub.reset { _, p in p.hasPrefix("admin/") ? .json(["ok": false, "error": "Войдите"], status: 401) : p == "state" ? stateReply() : .json(["ok": true]) }
            do { _ = try await shop.api.json("GET", "admin/data"); XCTFail("401 не стал ошибкой") } catch let e as APIError { XCTAssertEqual(e.status, 401) }
            let rechecked = try await until { NetStub.paths().contains("state") && !shop.isStaff }
            XCTAssertTrue(rechecked, "После 401 панели вход не перепроверен или права остались")
            shop.setUser(User(JSON(["id": "u1"])), staff: true)
            NetStub.reset { _, p in p == "me" ? .json(["ok": false], status: 401) : .json(["ok": true]) }
            _ = try? await shop.api.json("GET", "me")
            try await Task.sleep(nanoseconds: 500_000_000)
            XCTAssertFalse(NetStub.paths().contains("state"), "401 кабинета перепроверил вход")
            XCTAssertTrue(shop.isStaff)
        }
    }

    /// DEF-3: экран, устроенный как ProductCard (товар — свойство экрана, Shop — из окружения), после обновления
    /// витрины должен показать новую цену
    func test11_ScreenSeesNewPriceAfterReload() async throws {
        try await stubbed {
            NetStub.reset { _, p in p == "state" ? stateReply(products: [productJSON("p1", 1000)]) : .json(["ok": true]) }
            await shop.load()
            PriceProbe.seen = []
            guard let scene = UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene else {
                return XCTFail("Нет сцены приложения-хоста")
            }
            let host = UIHostingController(rootView: PriceProbeList().environmentObject(shop))
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            window.rootViewController = host
            window.isHidden = false
            defer { window.isHidden = true; window.rootViewController = nil }
            host.view.layoutIfNeeded()
            let shown = try await until { PriceProbe.seen.last == 1000 }
            XCTAssertTrue(shown, "Экран не показал товар: \(PriceProbe.seen)")
            NetStub.reset { _, p in p == "state" ? stateReply(products: [productJSON("p1", 2000)]) : .json(["ok": true]) }
            await shop.load()
            _ = try await until(3) { PriceProbe.seen.last == 2000 }
            XCTAssertEqual(shop.products.first?.price, 2000)
            XCTAssertEqual(PriceProbe.seen.last, 2000, "После обновления витрины экран показывает прежнюю цену (DEF-3). Отрисовки: \(PriceProbe.seen)")
        }
    }
}

/// Устроен как ProductCard (HomeView): товар — свойство экрана, Shop — из окружения. Записывает цену при каждой отрисовке
private struct PriceProbe: View {
    @MainActor static var seen: [Int] = []
    let product: Product
    @EnvironmentObject private var shop: Shop
    var body: some View {
        let price = shop.price(product).price
        let _ = PriceProbe.seen.append(price)
        Text(Fmt.rub(price))
    }
}

/// Список, как ряды товаров на главной: ForEach по товарам витрины
private struct PriceProbeList: View {
    @EnvironmentObject private var shop: Shop
    var body: some View { VStack { ForEach(shop.products) { PriceProbe(product: $0) } } }
}
