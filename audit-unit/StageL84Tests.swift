import XCTest
@testable import Albakov

/// Этап L.8.4: стабильность приложения.
/// L8-09 — все виды «нет связи» дают APIError.offline (понятный текст и подсказка повтора на оформлении).
/// L8-12 — выход и удаление аккаунта отменяют запланированную отправку корзины и избранного: после выхода она не уходит.
/// Сеть не используется: ответы сервера подменяет NetStub (этап I)

// MARK: - L8-09

final class OfflineCodesTests: XCTestCase {
    private let api = NetStub.api()

    /// До L8-09 эти четыре ошибки URLSession показывали покупателю текст системы, а оформление — не подсказку повтора
    func test01_MoreNoConnectionCodesAreOffline() async throws {
        let codes: [URLError.Code] = [.dataNotAllowed, .internationalRoamingOff, .secureConnectionFailed, .cannotLoadFromNetwork]
        for code in codes {
            NetStub.reset { _, _ in .fail(code) }
            do {
                _ = try await api.raw("GET", "state"); XCTFail("\(code): нет ошибки")
            } catch let e as APIError {
                XCTAssertEqual(e.status, 0, "\(code)"); XCTAssertEqual(e.message, APIError.offline.message, "\(code)")
            } catch {
                XCTFail("\(code): ошибка не стала «нет связи» — \(error)")
            }
        }
        // связь вернулась — тот же запрос проходит: «нет связи» не остаётся в состоянии API
        NetStub.reset { _, _ in .json(["ok": true]) }
        let d = try await api.raw("GET", "state")
        XCTAssertFalse(d.isEmpty)
    }
}

// MARK: - L8-12

/// Shop.shared — витрина приложения-хоста: тесты подменяют ему API на NetStub и очищают покупателя, корзину, избранное
/// и записи на телефоне, а в конце возвращают прежние (как ShopStateTests этапа I)
@MainActor
final class LogoutSyncTests: XCTestCase {
    private var shop: Shop { Shop.shared }
    private let line = CartLine(productId: "p1", colorId: "c1", size: "M", qty: 2)
    private var keys: [String] { ["orderTokens", CheckoutView.draftStore, "cart", "favorites"] }

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
            shop.api = was.api   // отложенные отправки уже взяли NetStub — на сервер не уходят
        }
        try await body()
        await shop.cartSync?.value; await shop.favSync?.value
    }
    /// Отправки корзины и избранного, дошедшие до «сервера»
    private func puts() -> [String] { NetStub.seen.filter { $0.method == "PUT" }.map(\.path) }
    /// Вошёл покупатель u1; его вход не запланировал отправок (корзина и избранное пусты), журнал запросов чист
    private func signIn(_ id: String) async {
        shop.setUser(User(JSON(["id": id])), staff: false)
        await shop.cartSync?.value; await shop.favSync?.value
        NetStub.clearSeen()
    }

    /// Изменили корзину и избранное и сразу вышли, а сервер отвечает на выход дольше, чем ждёт отправка (0,8 с и 0,6 с).
    /// До L8-12 PUT me/cart и me/favorites уходили, пока ждали ответа на выход. После выхода и повторного входа
    /// отправки снова работают: отмена не ломает следующий сеанс
    func test01_SlowLogoutDoesNotSendPendingChanges() async throws {
        try await stubbed {
            await signIn("u1")
            let gate = DispatchSemaphore(value: 0)
            defer { gate.signal() }
            NetStub.reset { _, p in p == "auth/logout" ? NetStub.Reply.json(["ok": true]).held(gate) : .json(["ok": true]) }
            shop.cart = [line]; shop.toggleFavorite("p1")
            let out = Task { await shop.logout() }
            let asked = try await until { NetStub.paths().contains("auth/logout") }
            XCTAssertTrue(asked, "Запрос выхода не ушёл")
            try await Task.sleep(nanoseconds: 1_200_000_000)   // дольше обеих задержек отправки
            XCTAssertEqual(puts(), [], "Пока ждали ответа на выход, ушли отложенные отправки")
            gate.signal()
            await out.value
            await shop.cartSync?.value; await shop.favSync?.value
            XCTAssertNil(shop.user); XCTAssertEqual(shop.cart, []); XCTAssertEqual(shop.favorites, [])
            XCTAssertEqual(puts(), [], "После выхода ушли отложенные отправки")

            await signIn("u2")
            shop.cart = [line]
            await shop.cartSync?.value
            XCTAssertEqual(puts(), ["me/cart"], "После нового входа корзина не уходит в аккаунт")
            let put = NetStub.seen.last { $0.method == "PUT" && $0.path == "me/cart" }
            XCTAssertEqual(JSON(data: put?.body ?? Data())["lines"].array.compactMap(CartLine.init), [line])
        }
    }

    /// Сценарий из плана L.8: выход через 0,3 с после изменения корзины (ответ на выход сразу) — PUT не отправлен
    func test02_QuickLogoutDoesNotSendPendingChanges() async throws {
        try await stubbed {
            await signIn("u1")
            shop.cart = [line]; shop.toggleFavorite("p1")
            try await Task.sleep(nanoseconds: 300_000_000)
            await shop.logout()
            await shop.cartSync?.value; await shop.favSync?.value
            try await Task.sleep(nanoseconds: 1_000_000_000)   // отправка, если бы не отменилась, успела бы прийти
            XCTAssertEqual(puts(), [], "После выхода ушли отложенные отправки")
            XCTAssertTrue(NetStub.paths("POST").contains("auth/logout"))
        }
    }

    /// Удаление аккаунта: неверный пароль — покупатель остаётся, и его изменение корзины уходит в аккаунт, как раньше.
    /// Удаление прошло — запланированная отправка не уходит
    func test03_DeleteAccountCancelsOnlyOnSuccess() async throws {
        try await stubbed {
            await signIn("u1")
            NetStub.reset { _, p in p == "me/delete" ? .json(["ok": false, "error": "Неверный пароль"], status: 403) : .json(["ok": true]) }
            shop.cart = [line]
            do { try await shop.deleteAccount(password: "1"); XCTFail("Удаление с неверным паролем прошло") }
            catch let e as APIError { XCTAssertEqual(e.status, 403) }
            XCTAssertEqual(shop.user?.id, "u1")
            await shop.cartSync?.value
            XCTAssertEqual(puts(), ["me/cart"], "Неудачное удаление аккаунта отменило отправку корзины")

            NetStub.reset { _, _ in .json(["ok": true]) }
            NetStub.clearSeen()
            shop.toggleFavorite("p1")
            try await shop.deleteAccount(password: "1")
            await shop.cartSync?.value; await shop.favSync?.value
            try await Task.sleep(nanoseconds: 1_000_000_000)
            XCTAssertNil(shop.user)
            XCTAssertEqual(puts(), [], "После удаления аккаунта ушла отложенная отправка избранного")
        }
    }
}
