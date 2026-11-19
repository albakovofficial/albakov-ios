import XCTest
import UIKit
import ImageIO
import UniformTypeIdentifiers
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
    private func stubbed(_ reply: @escaping (String, String) -> NetStub.Reply = { _, _ in .ok },
                         _ body: () async throws -> Void) async throws {
        let ready = try await until(30) { Shop.shared.loaded || Shop.shared.loadError != nil }
        XCTAssertTrue(ready, "Хост не закончил первую загрузку витрины")
        let was = (api: shop.api, push: push.api, user: shop.user, staff: shop.isStaff, cart: shop.cart, favorites: shop.favorites)
        shop.api = NetStub.api(); push.api = NetStub.api()
        defer { shop.api = was.api; push.api = was.push }   // и если тест упал
        // подготовка — на обычных ответах: адрес устройства и первая отправка не должны забрать задержанный
        // или ошибочный ответ теста (иначе тест зависел бы от того, запускался ли до него другой)
        NetStub.reset { _, p in p == "state" ? stateReply() : .ok }
        shop.setUser(nil, staff: false)
        await shop.load()
        XCTAssertTrue(shop.loaded)
        if push.token == nil { push.didRegister(deviceToken: Data([0xAB, 0xCD, 0x01])) }
        await drain()
        NetStub.reset { m, p in p == "state" ? stateReply() : reply(m, p) }   // и журнал с чистого листа
        try await body()
        await drain()
        shop.setUser(was.user, staff: was.staff); shop.cart = was.cart; shop.favorites = was.favorites
        // отправки от теста и от восстановления (подписка, корзина, избранное) уходят в NetStub здесь, а не в следующий тест
        await drain(); await shop.cartSync?.value; await shop.favSync?.value
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

/// Этап K.1, K-L9: логотип с поворотом из EXIF. Снимок 300×200 записан «как снят»: красный угол — вверху слева
/// в файле, остальное синее; отметка поворота говорит, как его показывать. После обработки красный угол должен быть
/// там, где его видит человек, а стороны — повёрнуты для 5–8. Раньше поворот не применялся: при любой отметке
/// логотип выходил как в файле
final class LogoOrientationTests: XCTestCase {
    private func photo(orientation: Int) -> Data? {
        guard let ctx = CGContext(data: nil, width: 300, height: 200, bitsPerComponent: 8, bytesPerRow: 300 * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.setFillColor(UIColor.blue.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 200))
        ctx.setFillColor(UIColor.red.cgColor); ctx.fill(CGRect(x: 0, y: 140, width: 60, height: 60))   // верхний левый угол файла
        guard let img = ctx.makeImage() else { return nil }
        let out = NSMutableData()
        guard let dst = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dst, img, [kCGImageDestinationLossyCompressionQuality: 0.95, kCGImagePropertyOrientation: orientation] as CFDictionary)
        return CGImageDestinationFinalize(dst) ? out as Data : nil
    }
    /// В каком углу красный: «вверху слева», «вверху справа», «внизу слева», «внизу справа»
    private func redCorner(_ png: Data) -> (corner: String, w: Int, h: Int)? {
        guard let s = CGImageSourceCreateWithData(png as CFData, nil), let cg = CGImageSourceCreateImageAtIndex(s, 0, nil) else { return nil }
        let w = cg.width, h = cg.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue), let raw = ctx.data else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        let corners = withExtendedLifetime(ctx) { () -> [(String, Bool)] in
            let px = raw.bindMemory(to: UInt8.self, capacity: w * h * 4)
            func red(_ x: Int, _ fromTop: Int) -> Bool { let i = (fromTop * w + x) * 4; return px[i] > 180 && px[i + 2] < 80 }
            return [("вверху слева", red(15, 15)), ("вверху справа", red(w - 15, 15)), ("внизу слева", red(15, h - 15)), ("внизу справа", red(w - 15, h - 15))]
        }
        let hits = corners.filter { $0.1 }.map { $0.0 }
        return (hits.isEmpty ? "нигде" : hits.joined(separator: " + "), w, h)
    }
    private func check(_ orientation: Int, _ corner: String, _ size: [Int], line: UInt = #line) throws {
        let src = try XCTUnwrap(photo(orientation: orientation), "Нет исходника", line: line)
        let r = try LogoKit.process(src, removeBg: false, recolor: false)
        let got = try XCTUnwrap(redCorner(r.png), "PNG логотипа не читается", line: line)
        XCTAssertEqual([r.w, r.h], size, "EXIF \(orientation): размер логотипа", line: line)
        XCTAssertEqual([got.w, got.h], size, "EXIF \(orientation): размер PNG", line: line)
        XCTAssertEqual(got.corner, corner, "EXIF \(orientation): красный угол не на месте", line: line)
    }

    func test01_Normal() throws { try check(1, "вверху слева", [300, 200]) }
    func test02_Rotated90() throws { try check(6, "вверху справа", [200, 300]) }
    func test03_Rotated180() throws { try check(3, "внизу справа", [300, 200]) }
    func test04_Rotated270() throws { try check(8, "внизу слева", [200, 300]) }
    /// Зеркальные отметки (фронтальная камера, редакторы): 2 — по горизонтали, 4 — по вертикали, 5 и 7 — с поворотом
    func test05_Mirrored() throws {
        try check(2, "вверху справа", [300, 200])
        try check(4, "внизу слева", [300, 200])
        try check(5, "вверху слева", [200, 300])
        try check(7, "внизу справа", [200, 300])
    }
}
