import XCTest
@testable import Albakov

/// Этап L.12: оставшиеся пункты реестра L.8.
/// L8-11 — выход и удаление аккаунта стирают мерки, «Вы недавно смотрели» и ответ «мне есть 18» (решение владельца);
/// L8-13 — несколько 401 от панели подряд — одна перепроверка входа; L8-05 — потеря прав убирает экраны панели из стеков;
/// L8-10 — после окна оплаты статус перечитывается, пока заказ ждёт оплаты, но не бесконечно.
/// Сеть не используется: ответы сервера подменяет NetStub (этап I)

/// Shop.shared — витрина приложения-хоста: тесты подменяют ему API на NetStub и очищают покупателя и записи на телефоне,
/// а в конце возвращают прежние (как ShopStateTests этапа I и LogoutSyncTests этапа L.8.4)
@MainActor
final class DeviceDataLogoutTests: XCTestCase {
    private var shop: Shop { Shop.shared }
    private let adultKey = "ageCheck.adult"
    private var keys: [String] { ["orderTokens", DeviceData.checkoutDraft, DeviceData.fit, DeviceData.fitTick, "recent", adultKey, "cart", "favorites"] }

    private func stubbed(_ body: () async throws -> Void) async throws {
        let hostReady = try await until(30) { Shop.shared.loaded || Shop.shared.loadError != nil }
        XCTAssertTrue(hostReady, "Хост не закончил первую загрузку витрины")
        let was = (api: shop.api, user: shop.user, staff: shop.isStaff, cart: shop.cart, favorites: shop.favorites, recent: shop.recentIds)
        let d = UserDefaults.standard, saved = keys.map { d.object(forKey: $0) }
        shop.api = NetStub.api()
        NetStub.reset { _, _ in .json(["ok": true]) }
        shop.setUser(nil, staff: false); shop.cart = []; shop.favorites = []; shop.buyNow = nil; shop.clearRecent()
        for k in keys { d.removeObject(forKey: k) }
        NetStub.clearSeen()
        defer {
            shop.setUser(was.user, staff: was.staff); shop.cart = was.cart; shop.favorites = was.favorites; shop.buyNow = nil
            shop.clearRecent(); for id in was.recent.reversed() { shop.addRecent(id) }
            for (k, v) in zip(keys, saved) { d.set(v, forKey: k) }
            shop.api = was.api
        }
        try await body()
        await shop.cartSync?.value; await shop.favSync?.value
    }
    /// Покупатель на телефоне: мерки, два просмотренных товара, ответ «мне есть 18», черновик оформления
    private func fill() {
        shop.setUser(User(JSON(["id": "u1"])), staff: false)
        UserDefaults.standard.set(["h": 180.0, "kg": 76.0, "pref": "free", "w": 52.0], forKey: DeviceData.fit)
        shop.addRecent("p1"); shop.addRecent("p2")
        UserDefaults.standard.set(true, forKey: adultKey)
        UserDefaults.standard.set(["firstName": "Анна"], forKey: DeviceData.checkoutDraft)
    }
    private func assertCleared(_ step: String) {
        let d = UserDefaults.standard
        XCTAssertNil(d.object(forKey: DeviceData.fit), "\(step): мерки прежнего покупателя остались")
        XCTAssertEqual(shop.recentIds, [], "\(step): «Вы недавно смотрели» прежнего покупателя остались")
        XCTAssertNil(d.object(forKey: "recent"), "\(step): просмотренные товары остались в записи на телефоне")
        XCTAssertFalse(d.bool(forKey: adultKey), "\(step): ответ «мне есть 18» прежнего покупателя остался")
        XCTAssertNil(d.object(forKey: DeviceData.checkoutDraft), "\(step): черновик оформления остался")
    }

    /// До L8-11 выход стирал корзину, избранное, черновик и ключи заказов, но не мерки, просмотренное и «18+».
    /// Счётчик мерок меняется — экраны размера перечитывают пустые мерки
    func test01_LogoutClearsFitRecentAndAge() async throws {
        try await stubbed {
            fill()
            let tick = UserDefaults.standard.integer(forKey: DeviceData.fitTick)
            await shop.logout()
            XCTAssertNil(shop.user)
            assertCleared("Выход")
            XCTAssertNotEqual(UserDefaults.standard.integer(forKey: DeviceData.fitTick), tick, "Экраны размера не узнали, что мерки стёрты")
        }
    }

