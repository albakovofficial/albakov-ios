import XCTest
@testable import Albakov

/// Этап K.1, K-M1: «Добавить образ в корзину» — всё или ничего. Раньше вещи до первой вещи без размера уже лежали
/// в корзине, а повторное нажатие клало их второй раз
@MainActor
final class LookAddTests: XCTestCase {
    private var shop: Shop { Shop.shared }
    /// Корзина хоста на время теста пустая и потом возвращается (гость: на сервер ничего не уходит)
    private func clean(_ body: () -> Void) { let was = shop.cart; shop.cart = []; defer { shop.cart = was }; body() }

    private func item(_ id: String, sizes: [String]) -> Product {
        Product(JSON(["id": id, "name": "Вещь \(id)", "price": 1000,
                      "colors": [["id": "c-\(id)", "name": "Чёрный", "sizes": sizes.map { ["size": $0, "stock": 3] }]]]))
    }
    /// Эта вещь (размер — из карточки) и три вещи образа: p1 и p3 с выбором размера, у p2 в наличии один размер — он берётся сам
    private lazy var all = [item("p0", sizes: ["M", "L"]), item("p1", sizes: ["S", "M"]), item("p2", sizes: ["XL"]), item("p3", sizes: ["M", "L"])]
    private func add(main: String? = "M", sizes: [String: String], off: Set<String> = []) -> (missing: Product?, added: Int) {
        LookSection.add(all, off: off, sizes: sizes, mainColor: all[0].colors[0], mainSize: main, to: shop)
    }
    private var cart: [String] { shop.cart.map { "\($0.productId) \($0.colorId) \($0.size) ×\($0.qty)" } }
    private let full = ["p0 c-p0 M ×1", "p1 c-p1 S ×1", "p2 c-p2 XL ×1", "p3 c-p3 L ×1"]

    func test01_AllSizesChosen() {
        clean {
            let r = add(sizes: ["p1": "S", "p3": "L"])
            XCTAssertNil(r.missing); XCTAssertEqual(r.added, 4)
            XCTAssertEqual(cart, full)
        }
    }

    func test02_FirstWithoutSize() {
        clean {
            let r = add(main: nil, sizes: ["p1": "S", "p3": "L"])
            XCTAssertEqual(r.missing?.id, "p0"); XCTAssertEqual(r.added, 0)
            XCTAssertEqual(cart, [], "Без размера этой вещи в корзину не должно попасть ничего")
        }
    }

    func test03_LastWithoutSize() {
        clean {
            let r = add(sizes: ["p1": "S"])
            XCTAssertEqual(r.missing?.id, "p3"); XCTAssertEqual(r.added, 0)
            XCTAssertEqual(cart, [], "Вещи до последней попали в корзину частично")
        }
    }

    func test04_MiddleWithoutSize() {
        clean {
            let r = add(sizes: ["p3": "L"])
            XCTAssertEqual(r.missing?.id, "p1"); XCTAssertEqual(r.added, 0)
            XCTAssertEqual(cart, [], "Эта вещь попала в корзину раньше вещи без размера")
        }
    }

    /// Нажали без размера, ещё раз без размера, выбрали размер, нажали — в корзине каждая вещь по одной
    func test05_RepeatAfterFailure() {
        clean {
            XCTAssertEqual(add(sizes: ["p1": "S"]).missing?.id, "p3")
            XCTAssertEqual(add(sizes: ["p1": "S"]).missing?.id, "p3")
            XCTAssertEqual(cart, [])
            XCTAssertNil(add(sizes: ["p1": "S", "p3": "L"]).missing)
            XCTAssertEqual(cart, full, "После неудачных нажатий вещи задвоились")
        }
    }

    /// Убранная из образа вещь не мешает: размер у неё не нужен, в корзину она не идёт
    func test06_RemovedItemNeedsNoSize() {
        clean {
            let r = add(sizes: ["p1": "S"], off: ["p3"])
            XCTAssertNil(r.missing); XCTAssertEqual(r.added, 3)
            XCTAssertEqual(cart, ["p0 c-p0 M ×1", "p1 c-p1 S ×1", "p2 c-p2 XL ×1"])
        }
    }
}

/// Этап K.1, K-M3: подписка на push идёт строго по очереди, последней — самая новая. Раньше каждая отправка шла
/// сама по себе, и при быстром выходе и входе «отписать сотрудника» могло прийти на сервер после «подписать»
@MainActor
final class PushOrderTests: XCTestCase {
    private var shop: Shop { Shop.shared }
    private var push: PushManager { PushManager.shared }
    private let staff = User(JSON(["id": "staff1"]))
    private let buyer = User(JSON(["id": "buyer1"]))

    /// Ответ, который отдаётся один раз — для первого подходящего запроса
    private final class Once: @unchecked Sendable {
        private let lock = NSLock(); private var used = false
        func take() -> Bool { lock.lock(); defer { lock.unlock() }; if used { return false }; used = true; return true }
    }
    /// Запросы подписки по порядку прихода на «сервер»: «subscribe customer», «unsubscribe staff»…
    private var ops: [String] {
        NetStub.seen.filter { $0.path.hasPrefix("push/") }.map { s in
            let scope = s.body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["scope"] as? String
            return "\(s.path.dropFirst(5)) \(scope ?? "?")"
        }
    }
    private func drain() async { await push.sync?.value }

