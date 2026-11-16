import XCTest
import Network

/// Аудит приложения на GitHub (только проверка, в приложение не входит).
/// Приложение собрано в Debug и ходит в копию магазина на этом же Mac (через посредника ci/audit-proxy.js),
/// поэтому заказы настоящие, но боевого сайта они не касаются. Каждый шаг — снимок экрана во вложениях.
final class AuditUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() { continueAfterFailure = true }
    override func tearDown() { ctl("on?scope=all") }

    // MARK: - помощники

    /// HTTP к посреднику напрямую через сокет (Network.framework): правила ATS на него не действуют
    @discardableResult
    func http(_ path: String) -> [String: Any] {
        var out: [String: Any] = [:]
        let sem = DispatchSemaphore(value: 0)
        let conn = NWConnection(host: "127.0.0.1", port: 3998, using: .tcp)
        var buf = Data()
        func receive() {
            conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { d, _, done, err in
                if let d { buf.append(d) }
                if done || err != nil { conn.cancel(); sem.signal() } else { receive() }
            }
        }
        conn.stateUpdateHandler = { st in
            switch st {
            case .ready:
                conn.send(content: "GET \(path) HTTP/1.0\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n".data(using: .utf8), completion: .contentProcessed { _ in receive() })
            case .failed, .cancelled: sem.signal()
            default: break
            }
        }
        conn.start(queue: .global())
        _ = sem.wait(timeout: .now() + 20)
        if let r = buf.range(of: Data("\r\n\r\n".utf8)), let j = try? JSONSerialization.jsonObject(with: buf[r.upperBound...]) as? [String: Any] { out = j }
        return out
    }
    @discardableResult func ctl(_ cmd: String) -> [String: Any] { http("/__ctl/" + cmd) }
    func ordersFor(_ phone: String) -> Int { (ctl("stats?phone=" + phone)["orders"] as? Int) ?? -1 }

    func launch(_ screen: String, fresh: Bool = false) {
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU", "-screen", screen]
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 30)
        sleep(4)
    }
    /// Пустая корзина перед тестом — через интерфейс, кнопкой «Удалить» (корзина хранится между запусками)
    func startClean() {
        launch("/cart")
        var n = 0
        while button("Удалить").waitForExistence(timeout: 3) && n < 12 { let b = button("Удалить"); scrollTo(b); b.tap(); sleep(1); n += 1 }
    }
    func shot(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    func note(_ text: String) {
        let a = XCTAttachment(string: text); a.name = "заметка"; a.lifetime = .keepAlways; add(a)
    }
    /// Кнопка по подписи. «−» и «+» у количества iOS называет «Удалить» и «Добавить» — их исключаем
    func button(_ label: String) -> XCUIElement {
        let notStepper = "NOT (identifier IN {'minus', 'plus'})"
        let exact = app.buttons.matching(NSPredicate(format: "label == %@ AND \(notStepper)", label)).firstMatch
        if exact.exists { return exact }
        return app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@ AND \(notStepper)", label)).firstMatch
    }
    /// Небольшая прокрутка (четверть экрана), чтобы элемент не оказался под закреплённой внизу кнопкой
    func nudge(up: Bool = true) {
        let w = app.windows.firstMatch
        let from = w.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.62 : 0.38))
        let to = w.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.38 : 0.62))
        from.press(forDuration: 0.05, thenDragTo: to)
    }
    /// Размер: прокрутить так, чтобы кнопка была над кнопкой «Добавить в корзину», и нажать
    func tapSize(_ size: String) -> Bool {
        let chip = app.buttons.matching(NSPredicate(format: "label == %@", size)).firstMatch
        guard chip.waitForExistence(timeout: 15) else { return false }
        let bar = button("в корзину")
        var n = 0
        while n < 10 {
            let top = bar.exists ? bar.frame.minY - 12 : app.windows.firstMatch.frame.maxY - 160
            if chip.frame.maxY < top && chip.frame.minY > 110 { break }
            nudge(up: chip.frame.maxY >= top); n += 1
        }
        chip.tap(); sleep(1); return true
    }
    func text(_ part: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", part)).firstMatch
    }
    func scrollTo(_ e: XCUIElement, max: Int = 14) {
        var n = 0
        while (!e.exists || !e.isHittable) && n < max { app.swipeUp(velocity: .slow); n += 1 }
        // Нажатие идёт в центр элемента: если центр под плавающей нижней панелью вкладок, палец попадёт во вкладку
        // («Корзина»), а не в элемент — поднимаем элемент выше панели (16.11, третий аудит)
        let bottom = app.windows.firstMatch.frame.maxY - 130
        var k = 0
        while e.exists && e.frame.midY > bottom && k < 4 { nudge(); k += 1 }
    }
    @discardableResult
    func tap(_ label: String, timeout: TimeInterval = 12) -> Bool {
        let b = button(label)
        if !b.waitForExistence(timeout: timeout) { scrollTo(b) }
        guard b.exists else { XCTFail("Нет кнопки «\(label)»"); return false }
        scrollTo(b); b.tap(); return true
    }
    func field(_ placeholder: String) -> XCUIElement {
        let p = NSPredicate(format: "placeholderValue == %@", placeholder)
        let t = app.textFields.matching(p).firstMatch
        return t.exists ? t : app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS %@", placeholder)).firstMatch
    }
    func type(_ placeholder: String, _ value: String) {
        let f = field(placeholder)
        if !f.waitForExistence(timeout: 8) { scrollTo(f) }
        guard f.exists else { XCTFail("Нет поля «\(placeholder)»"); return }
        scrollTo(f)
        // курсор — в конец поля, иначе стирание уберёт только часть старого текста
        f.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.5)).tap()
        if let v = f.value as? String, !v.isEmpty, v != placeholder {
            f.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: v.count + 2))
        }
        f.typeText(value)
        app.navigationBars.firstMatch.tap()   // убрать клавиатуру
    }
    func addToCart(product: String, size: String) {
        launch("/product/\(product)")
        XCTAssertTrue(tapSize(size), "Нет размера \(size)")
        tap("Добавить в корзину")
        sleep(1)
    }
    /// Оформление до кнопки «Подтвердить заказ»: самовывоз, оплата при получении, обе галочки
    func fillCheckout(phone: String, name: String = "Пётр", last: String = "Проверкин") {
        _ = text("Оформление").waitForExistence(timeout: 15)
        type("Иван", name); type("Иванов", last); type("+7 (___) ___-__-__", String(phone.dropFirst())); type("mail@example.ru", "audit\(phone.suffix(4))@example.com")
        let pickup = button("Самовывоз"); scrollTo(pickup); if pickup.exists { pickup.tap() }
        let cod = button("При получении"); scrollTo(cod); if cod.exists { cod.tap() }
        let offer = button("публичной оферты"); scrollTo(offer); if offer.exists { offer.tap() }
        let consent = button("согласие на обработку"); scrollTo(consent); if consent.exists { consent.tap() }
    }
    func waitOrderOpened(_ timeout: TimeInterval = 25) -> Bool {
        let p = NSPredicate(format: "label CONTAINS[c] 'Заказ №' OR label CONTAINS[c] 'Спасибо' OR label CONTAINS[c] 'оформлен'")
        return app.staticTexts.matching(p).firstMatch.waitForExistence(timeout: timeout)
    }

    // MARK: - 1. Карточка товара: без размера, нет в наличии, последняя штука

    func test01_ProductEdgeCases() {
        startClean()
        launch("/product/p1")
        shot("01 карточка товара")
        tap("Добавить в корзину")
        sleep(1)
        shot("01 добавить без размера")
        XCTAssertFalse(button("Уже в корзине").exists, "Товар без размера попал в корзину")
        // L — 0 шт.
        if tapSize("L") { shot("01 размер L — нет в наличии") }
        // XL — последняя штука
        XCTAssertTrue(tapSize("XL"))
        tap("Добавить в корзину"); sleep(1)
        shot("01 последняя штука в корзине")
        XCTAssertTrue(button("Уже в корзине").waitForExistence(timeout: 5), "После последней штуки нет «Уже в корзине · перейти»")
    }

    // MARK: - 2. Корзина: одинаковые товары, разные размеры, удаление

    func test02_Cart() {
        startClean()
        addToCart(product: "p6", size: "M")
        addToCart(product: "p6", size: "M")   // тот же товар ещё раз — должна вырасти строка, а не появиться вторая
        addToCart(product: "p6", size: "L")
        launch("/cart")
        shot("02 корзина: футболка M ×2 и L ×1")
        let mLines = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Размер: M' OR label CONTAINS '· M'")).count
        note("Строк с размером M: \(mLines)")
        let del = button("Удалить")
        if del.waitForExistence(timeout: 5) { del.tap(); sleep(1); shot("02 после удаления строки") }
        if button("Удалить").exists { button("Удалить").tap(); sleep(1) }
        shot("02 пустая корзина")
    }

    // MARK: - 3. Оформление: пустые поля, длинное имя с эмодзи, двойное нажатие «Подтвердить»

    func test03_CheckoutValidationAndDoubleTap() {
        let phone = "79070000031"
        startClean()
        addToCart(product: "p5", size: "M")
        launch("/checkout")
        shot("03 оформление")
        let offer = button("публичной оферты"); scrollTo(offer); offer.tap()
        let consent = button("согласие на обработку"); scrollTo(consent); consent.tap()
        let confirm = button("Подтвердить заказ"); scrollTo(confirm); confirm.tap(); sleep(2)
        shot("03 пустые поля — ошибка")
        XCTAssertTrue(app.buttons["Подтвердить заказ"].exists || button("Подтвердить").exists, "Пустая форма ушла дальше оформления")
        XCTAssertEqual(ordersFor(phone), 0)
        launch("/checkout")
        fillCheckout(phone: phone)
        let c = button("Подтвердить заказ"); scrollTo(c)
        shot("03 перед двойным нажатием")
        c.doubleTap()
        XCTAssertTrue(waitOrderOpened(), "После оформления не открылся заказ")
        shot("03 заказ оформлен")
        sleep(2)
        XCTAssertEqual(ordersFor(phone), 1, "Двойное нажатие создало не один заказ")
    }

    // MARK: - 4. Связь: обрыв, ответ потерян после оформления, 502 — и затем успешный заказ без дубля

    func test04_NetworkFailuresNoDuplicate() {
        let phone = "79070000041"
        startClean()
        addToCart(product: "p4", size: "S")
        launch("/checkout")
        fillCheckout(phone: phone)
        let c = button("Подтвердить заказ"); scrollTo(c)
        // а) нет связи
        ctl("off?scope=orders"); c.tap(); sleep(4)
        shot("04а нет связи")
        XCTAssertTrue(app.buttons["Подтвердить заказ"].exists, "После обрыва кнопка пропала или зависла")
        XCTAssertEqual(ordersFor(phone), 0)
        // б) магазин недоступен (502 от nginx)
        ctl("502?scope=orders"); scrollTo(c); c.tap(); sleep(4)
        shot("04б 502 Bad Gateway")
        XCTAssertEqual(ordersFor(phone), 0)
        // в) заказ создан, но ответ потерян — повторное нажатие не должно создать второй
        ctl("drop-after?scope=orders"); scrollTo(c); c.tap(); sleep(5)
        shot("04в ответ потерян после оформления")
        XCTAssertEqual(ordersFor(phone), 1, "Заказ должен был создаться на сервере")
        ctl("on?scope=all"); scrollTo(c)
        if c.exists { c.tap() }
        XCTAssertTrue(waitOrderOpened(), "После восстановления связи заказ не открылся")
        shot("04г связь восстановлена — открылся заказ")
        sleep(2)
        XCTAssertEqual(ordersFor(phone), 1, "Повтор после потерянного ответа создал второй заказ")
    }

    // MARK: - 5. Медленный интернет и много нажатий

    func test05_SlowNetworkManyTaps() {
        let phone = "79070000051"
        startClean()
        addToCart(product: "p2", size: "M")
        launch("/checkout")
        fillCheckout(phone: phone)
        let c = button("Подтвердить заказ"); scrollTo(c)
        ctl("slow?scope=orders&ms=5000")
        for _ in 0..<5 { if c.exists && c.isHittable { c.tap() } }
        sleep(1); shot("05 медленная связь — после 5 нажатий")
        XCTAssertTrue(waitOrderOpened(30))
        sleep(3)
        XCTAssertEqual(ordersFor(phone), 1, "Много нажатий на медленной связи создали не один заказ")
    }

    // MARK: - 6. Перезапуск: корзина и черновик оформления сохраняются

    func test06_RelaunchKeepsCartAndDraft() {
        startClean()
        addToCart(product: "p3", size: "S")
        launch("/checkout")
        type("Иван", "Черновик"); type("Иванов", "Сохранённый")
        sleep(1)
        app.terminate()
        launch("/checkout")
        shot("06 после перезапуска — оформление")
        let f = field("Иван")
        XCTAssertTrue(f.waitForExistence(timeout: 10))
        XCTAssertEqual(f.value as? String, "Черновик", "Имя в оформлении не сохранилось после перезапуска")
        launch("/cart")
        shot("06 после перезапуска — корзина")
        XCTAssertTrue(text("Джемпер").waitForExistence(timeout: 8), "Корзина пуста после перезапуска")
    }

    // MARK: - 7. Без интернета при запуске и восстановление

    func test07_OfflineLaunchAndRecovery() {
        ctl("off?scope=all")
        launch("/")
        sleep(25)
        shot("07 запуск без интернета")
        let retry = button("Повторить")
        XCTAssertTrue(retry.exists || text("соединен").exists || text("интернет").exists, "Без интернета нет понятного сообщения")
        ctl("on?scope=all")
        if retry.exists { retry.tap() }
        sleep(8)
        shot("07 связь вернулась")
    }

    // MARK: - 8. Поиск: обычный, регистр, пробелы, спецсимволы, эмодзи, пусто

    func test08_Search() {
        launch("/catalog")
        let s = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Поиск' OR label CONTAINS[c] 'Search' OR identifier CONTAINS[c] 'magnifyingglass'")).firstMatch
        guard s.waitForExistence(timeout: 10) else { XCTFail("Нет кнопки поиска"); shot("08 нет кнопки поиска"); return }
        s.tap()
        let q = app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS 'Название'")).firstMatch
        XCTAssertTrue(q.waitForExistence(timeout: 8))
        for (i, term) in ["пальто", "  ПАЛЬТО  ", "Футб", "<script>alert(1)</script>", "😀😀", "ыыыыыыы", String(repeating: "очень длинный запрос ", count: 8)].enumerated() {
            q.tap()
            if let v = q.value as? String, !v.isEmpty, !v.hasPrefix("Название") { q.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: v.count)) }
            q.typeText(term); sleep(2)
            shot("08 поиск \(i + 1): \(term.prefix(20))")
        }
    }

    // MARK: - 10. Нестандартные данные: длинное имя, эмодзи, апостроф, HTML, длинный комментарий

    func test10_SpecialInputs() {
        let phone = "79070000101"
        startClean()
        addToCart(product: "p6", size: "S")
        launch("/checkout")
        fillCheckout(phone: phone, name: "Александра-Виктория 👗 О'Коннор-Длинноимённая-Очень-Длинное-Имя-Для-Проверки", last: "Константинопольская-Задунайская <b>тест</b> & «кавычки»")
        let more = button("Добавить комментарий"); scrollTo(more)
        if more.exists { more.tap(); let area = app.textViews.firstMatch; if area.waitForExistence(timeout: 4) { area.tap(); area.typeText(String(repeating: "Позвоните заранее 📞 ", count: 12)); app.navigationBars.firstMatch.tap() } }
        shot("10 длинные и необычные данные")
        let c = button("Подтвердить заказ"); scrollTo(c); c.tap()
        let opened = waitOrderOpened(20)
        shot(opened ? "10 заказ с необычными данными" : "10 ответ на необычные данные")
        note(opened ? "Заказ оформлен" : "Заказ не оформлен — см. снимок с сообщением")
        XCTAssertEqual(app.state, .runningForeground, "Приложение закрылось")
        XCTAssertLessThanOrEqual(ordersFor(phone), 1)
    }

    // MARK: - 9. Навигация: быстрые переключения, назад

    func test09_FastNavigation() {
        launch("/product/p1")
        for path in ["/cart", "/catalog", "/account", "/", "/product/p2", "/checkout", "/gift", "/track"] {
            app.terminate(); launch(path); sleep(1)
        }
        shot("09 после быстрых переходов")
        launch("/product/p2")
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.exists { back.tap(); sleep(2) }
        shot("09 назад с карточки товара")
        XCTAssertEqual(app.state, .runningForeground, "Приложение закрылось")
    }
}