    /// Удаление аккаунта: неверный пароль — покупатель остаётся, его мерки и просмотренное на месте; удаление прошло — стёрто
    func test02_DeleteAccountClearsOnlyOnSuccess() async throws {
        try await stubbed {
            fill()
            NetStub.reset { _, p in p == "me/delete" ? .json(["ok": false, "error": "Неверный пароль"], status: 403) : .json(["ok": true]) }
            do { try await shop.deleteAccount(password: "1"); XCTFail("Удаление с неверным паролем прошло") }
            catch let e as APIError { XCTAssertEqual(e.status, 403) }
            XCTAssertEqual(shop.user?.id, "u1")
            XCTAssertNotNil(UserDefaults.standard.object(forKey: DeviceData.fit), "Неудачное удаление стёрло мерки")
            XCTAssertEqual(shop.recentIds, ["p2", "p1"])
            XCTAssertTrue(UserDefaults.standard.bool(forKey: adultKey))

            NetStub.reset { _, _ in .json(["ok": true]) }
            try await shop.deleteAccount(password: "1")
            XCTAssertNil(shop.user)
            assertCleared("Удаление аккаунта")
        }
    }

    /// Панель ответила 401 на три запроса подряд (сеанс сотрудника истёк): до L8-13 — три GET state, теперь — одна
    /// перепроверка. Права сняты — isStaff false. Следующий 401 после проверки запускает новую
    func test03_SeveralAdmin401OneRecheck() async throws {
        try await stubbed {
            shop.setUser(User(JSON(["id": "s1"])), staff: true)
            let gate = DispatchSemaphore(value: 0)
            defer { gate.signal() }
            NetStub.reset { _, p in
                p.hasPrefix("admin/") ? .json(["ok": false, "error": "Нет доступа"], status: 401)
                    : p == "state" ? stateReply(user: ["id": "s1"], staff: false).held(gate) : .json(["ok": true])
            }
            let api = NetStub.api()
            for _ in 0..<3 { _ = try? await api.raw("GET", "admin/data") }
            let asked = try await until { NetStub.paths("GET").contains("state") }
            XCTAssertTrue(asked, "Перепроверка входа не началась")
            try await Task.sleep(nanoseconds: 300_000_000)
            XCTAssertEqual(NetStub.paths("GET").filter { $0 == "state" }.count, 1, "На несколько 401 — несколько перепроверок")
            gate.signal()
            let done = try await until { !shop.isStaff }
            XCTAssertTrue(done, "После перепроверки права сотрудника не сняты")

            NetStub.reset { _, p in p.hasPrefix("admin/") ? .json(["ok": false], status: 401) : p == "state" ? stateReply(user: ["id": "s1"], staff: false) : .json(["ok": true]) }
            _ = try? await api.raw("GET", "admin/data")
            let again = try await until { NetStub.paths("GET").contains("state") }
            XCTAssertTrue(again, "401 после завершённой проверки не запустил новую")
        }
    }
}

/// L8-05: потеря прав (выход сотрудника, 401 панели) убирает из стеков экраны панели и всё, что открыто поверх них
@MainActor
final class CloseAdminTests: XCTestCase {
    func test01_AdminScreensLeaveStacks() {
        let r = Router()
        r.account = [.orders, .admin, .adminOrders, .adminOrder("o1")]
        r.home = [.product("p1")]
        r.catalog = [.admin, .adminProducts]
        r.closeAdmin()
        XCTAssertEqual(r.account, [.orders], "В кабинете остались экраны панели")
        XCTAssertEqual(r.catalog, [], "Во вкладке каталога остались экраны панели")
        XCTAssertEqual(r.home, [.product("p1")], "Стек без панели изменился")
        r.closeAdmin()
        XCTAssertEqual(r.account, [.orders], "Повторный вызов изменил стек")
    }
}

/// L8-10: после окна оплаты заказ перечитывается сразу и потом, пока ждёт оплаты, — не больше 4 повторов
@MainActor
final class AfterPaymentTests: XCTestCase {
    private var loads = 0
    private func load() async { loads += 1 }

    func test01_RereadsUntilPaidButNotForever() async {
        await afterPayment({ await self.load() }, step: .milliseconds(10)) { self.loads >= 3 }   // оплата дошла к третьему чтению
        XCTAssertEqual(loads, 3, "Чтения не прекратились после оплаты")

        loads = 0
        await afterPayment({ await self.load() }, step: .milliseconds(10)) { true }              // оплачено сразу
        XCTAssertEqual(loads, 1, "Оплаченный заказ перечитан лишний раз")

        loads = 0
        await afterPayment({ await self.load() }, step: .milliseconds(10)) { false }             // уведомление так и не пришло
        XCTAssertEqual(loads, 5, "Повторы не ограничены")
    }

    func test02_CancelledStops() async {
        loads = 0
        let t = Task { await afterPayment({ await self.load() }, step: .seconds(5)) { false } }
        try? await Task.sleep(nanoseconds: 200_000_000)
        t.cancel()
        await t.value
        XCTAssertEqual(loads, 1, "После отмены повторы продолжились")
    }
}