    /// Витрина и подписка — через NetStub, витрина загружена, покупателя нет, адрес устройства есть
    private func stubbed(_ reply: @escaping (String, String) -> NetStub.Reply = { _, _ in .json(["ok": true]) },
                         _ body: () async throws -> Void) async throws {
        let ready = try await until(30) { Shop.shared.loaded || Shop.shared.loadError != nil }
        XCTAssertTrue(ready, "Хост не закончил первую загрузку витрины")
        let was = (api: shop.api, push: push.api, user: shop.user, staff: shop.isStaff, cart: shop.cart, favorites: shop.favorites)
        shop.api = NetStub.api(); push.api = NetStub.api()
        NetStub.reset { m, p in p == "state" ? stateReply() : reply(m, p) }
        shop.setUser(nil, staff: false)
        await shop.load()
        XCTAssertTrue(shop.loaded)
        if push.token == nil { push.didRegister(deviceToken: Data([0xAB, 0xCD, 0x01])) }
        await drain(); NetStub.clearSeen()
        try await body()
        await drain()
        shop.setUser(was.user, staff: was.staff); shop.cart = was.cart; shop.favorites = was.favorites
        await drain()   // отправка от восстановления уходит в NetStub, а не на сервер и не в следующий тест
        shop.api = was.api; push.api = was.push
    }
    private func signInStaff() async { shop.setUser(staff, staff: true); await drain() }

    func test01_LoginStaff() async throws {
        try await stubbed {
            shop.setUser(staff, staff: true)
            await drain()
            XCTAssertEqual(ops, ["subscribe customer", "subscribe staff"])
        }
    }

    func test02_LoginBuyer() async throws {
        try await stubbed {
            shop.setUser(buyer, staff: false)
            await drain()
            XCTAssertEqual(ops, ["subscribe customer", "unsubscribe staff"])
        }
    }

    func test03_Logout() async throws {
        try await stubbed {
            await signInStaff(); NetStub.clearSeen()
            shop.setUser(nil, staff: false); push.resend()
            await drain()
            XCTAssertEqual(ops, ["subscribe customer", "unsubscribe staff"])
        }
    }

    /// Выход и сразу вход: «отписать» выхода задержалось на сервере. Вход ждёт, пока оно закончится, и только потом
    /// подписывает — на сервере последним остаётся «подписать»
    func test04_FastLogoutLoginKeepsOrder() async throws {
        let gate = DispatchSemaphore(value: 0), once = Once()
        defer { gate.signal() }
        try await stubbed({ _, p in p == "push/unsubscribe" && once.take() ? Reply.ok.held(gate) : .ok }) {
            await signInStaff(); NetStub.clearSeen()
            shop.setUser(nil, staff: false); push.resend()
            let held = try await until(10) { self.ops == ["subscribe customer", "unsubscribe staff"] }
            XCTAssertTrue(held, "Выход не дошёл до «отписать»: \(ops)")
            shop.setUser(staff, staff: true)   // вход: новая отправка
            try await Task.sleep(nanoseconds: 500_000_000)
            XCTAssertEqual(ops, ["subscribe customer", "unsubscribe staff"], "Вход отправил подписку, не дождавшись «отписать» выхода")
            gate.signal()
            await drain()
            XCTAssertEqual(ops, ["subscribe customer", "unsubscribe staff", "subscribe customer", "subscribe staff"])
        }
    }

    /// Несколько быстрых переключений, пока первый запрос задержан: промежуточные отправки ничего не шлют,
    /// последней выполняется самая новая (вход сотрудника)
    func test05_ManyTogglesOnlyLatestRuns() async throws {
        let gate = DispatchSemaphore(value: 0), once = Once()
        defer { gate.signal() }
        try await stubbed({ _, p in p == "push/subscribe" && once.take() ? Reply.ok.held(gate) : .ok }) {
            shop.setUser(staff, staff: true)   // первая отправка, её «subscribe customer» задержан
            let held = try await until(10) { self.ops == ["subscribe customer"] }
            XCTAssertTrue(held, "Первая отправка не началась: \(ops)")
            shop.setUser(nil, staff: false); push.resend()
            shop.setUser(buyer, staff: false)
            shop.setUser(nil, staff: false); push.resend()
            shop.setUser(staff, staff: true)
            gate.signal()
            await drain()
            XCTAssertEqual(ops, ["subscribe customer", "subscribe customer", "subscribe staff"],
                           "Устаревшие отправки слали запросы или новая выполнилась не последней")
        }
    }

    /// Сбой сети в первом запросе не мешает второму, а следующая отправка проходит полностью
    func test06_NetworkErrorThenRecovery() async throws {
        let once = Once()
        try await stubbed({ _, p in p == "push/subscribe" && once.take() ? .fail(.notConnectedToInternet) : .ok }) {
            shop.setUser(staff, staff: true)
            await drain()
            XCTAssertEqual(ops, ["subscribe customer", "subscribe staff"])
            NetStub.clearSeen()
            push.resend()
            await drain()
            XCTAssertEqual(ops, ["subscribe customer", "subscribe staff"])
        }
    }

    /// Отменённая отправка оставшиеся запросы не шлёт
    func test07_CancelledStopsRemaining() async throws {
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        try await stubbed({ _, p in p == "push/subscribe" ? Reply.ok.held(gate) : .ok }) {
            shop.setUser(staff, staff: true)
            let held = try await until(10) { self.ops == ["subscribe customer"] }
            XCTAssertTrue(held, "Отправка не началась: \(ops)")
            push.sync?.cancel()
            gate.signal()
            await drain()
            XCTAssertEqual(ops, ["subscribe customer"], "После отмены отправка продолжила слать запросы")
        }
    }
}

private typealias Reply = NetStub.Reply
private extension NetStub.Reply { static let ok = NetStub.Reply.json(["ok": true]) }
