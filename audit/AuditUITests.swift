import XCTest
import UIKit
import Network
import os

/// Аудит приложения на GitHub (только проверка, в приложение не входит).
/// Приложение собрано в Debug и ходит в копию магазина на этом же Mac (через посредника ci/audit-proxy.js),
/// поэтому заказы настоящие, но боевого сайта они не касаются. Каждый шаг — снимок экрана во вложениях.
/// Класс — на главном акторе: тесты работают с XCUIApplication и XCUIElement, а они в SDK изолированы на главном акторе
/// (XCTest и так вызывает синхронные тесты на главном потоке). Вне главного актора — только то, что интерфейса не касается:
/// setUp/tearDown (так они объявлены в XCTestCase) и HTTP к посреднику (этап L.2.15)
@MainActor
final class AuditUITests: XCTestCase {
    var app: XCUIApplication!

    nonisolated override func setUp() { continueAfterFailure = true }
    nonisolated override func tearDown() { ctl("on?scope=all") }

    // MARK: - помощники

    /// HTTP к посреднику напрямую через сокет (Network.framework): правила ATS на него не действуют.
    /// Тест ждёт ответа, держа свой поток на семафоре, поэтому обработчики соединения идут на очереди .global(), а не через
    /// главный актор (там они ждали бы освобождения главного потока, который ждёт их). Ответ они дописывают под замком
    @discardableResult
    nonisolated func http(_ path: String) -> [String: Any] {
        var out: [String: Any] = [:]
        let sem = DispatchSemaphore(value: 0)
        let conn = NWConnection(host: "127.0.0.1", port: 3998, using: .tcp)
        let received = OSAllocatedUnfairLock(initialState: Data())
        @Sendable func receive() {
            conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { d, _, done, err in
                if let d { received.withLock { $0.append(d) } }
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
        let buf = received.withLock { $0 }
        if let r = buf.range(of: Data("\r\n\r\n".utf8)) {
            // посредник передаёт заголовки магазина: большие ответы (витрина) идут частями — chunked (этап J)
            let chunked = String(decoding: buf[..<r.lowerBound], as: UTF8.self).lowercased().contains("transfer-encoding: chunked")
            let body = chunked ? dechunk(Data(buf[r.upperBound...])) : Data(buf[r.upperBound...])
            if let j = try? JSONSerialization.jsonObject(with: body) as? [String: Any] { out = j }
        }
        return out
    }
    /// Тело ответа, переданного частями: «размер в hex\r\nданные\r\n» … «0\r\n\r\n»
    nonisolated func dechunk(_ d: Data) -> Data {
        var out = Data(), i = d.startIndex
        let crlf = Data("\r\n".utf8)
        while let r = d.range(of: crlf, in: i..<d.endIndex),
              let n = Int(String(decoding: d[i..<r.lowerBound], as: UTF8.self).split(separator: ";").first ?? "", radix: 16), n > 0,
              r.upperBound + n <= d.endIndex {
            out.append(d[r.upperBound..<r.upperBound + n])
            i = min(d.endIndex, r.upperBound + n + 2)
        }
        return out
    }
    @discardableResult nonisolated func ctl(_ cmd: String) -> [String: Any] { http("/__ctl/" + cmd) }
    func ordersFor(_ phone: String) -> Int { (ctl("stats?phone=" + phone)["orders"] as? Int) ?? -1 }

    func launch(_ screen: String, fresh: Bool = false) {
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU", "-screen", screen]
        // Thread Sanitizer (audit.yml, tsan): приложение запускается с окружением только из launchEnvironment —
        // передаём ему настройки отчётов, иначе его отчёты о гонках никуда не попадут
        if let t = ProcessInfo.processInfo.environment["TSAN_OPTIONS"] { app.launchEnvironment["TSAN_OPTIONS"] = t }
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
        guard let f = erase(placeholder) else { return }
        f.typeText(value)
        app.navigationBars.firstMatch.tap()   // убрать клавиатуру
    }
    /// Стереть поле целиком; клавиатура остаётся открытой. nil — поля нет
    @discardableResult func erase(_ placeholder: String) -> XCUIElement? {
        let f = field(placeholder)
        if !f.waitForExistence(timeout: 8) { scrollTo(f) }
        guard f.exists else { XCTFail("Нет поля «\(placeholder)»"); return nil }
        scrollTo(f)
        // курсор — в конец поля, иначе стирание уберёт только часть старого текста
        f.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.5)).tap()
        if let v = f.value as? String, !v.isEmpty, v != placeholder {
            f.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: v.count + 2))
        }
        return f
    }
    /// Поля покупателя на оформлении. Черновик оформления хранится между запусками (так задумано в 1.0.3),
    /// поэтому тест, которому нужна пустая форма, сам её очищает и не зависит от предыдущих тестов
    static let customerFields = ["Иван", "Иванов", "+7 (___) ___-__-__", "mail@example.ru"]
    func clearCustomer() {
        for p in Self.customerFields {
            erase(p)
            app.navigationBars.firstMatch.tap()   // убрать клавиатуру: иначе следующее поле может оказаться под ней
        }
        for p in Self.customerFields {
            let v = field(p).value as? String ?? ""
            XCTAssertTrue(v.isEmpty || v == p || v.filter(\.isNumber).count <= 1, "Поле «\(p)» не очистилось: \(v)")
        }
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
    /// Ждёт конца отправки заказа: пока он отправляется, на кнопке индикатор вместо подписи «Подтвердить заказ».
    /// На симуляторе iOS 26.5 от нажатия до ответа магазина прошло ~6,7 с (test03; магазин отвечает сразу). До запроса
    /// приложение ждёт только системный ответ «нужна ли проверка возраста» (AgeRangeService, iOS 26.2+) — вероятная
    /// причина, отдельно не измерялась. Прежние фиксированные паузы (2–5 с) могли кончиться до отправки: проверка шла
    /// посреди неё, а режим посредника менялся раньше, чем запрос до него доходил.
    /// Сначала до 3 с ждём, что подпись сменилась индикатором (если отправка была мгновенной — просто пауза), затем — возврата подписи.
    @discardableResult func waitSendFinished(_ timeout: TimeInterval = 30) -> Bool {
        let b = app.buttons["Подтвердить заказ"]
        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: b)], timeout: 3)
        return b.waitForExistence(timeout: timeout)
    }
    func waitOrderOpened(_ timeout: TimeInterval = 25) -> Bool {
        // Только то, чего нет до создания заказа: заголовок экрана заказа «Заказ № …» или тост «…Заказ оформлен…».
        // Раньше подходило любое «оформлен» без учёта регистра — под него попадал заголовок самого экрана «Оформление»,
        // и ожидание заканчивалось сразу, ещё до ответа сервера (test05 на iOS 26.5: заказа ещё не было).
        let p = NSPredicate(format: "label BEGINSWITH 'Заказ № ' OR label CONTAINS 'Заказ оформлен'")
        return app.staticTexts.matching(p).firstMatch.waitForExistence(timeout: timeout)
    }
    /// Галочки оферты и согласия (они не сохраняются в черновике — их ставят заново на каждом экране оформления)
    func tickAgreements() {
        let offer = button("публичной оферты"); scrollTo(offer); if offer.exists { offer.tap() }
        let consent = button("согласие на обработку"); scrollTo(consent); if consent.exists { consent.tap() }
    }
    /// Вход владельцем копии магазина (аккаунт создаёт audit.yml; почта в копии не настроена — вход без кода).
    /// Сеанс хранится между запусками: если уже вошли, формы входа нет.
    /// Пароль — из секрета SHOP_TEST_PASSWORD (audit.yml передаёт его раннеру), в коде его нет (этап I.1)
    func signInOwner() {
        guard let password = ProcessInfo.processInfo.environment["SHOP_TEST_PASSWORD"], !password.isEmpty else {
            return XCTFail("Нет пароля владельца копии магазина: секрет SHOP_TEST_PASSWORD не передан тестам (audit.yml)")
        }
        launch("/account")
        let pw = app.secureTextFields.firstMatch
        if pw.waitForExistence(timeout: 8) {
            let login = app.textFields.firstMatch
            login.tap(); login.typeText("owner-audit@example.com")
            // Пароль: поле должно получить фокус, и в нём должно оказаться столько знаков, сколько в пароле (секретное поле показывает точки).
            // Пароль из цифр: в секретном поле открывается русская раскладка, латинские буквы XCUITest не набирает —
            // раньше вход молча не удавался, и тесты панели шли без входа (этап A.1, видео теста 11)
            var typed = false
            for _ in 1...3 where !typed {
                pw.tap()
                guard app.keyboards.firstMatch.waitForExistence(timeout: 5) else { continue }
                let had = (pw.value as? String)?.count ?? 0
                if had > 0 && had != password.count { pw.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: had + 2)) }
                if had != password.count { pw.typeText(password) }
                typed = (pw.value as? String)?.count == password.count
            }
            note("Пароль введён: \(typed)")
            tap("Войти"); sleep(5)   // у экрана входа нет панели навигации — клавиатуру не прячем, «Войти» ищем прокруткой
        }
        shot("вход владельца")
        XCTAssertFalse(app.secureTextFields.firstMatch.exists, "Вход владельцем не удался — проверка панели без входа недостоверна")
    }
    /// Выход на открытом экране кабинета — без перезапуска приложения (данные в памяти остаются, как у человека)
    func logoutFromAccount() {
        let out = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Выйти'")).firstMatch
        scrollTo(out)
        XCTAssertTrue(out.exists, "Нет строки «Выйти» в кабинете"); out.tap()
        // сначала дождаться окна подтверждения: иначе lastButton мог бы выбрать саму строку «Выйти» (ревью этапа F)
        _ = app.staticTexts.matching(NSPredicate(format: "label == 'Выйти из кабинета?'")).firstMatch.waitForExistence(timeout: 5)
        let yes = app.sheets.buttons["Выйти"].exists ? app.sheets.buttons["Выйти"] : lastButton(["Выйти"])
        XCTAssertTrue(yes.waitForExistence(timeout: 5), "Нет подтверждения выхода"); yes.tap(); sleep(3)
        XCTAssertTrue(app.secureTextFields.firstMatch.waitForExistence(timeout: 10), "После выхода не показан вход")
    }
    /// Ссылка albakov://… в приложение — запуск с этой ссылкой, как переход из push или письма
    func openLink(_ link: String) {
        guard let url = URL(string: link) else { return XCTFail("Неверная ссылка \(link)") }
        guard #available(iOS 16.4, *) else { return XCTFail("Открыть ссылку в приложении из теста можно с iOS 16.4") }
        // XCUIApplication.open перезапускает приложение с его launchArguments — убираем «-screen», иначе отладочный экран
        // из аргументов перекрыл бы ссылку. Запуск обычный, как из push: окна запуска закрывает waitClosingPrompts
        app.launchArguments = ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU"]
        app.open(url)
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "Приложение не открылось по ссылке")
        sleep(3)
    }
    /// Ждать условие, закрывая окна обычного запуска («Включите уведомления», «Вышло обновление») — к проверкам не относятся
    func waitClosingPrompts(_ timeout: TimeInterval, _ ready: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while !ready() {
            if Date() > end { return false }
            for b in ["Не сейчас", "Позже"] {
                let x = app.buttons.matching(NSPredicate(format: "label == %@", b)).firstMatch
                if x.exists { x.tap() }
            }
            sleep(1)
        }
        return true
    }
    /// Спрятать клавиатуру: тап по заголовку экрана, если он есть
    func hideKeyboard() { let nb = app.navigationBars.firstMatch; if nb.exists && nb.isHittable { nb.tap() } }
    /// Последняя кнопка из подходящих по подписи (нижняя строка списка)
    func lastButton(_ labels: [String]) -> XCUIElement {
        let q = app.buttons.matching(NSPredicate(format: "label IN %@", labels))
        return q.element(boundBy: max(0, q.count - 1))
    }
    /// Кнопка в той же строке, что и поле (✕ у строки размера), — не зависит от того, что ещё есть на экране
    func button(inRowOf field: XCUIElement, _ labels: [String]) -> XCUIElement? {
        let y = field.frame.midY
        return app.buttons.matching(NSPredicate(format: "label IN %@", labels)).allElementsBoundByIndex.first { abs($0.frame.midY - y) < 14 }
    }
    /// Ближайшая кнопка над полем (шапка карточки: ↑ ↓ ✕)
    func button(above field: XCUIElement, _ labels: [String]) -> XCUIElement? {
        let y = field.frame.minY
        return app.buttons.matching(NSPredicate(format: "label IN %@", labels)).allElementsBoundByIndex
            .filter { $0.frame.maxY <= y + 2 }.max { $0.frame.maxY < $1.frame.maxY }
    }
    /// Средняя яркость (0 — чёрный, 1 — белый) части снимка экрана: снимок — то, что видит человек, со всеми окнами.
    /// rect — в точках экрана приложения; screenWidth — ширина экрана в точках (app.frame: у самого раннера тестов
    /// UIScreen может быть в режиме совместимости с другой шириной — на этом ошибся прогон на iPhone SE); nil — весь снимок
    func luminance(_ image: UIImage, _ rect: CGRect? = nil, screenWidth: CGFloat = 0) -> Double? {
        guard var cg = image.cgImage else { return nil }
        if let r = rect {
            guard screenWidth > 0 else { return nil }
            let k = CGFloat(cg.width) / screenWidth   // пикселей снимка на точку экрана
            guard let c = cg.cropping(to: CGRect(x: r.minX * k, y: r.minY * k, width: r.width * k, height: r.height * k)) else { return nil }
            cg = c
        }
        guard let ctx = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue),
              let data = ctx.data else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 16, height: 16))
        return withExtendedLifetime(ctx) {   // буфер принадлежит контексту — контекст живёт, пока читаем
            let px = data.bindMemory(to: UInt8.self, capacity: 16 * 16 * 4)
            var sum = 0.0
            for i in stride(from: 0, to: 16 * 16 * 4, by: 4) { sum += 0.299 * Double(px[i]) + 0.587 * Double(px[i + 1]) + 0.114 * Double(px[i + 2]) }
            return sum / (16 * 16 * 255)
        }
    }
    /// Снимки экрана сразу после появления тоста: он виден ~2,4 с, а обращения к дереву элементов на CI медленные —
    /// поэтому сначала снимки (второй — после анимации появления); рамку тоста берёт catchToast из снимков дерева
    func toastShots() -> [XCUIScreenshot] {
        let first = XCUIScreen.main.screenshot(); usleep(400_000)
        return [first, XCUIScreen.main.screenshot()]
    }
    /// Дождаться тоста и сразу снять экран. Рамка — из того же снимка дерева элементов, в котором тост найден (snapshot()):
    /// на iOS 26.5 (Mac macos-26) каждый запрос к дереву идёт ~1 с, тост виден ~2,4 с, и отдельный запрос рамки после ожидания приходил,
    /// когда тост уже ушёл (этап E). nil — тоста не было за timeout
    func catchToast(_ toast: XCUIElement, _ timeout: TimeInterval) -> (frame: CGRect, shots: [XCUIScreenshot])? {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            // snapshot() бросает ошибку, пока тоста нет: это «ещё не появился», ждём дальше
            if let s = try? toast.snapshot() {
                let shots = toastShots()
                // тост и появляется, и уходит снизу: место, где он стоит, — самое верхнее из увиденных. Второй снимок дерева
                // поправляет рамку, снятую посреди появления; на iOS 26.5 он может попасть уже на уход — тогда остаётся первая
                let second = (try? toast.snapshot())?.frame ?? s.frame
                return (second.minY < s.frame.minY ? second : s.frame, shots)
            }
            usleep(200_000)
        }
        return nil
    }
    /// Тост виден человеку: место тоста на экране, пока он показан, заметно отличается от того же места, когда он ушёл.
    /// Не зависит от цветов и раздела магазина; если тост закрыт листом или клавиатурой, разницы нет
    func assertToastVisible(_ shots: [XCUIScreenshot], _ f: CGRect, _ toast: XCUIElement, _ what: String) {
        let w = app.frame.width
        let during = shots.compactMap { luminance($0.image, f, screenWidth: w) }.min()
        if let last = shots.last { let a = XCTAttachment(screenshot: last); a.name = "тост " + what; a.lifetime = .keepAlways; add(a) }
        XCTAssertTrue(waitGone(toast, 8), "Тост не ушёл")
        sleep(1)
        let after = luminance(XCUIScreen.main.screenshot().image, f, screenWidth: w)
        guard let d = during, let a = after else { XCTFail("Не удалось снять экран (\(what))"); return }
        note("Тост \(what): яркость его места \(d) с тостом и \(a) без него, рамка \(f), экран \(w) pt")
        XCTAssertGreaterThan(abs(a - d), 0.15, "Тост не виден (\(what)): яркость его места \(d) с тостом и \(a) без него")
    }
    /// Дождаться, что элемент пропал с экрана
    func waitGone(_ e: XCUIElement, _ timeout: TimeInterval) -> Bool {
        let x = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: e)
        return XCTWaiter.wait(for: [x], timeout: timeout) == .completed
    }
    /// Поставить курсор в конец поля и дописать текст; вернуть значение до правки
    @discardableResult func append(_ f: XCUIElement, _ text: String) -> String {
        let before = f.value as? String ?? ""
        f.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.5)).tap()
        f.typeText(text); hideKeyboard(); sleep(1)
        return before
    }
    /// Ждать, пока в обращении будет n фото и все они обработаны и отправлены. ok — так и вышло; text — чем кончилось
    /// ожидание (для заметки и текста ошибки). Каждое новое фото продлевает ожидание; без нового фото дольше stall секунд — сбой.
    /// «Идёт работа» — по доступности кнопок, а не по индикаторам: пока снимок читается и уменьшается, на миниатюрах
    /// индикатора нет (ревью этапа D). Пока фото меньше n, «Добавить фото» недоступна ровно тогда, когда идёт обработка
    /// или отправка (SupportViews: .disabled(att.left == 0 || att.busy), а left > 0). При n фото — «Отправить»:
    /// пока что-то отправляется, вместо подписи у неё индикатор и она недоступна.
    /// Работа уже шла и кончилась, а фото меньше n — часть фото потерялась: сбой (через 3 с простоя).
    /// Простой до начала работы не считается: окно выбора на медленном Mac может закрываться дольше
    func waitPhotos(_ photos: XCUIElementQuery, _ n: Int, addPhoto: XCUIElement, stall: TimeInterval) -> (ok: Bool, text: String) {
        let send = app.buttons.matching(NSPredicate(format: "label == 'Отправить'")).firstMatch
        let start = Date()
        var last = Date(), seen = -1, idleSince: Date?, started = false
        while true {
            let count = photos.count, t = Int(Date().timeIntervalSince(start))
            let busy = count < n ? !addPhoto.isEnabled : !(send.exists && send.isEnabled)
            if busy || count > 0 { started = true }
            if count != seen { seen = count; last = Date() }
            if count == n && !busy { return (true, "все \(n) фото за \(t) с") }
            if started && !busy && count < n {
                if let s = idleSince { if Date().timeIntervalSince(s) > 3 { return (false, "обработка закончилась, а фото \(count) из \(n) (\(t) с)") } }
                else { idleSince = Date() }
            } else { idleSince = nil }
            if Date().timeIntervalSince(last) > stall { return (false, "за \(Int(stall)) с без нового фото: \(count) из \(n), работа \(busy ? "идёт" : "стоит") (\(t) с)") }
            usleep(500_000)
        }
    }
    /// Выбрать n снимков, которые добавил audit.yml (пять больших ≈48 Мп), в системном окне выбора фото и подтвердить выбор.
    /// Свои снимки узнаём по подписи: у снимков этого года в ней нет года («Фотография, November 17, 6:15 PM»), у стандартных
    /// снимков симулятора есть («…, August 08, 2012, …»). Раньше брались последние по порядку — это были в основном стандартные
    /// снимки (по размерам отправок в журнале посредника), и проверка памяти на больших фото их не касалась (ревью этапа E).
    /// Окно разное на iOS 26.2 (Mac macos-15) и iOS 26.5 (macos-26): на 26.5 это отдельный процесс (каждый запрос к элементу ~1 с, снимки «не нажимаемые»),
    /// нижний ряд под плавающей панелью, подтверждение — «Готово». Поэтому рамки и подписи — из одного снимка дерева элементов,
    /// нажатие — в середину снимка, видимого целиком над нижней панелью. Проверяем: выбрано ровно n (отметки у снимков или
    /// счётчик окна), кнопка подтверждения доступна, окно после неё закрылось. false — не вышло (причина — в XCTFail)
    func pickPhotos(_ n: Int, _ step: String) -> Bool {
        let year = #"\b(19|20)\d{2}\b"#
        var snapError = ""
        // верх нижней панели окна выбора — по её подписи; снимки ниже него закрыты панелью.
        // Жёсткий запас от низа экрана не годится: на iPhone SE (iOS 26.2) он отсекал целиком видимый ряд (этап E)
        var barTop = app.frame.maxY - 100
        let barLabels = ["Выбрать фото", "Choose Photos", "Select Photos", "Показать выбранные", "Show Selected"]
        func cells() -> [XCUIElementSnapshot] {
            // snapshot() бросает ошибку, пока дерево недоступно (окно ещё открывается): это «пока снимков нет», пробуем снова;
            // последняя ошибка — в текст сбоя, если снимков так и не будет
            let root: XCUIElementSnapshot
            do { root = try app.snapshot() } catch { snapError = "\(error)"; return [] }
            var out: [XCUIElementSnapshot] = [], bar: CGFloat?
            func walk(_ e: XCUIElementSnapshot) {
                let l = e.label.lowercased()
                if e.elementType == .image, e.frame.width >= 60, e.frame.height >= 60, ["фото", "photo", "изображ"].contains(where: { l.contains($0) }) { out.append(e) }
                if barLabels.contains(where: { e.label.hasPrefix($0) }), e.frame.minY > app.frame.midY { bar = min(bar ?? .infinity, e.frame.minY - 16) }
                e.children.forEach(walk)
            }
            walk(root)
            if let bar { barTop = bar }
            return out
        }
        func ours(_ all: [XCUIElementSnapshot]) -> [XCUIElementSnapshot] { all.filter { $0.label.range(of: year, options: .regularExpression) == nil } }
        // окно выбора подгружает снимки не сразу; на медленном Mac (Intel, Thread Sanitizer) — дольше 20 с (этап E)
        let deadline = Date().addingTimeInterval(60)
        var all = cells()
        while ours(all).count < n && Date() < deadline { sleep(1); all = cells() }
        guard !all.isEmpty else { XCTFail("\(step): снимков в окне выбора не видно за 60 с" + (snapError.isEmpty ? "" : " (\(snapError))")); return false }
        // признак «без года» должен различать снимки: если года нет ни в одной подписи, свои от стандартных не отличить —
        // молча взять первые попавшиеся значило бы проверять не те фото
        guard all.contains(where: { $0.label.range(of: year, options: .regularExpression) != nil }) else {
            XCTFail("\(step): по подписям не отличить снимки audit.yml от стандартных: " + all.map { $0.label }.joined(separator: " | ")); return false
        }
        let usable = Array(ours(all).filter { $0.frame.minY >= 0 && $0.frame.maxY <= barTop }.prefix(n))
        note("\(step): снимков в окне \(all.count), своих \(ours(all).count), нижняя панель с \(Int(barTop)) pt; выбираем: " + usable.map { $0.label }.joined(separator: " | "))
        guard usable.count == n else { XCTFail("\(step): в окне выбора видно своих снимков \(usable.count) из \(n); подписи: " + all.map { $0.label }.joined(separator: " | ")); return false }
        let origin = app.coordinate(withNormalizedOffset: .zero)
        for c in usable { origin.withOffset(CGVector(dx: c.frame.midX, dy: c.frame.midY)).tap(); usleep(400_000) }
        let marked = cells().filter { $0.isSelected }, selected = marked.count
        // где отметки видны — все отмеченные должны быть своими (сетка могла сдвинуться после первого нажатия)
        guard ours(marked).count == marked.count else { XCTFail("\(step): отмечены не те снимки: " + marked.map { $0.label }.joined(separator: " | ")); return false }
        let counter = app.descendants(matching: .any).matching(NSPredicate(format: "label MATCHES %@",
            ".*(\\(\(n)\\)|[Вв]ыбран[оаы]*:? \(n)\\b|\\b\(n) (фото |снимк[аов]* )?выбран|[Ss]elected:? \(n)\\b|\\b\(n) ([Pp]hotos? )?[Ss]elected).*")).firstMatch
        let counted = selected == n || counter.exists
        note("\(step): отмечено снимков \(selected), счётчик окна: \(counter.exists ? counter.label : "нет")")
        shot("\(step) выбрано \(n) фото")
        guard counted else { XCTFail("\(step): не видно, что выбрано ровно \(n) (отмечено \(selected), счётчика нет)"); return false }
        let done = app.buttons.matching(NSPredicate(format: "label IN %@", ["Добавить", "Add", "Готово", "Done"])).firstMatch
        guard done.waitForExistence(timeout: 5), done.isEnabled else { XCTFail("\(step): кнопка подтверждения выбора \(done.exists ? "недоступна" : "не найдена")"); return false }
        if done.isHittable { done.tap() } else { done.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
        guard waitGone(done, 10) else { XCTFail("\(step): окно выбора фото не закрылось после подтверждения"); return false }
        return true
    }
    /// Отметка времени для замера памяти: audit.yml пишет память приложения раз в полсекунды и считает пик между отметками
    func mark(_ label: String) {
        let s = "MEMMARK \(label) \(Int(Date().timeIntervalSince1970))"
        print(s); note(s)
    }

    // MARK: - 0. IOS-01: первый заказ на телефоне — обрыв, повторное открытие оформления, повтор — без второго заказа
    // Идёт первым (имена тестов — по алфавиту): в свежем симуляторе ещё не было ни одного заказа,
    // поэтому ключ повтора заказа ещё не сохранён — ровно случай из аудита.

    func test00_FirstOrderReopenRetryNoDuplicate() {
        let phone = "79070000001"
        startClean()
        addToCart(product: "p5", size: "L")
        launch("/checkout")
        fillCheckout(phone: phone)
        let c = button("Подтвердить заказ"); scrollTo(c)
        // а) первый запуск оформления, обрыв связи — заказ не дошёл
        ctl("off?scope=orders"); c.tap()
        XCTAssertTrue(waitSendFinished(), "После обрыва кнопка пропала или зависла")
        shot("00а первое оформление — обрыв связи")
        XCTAssertEqual(ordersFor(phone), 0)
        ctl("on?scope=all")
        // б) повторное открытие экрана в том же запуске: назад в корзину и снова «Оформить заказ»
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.exists { back.tap(); sleep(2) }
        tap("Оформить заказ"); sleep(3)
        shot("00б оформление открыто заново")
        XCTAssertEqual(field("Иван").value as? String, "Пётр", "Черновик не восстановился — данные заказа будут другими")
        tickAgreements()
        // в) заказ создан, а ответ потерян
        let c2 = button("Подтвердить заказ"); scrollTo(c2)
        ctl("drop-after?scope=orders"); c2.tap()
        XCTAssertTrue(waitSendFinished(), "После потерянного ответа кнопка пропала или зависла")
        shot("00в ответ потерян")
        XCTAssertEqual(ordersFor(phone), 1, "Заказ должен был создаться на сервере")
        ctl("on?scope=all")
        // г) приложение закрыли и открыли оформление снова — повторная отправка
        app.terminate()
        launch("/checkout")
        tickAgreements()
        let c3 = button("Подтвердить заказ"); scrollTo(c3)
        shot("00г после перезапуска — перед повтором")
        c3.tap()
        // д) успешный ответ: открылся тот же заказ, второго нет
        XCTAssertTrue(waitOrderOpened(), "После повтора заказ не открылся")
        shot("00д заказ открыт")
        sleep(2)
        XCTAssertEqual(ordersFor(phone), 1, "Повтор после обрыва и повторного открытия создал второй заказ")
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
        addToCart(product: "p6", size: "M")   // тот же товар и размер ещё раз — должна вырасти строка, а не появиться вторая
        launch("/cart")
        // одна строка: одна кнопка «Удалить» и одна подпись «Размер: M»; в ней количество 2 (рядом с «−» у этой строки),
        // и итог корзины — за 2 вещи (этап H, T-2: раньше тест проверял только, что нажатия прошли)
        let lines = app.buttons.matching(NSPredicate(format: "label == 'Удалить' AND NOT (identifier IN {'minus', 'plus'})"))
        XCTAssertTrue(lines.firstMatch.waitForExistence(timeout: 10), "Корзина пуста после двух добавлений")
        XCTAssertEqual(lines.count, 1, "Тот же товар и размер добавился второй строкой")
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Размер: M'")).count, 1, "Строк с размером M не одна")
        let minus = app.buttons["Уменьшить количество"]
        XCTAssertTrue(minus.waitForExistence(timeout: 5), "У строки нет «−» для количества больше 1 — количество не выросло")
        let qty = app.staticTexts.matching(NSPredicate(format: "label == '2'")).allElementsBoundByIndex.first { abs($0.frame.midY - minus.frame.midY) < 12 }
        XCTAssertNotNil(qty, "В строке корзины количество не 2")
        XCTAssertTrue(text("2 товара").waitForExistence(timeout: 15), "Итог корзины посчитан не за 2 вещи")
        shot("02 корзина: одна строка M × 2")
        // удаление строки: строка исчезла, корзина пустая
        lines.firstMatch.tap(); sleep(1)
        XCTAssertTrue(text("В корзине пока пусто").waitForExistence(timeout: 10), "После удаления корзина не пустая")
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Размер: M'")).count, 0, "Удалённая строка осталась на экране")
        XCTAssertEqual(lines.count, 0, "После удаления осталась кнопка «Удалить»")
        shot("02 пустая корзина")
    }

    // MARK: - 3. Оформление: пустые поля, длинное имя с эмодзи, двойное нажатие «Подтвердить»

    func test03_CheckoutValidationAndDoubleTap() {
        let phone = "79070000031"
        startClean()
        addToCart(product: "p5", size: "M")
        launch("/checkout")
        _ = text("Оформление").waitForExistence(timeout: 15)
        clearCustomer()   // форма пустая, даже если раньше оформляли заказ (черновик)
        shot("03 оформление — пустая форма")
        let offer = button("публичной оферты"); scrollTo(offer); offer.tap()
        let consent = button("согласие на обработку"); scrollTo(consent); consent.tap()
        let confirm = button("Подтвердить заказ"); scrollTo(confirm); confirm.tap()
        let back = waitSendFinished()   // на iOS 26.5 от нажатия до ответа магазина прошло ~6,7 с, прежние «2 с» проверяли середину отправки
        shot("03 пустые поля — ошибка")
        XCTAssertTrue(back || button("Подтвердить").exists, "Пустая форма ушла дальше оформления")
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
        ctl("off?scope=orders"); c.tap()
        XCTAssertTrue(waitSendFinished(), "После обрыва кнопка пропала или зависла")
        shot("04а нет связи")
        XCTAssertEqual(ordersFor(phone), 0)
        // б) магазин недоступен (502 от nginx)
        ctl("502?scope=orders"); scrollTo(c); c.tap()
        XCTAssertTrue(waitSendFinished(), "После ответа 502 кнопка пропала или зависла")
        shot("04б 502 Bad Gateway")
        XCTAssertEqual(ordersFor(phone), 0)
        // в) заказ создан, но ответ потерян — повторное нажатие не должно создать второй
        ctl("drop-after?scope=orders"); scrollTo(c); c.tap()
        XCTAssertTrue(waitSendFinished(), "После потерянного ответа кнопка пропала или зависла")
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

    // MARK: - 11. IOS-04: панель — удаление строки списка, пока поле этой строки в фокусе (ничего не сохраняем)

    func test11_AdminRowsDeleteWhileEditing() {
        signInOwner()
        launch("/admin?s=menu")
        XCTAssertTrue(text("Социальные сети").waitForExistence(timeout: 25), "Раздел «Меню, контакты, соцсети» не открылся")
        let del = ["Удалить строку", "Закрыть", "Close", "xmark"]
        for round in 1...3 {
            // новая строка в последнем списке (соцсети), курсор — в её последнем поле, клавиатура открыта
            let add = lastButton(["Добавить"]); scrollTo(add)
            guard add.exists else { XCTFail("Нет кнопки «Добавить»"); return }
            add.tap(); sleep(1)
            let fields = app.textFields
            let f = fields.element(boundBy: fields.count - 1); scrollTo(f)
            f.tap(); f.typeText("Проверка \(round)")
            shot("11.\(round) поле новой строки в фокусе")
            let x = lastButton(del)
            if x.isHittable { x.tap() } else { x.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
            sleep(1)
            XCTAssertEqual(app.state, .runningForeground, "Панель закрылась после удаления строки (круг \(round))")
            // правка соседней (теперь последней) строки
            let n = app.textFields
            let g = n.element(boundBy: n.count - 1); scrollTo(g)
            if g.exists { g.tap(); g.typeText("!"); hideKeyboard() }
            sleep(1)
            shot("11.\(round) после удаления и правки соседней строки")
            XCTAssertEqual(app.state, .runningForeground, "Панель закрылась при правке соседней строки (круг \(round))")
            XCTAssertFalse(app.textFields.matching(NSPredicate(format: "value == %@", "Проверка \(round)")).firstMatch.exists, "Удалённая строка осталась на экране")
        }
        app.terminate()   // выходим без сохранения
    }

    // MARK: - 12. IOS-05: панель — удаление упаковки СДЭК, пока её поле в фокусе (ничего не сохраняем)

    func test12_AdminPacksDeleteWhileEditing() {
        signInOwner()
        launch("/admin?s=payment")
        let add = button("Добавить упаковку")
        scrollTo(add, max: 30)
        guard add.waitForExistence(timeout: 20) else { XCTFail("Нет кнопки «+ Добавить упаковку»"); shot("12 нет упаковок"); return }
        let del = ["Удалить упаковку", "Закрыть", "Close", "xmark"]
        for (round, placeholder) in [(1, "Название"), (2, "0")] {
            scrollTo(add); add.tap(); sleep(1)
            // поле новой (последней) упаковки: название или вес
            let fs = app.textFields.matching(NSPredicate(format: "placeholderValue == %@", placeholder))
            let f = fs.element(boundBy: fs.count - 1); scrollTo(f)
            f.tap(); f.typeText(placeholder == "0" ? "777" : "Проверка")
            shot("12.\(round) поле новой упаковки в фокусе")
            let x = lastButton(del)
            if x.isHittable { x.tap() } else { x.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
            sleep(1)
            XCTAssertEqual(app.state, .runningForeground, "Панель закрылась после удаления упаковки (круг \(round))")
            // правка соседней упаковки: название и вес
            let names = app.textFields.matching(NSPredicate(format: "placeholderValue == %@", "Название"))
            let n = names.element(boundBy: names.count - 1)
            if n.exists { scrollTo(n); n.tap(); n.typeText(" 2") }
            let ws = app.textFields.matching(NSPredicate(format: "placeholderValue == %@", "0"))
            let w = ws.element(boundBy: ws.count - 1)
            if w.exists { scrollTo(w); w.tap(); w.typeText("5") }
            hideKeyboard(); sleep(1)
            shot("12.\(round) после удаления и правки соседней упаковки")
            XCTAssertEqual(app.state, .runningForeground, "Панель закрылась при правке соседней упаковки (круг \(round))")
        }
        app.terminate()   // выходим без сохранения
    }

    // MARK: - 13. IOS-03: пять больших фото (≈48 Мп) в обращение в поддержку; память — в mem-summary.txt

    func test13_FiveLargePhotosInSupport() {
        signInOwner()
        launch("/account?tab=support")
        XCTAssertTrue(tap("Написать в поддержку"))
        let addPhoto = button("Добавить фото")
        guard addPhoto.waitForExistence(timeout: 12) else { XCTFail("Нет кнопки «Добавить фото»"); shot("13 нет кнопки фото"); return }
        mark("photos-start")
        addPhoto.tap(); sleep(5)
        shot("13 окно выбора фото")
        // системное окно выбора: последние 5 снимков — те, что audit.yml добавил в «Фото» симулятора
        guard pickPhotos(5, "13") else { return }
        let removes = app.buttons.matching(NSPredicate(format: "label == 'Убрать фото'"))
        // Ждём событие, а не время (этап D): все 5 фото в обращении, обработка и отправка закончились (см. waitPhotos).
        // Пока фото появляются, ждём дальше; без нового фото дольше 90 с — сбой (на медленном Mac этапа C одно фото шло ~57 с).
        // Обработка кончилась, а фото меньше 5 — часть потерялась: падаем сразу, с числом
        let waited = waitPhotos(removes, 5, addPhoto: addPhoto, stall: 90)
        note("13: \(waited.text)")
        mark("photos-loaded")
        shot("13 пять фото в обращении")
        XCTAssertTrue(waited.ok, "Фото в обращении не готовы: \(waited.text)")
        XCTAssertEqual(removes.count, 5, "В обращении не 5 фото: \(waited.text)")
        XCTAssertEqual(app.state, .runningForeground, "Приложение закрылось при добавлении 5 больших фото")
        // убрать все фото, затем закрыть окно — память должна вернуться
        var k = 0
        while removes.count > 0 && k < 8 { removes.firstMatch.tap(); usleep(500_000); k += 1 }
        sleep(4)
        mark("photos-removed")
        shot("13 фото убраны")
        XCTAssertEqual(removes.count, 0)
        tap("Закрыть"); sleep(5)
        mark("sheet-closed")
        XCTAssertEqual(app.state, .runningForeground, "Приложение закрылось")
    }

    // MARK: - 14. Q-2: панель — размеры товара и способы доставки: удаление при активном поле, правка соседних (ничего не сохраняем)

    func test14_AdminSizesAndDeliveryDelete() {
        signInOwner()
        launch("/admin?s=products&id=p1")
        XCTAssertTrue(text("Цвета, фото и остатки").waitForExistence(timeout: 25), "Карточка товара не открылась")
        let del = ["Удалить", "Удалить строку", "Закрыть", "Close", "xmark"]
        let sizes = app.textFields.matching(NSPredicate(format: "placeholderValue == %@", "Размер"))
        func size(_ v: String) -> XCUIElement { app.textFields.matching(NSPredicate(format: "value == %@", v)).firstMatch }
        // Три новых размера (только кириллица — раскладка русская): ЦА, ЦБ, ЦВ. Курсор — в среднем, удаляем верхний.
        // Это проверка «удаление и правка в панели работают» на интерфейсе. Сам дефект строк по номеру (поле, оставшееся
        // в фокусе, привязывается к соседней строке) через интерфейс не воспроизводится: касание ✕ снимает фокус
        // (KeyboardDismisser). Его ловят модельные тесты RowKeysTests (test01, test02)
        for _ in 1...3 {
            let plus = lastButton(["+ Размер"]); scrollTo(plus)
            guard plus.exists else { XCTFail("Нет кнопки «+ Размер»"); return }
            plus.tap(); sleep(1)
        }
        for (k, v) in [(3, "ЦА"), (2, "ЦБ"), (1, "ЦВ")] {
            let f = sizes.element(boundBy: sizes.count - k); scrollTo(f)
            f.tap(); f.typeText(v); hideKeyboard()
        }
        let mid = size("ЦБ"); scrollTo(mid)
        mid.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.5)).tap()   // курсор в среднем размере, клавиатура открыта
        shot("14.1 три новых размера, курсор в среднем")
        guard let x = button(inRowOf: size("ЦА"), del) else { XCTFail("Нет кнопки удаления размера"); return }
        if x.isHittable { x.tap() } else { x.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
        sleep(1)
        XCTAssertEqual(app.state, .runningForeground, "Панель закрылась после удаления размера")
        XCTAssertFalse(size("ЦА").exists, "Удалённый размер остался на экране")
        XCTAssertTrue(size("ЦБ").exists && size("ЦВ").exists, "Соседние размеры пропали или изменились")
        // Нажатие ✕ закрывает клавиатуру (так устроено приложение: касание вне поля — KeyboardDismisser), поэтому
        // правка среднего размера — новым касанием в него: она должна попасть именно в него, нижний — не меняться
        append(size("ЦБ"), "Ж")
        XCTAssertTrue(size("ЦБЖ").exists, "Ввод ушёл не в средний размер")
        XCTAssertTrue(size("ЦВ").exists, "Нижний размер изменился — правка ушла в чужую строку")
        shot("14.1 после удаления верхнего размера и правки среднего")
        launch("/admin?s=payment")
        let addPickup = button("+ Самовывоз"); scrollTo(addPickup, max: 30)
        guard addPickup.waitForExistence(timeout: 20) else { XCTFail("Нет кнопки «+ Самовывоз»"); return }
        addPickup.tap(); sleep(1); scrollTo(addPickup); addPickup.tap(); sleep(1)
        let descs = app.textFields.matching(NSPredicate(format: "placeholderValue == %@", "Например, 1–2 дня, с примеркой"))
        let names = app.textFields.matching(NSPredicate(format: "placeholderValue == %@", "Например, Курьер по Москве"))
        func desc(_ v: String) -> XCUIElement { app.textFields.matching(NSPredicate(format: "value == %@", v)).firstMatch }
        let up = descs.element(boundBy: descs.count - 2); scrollTo(up)
        up.tap(); up.typeText("ПЕРВЫЙ"); hideKeyboard()
        let low = descs.element(boundBy: descs.count - 1); scrollTo(low)
        low.tap(); low.typeText("ВТОРОЙ")
        shot("14.2 два новых способа доставки, курсор в нижнем")
        let upName = names.element(boundBy: names.count - 2); scrollTo(upName)
        guard let x2 = button(above: upName, del) else { XCTFail("Нет кнопки удаления способа доставки"); return }
        x2.tap()
        let yes = app.sheets.buttons["Удалить"].exists ? app.sheets.buttons["Удалить"] : app.buttons.matching(NSPredicate(format: "label == 'Удалить'")).firstMatch
        XCTAssertTrue(yes.waitForExistence(timeout: 5), "Нет подтверждения удаления"); yes.tap(); sleep(1)
        XCTAssertEqual(app.state, .runningForeground, "Панель закрылась после удаления способа доставки")
        XCTAssertFalse(desc("ПЕРВЫЙ").exists, "Удалённый способ остался на экране")
        XCTAssertTrue(desc("ВТОРОЙ").exists, "Соседний способ доставки пропал или изменился")
        let g = desc("ВТОРОЙ"); scrollTo(g)
        append(g, "Ж")
        shot("14.2 после удаления верхнего способа и правки нижнего")
        XCTAssertTrue(desc("ВТОРОЙЖ").exists, "Правка ушла не в соседний способ доставки")
        app.terminate()   // выходим без сохранения
    }

    // MARK: - 15. Q-3, Q-4: ошибки сети видны — на экране с «Повторить», в корзине вместо «0 ₽», поверх открытого листа

    func test15_NetworkErrorsVisible() {
        signInOwner()
        // а) список обращений не загрузился — не пустой экран, а причина и «Повторить»
        ctl("off?scope=support")
        launch("/account?tab=support")
        let failed = text("Не удалось загрузить")
        XCTAssertTrue(failed.waitForExistence(timeout: 25), "Ошибка загрузки обращений не показана")
        shot("15а обращения — нет связи")
        ctl("on?scope=all")
        tap("Повторить")
        XCTAssertTrue(waitGone(failed, 20), "После «Повторить» ошибка не ушла")
        shot("15а обращения — после «Повторить»")
        // б) корзина: сумма не посчиталась — «—» и причина, а не «0 ₽»
        startClean()
        addToCart(product: "p5", size: "M")
        ctl("off?scope=quote")
        launch("/cart")
        let qErr = text("Не удалось посчитать сумму")
        XCTAssertTrue(qErr.waitForExistence(timeout: 25), "Ошибка расчёта суммы не показана")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '0' AND label CONTAINS '₽'")).firstMatch.exists, "В корзине показано «0 ₽»")
        shot("15б корзина — сумма не посчиталась")
        ctl("on?scope=all")
        tap("Посчитать ещё раз")
        XCTAssertTrue(waitGone(qErr, 20), "После «Посчитать ещё раз» ошибка не ушла")
        shot("15б корзина — сумма посчитана")
        // в) сообщение об ошибке поверх открытого листа: фото в обращении не отправилось
        launch("/account?tab=support")
        XCTAssertTrue(tap("Написать в поддержку"))
        let addPhoto = button("Добавить фото")
        guard addPhoto.waitForExistence(timeout: 12) else { XCTFail("Нет кнопки «Добавить фото»"); return }
        ctl("off?scope=support/upload")
        addPhoto.tap(); sleep(5)
        guard pickPhotos(1, "15в") else { return }
        let toast = text("Нет соединения")
        // большое фото (≈48 Мп из теста 13) в симуляторе читается и уменьшается до ~40 с — ждём до минуты
        guard let caught = catchToast(toast, 60) else { XCTFail("Сообщение об ошибке отправки фото не показано"); return }
        // exists верно и для закрытого другим окном элемента — сравниваем место тоста на экране с ним и без него
        assertToastVisible(caught.shots, caught.frame, toast, "поверх листа")
        XCTAssertTrue(button("Добавить фото").exists, "Лист обращения закрылся — проверка не поверх листа")
        ctl("on?scope=all")
        tap("Закрыть")
        // г) тост при открытой клавиатуре: ответ в переписке не отправился — сообщение не прячется под клавиатурой
        XCTAssertTrue(tap("Написать в поддержку"))
        // многострочный TextField(axis: .vertical) в XCUITest — textField, а не textView: ищем по подсказке
        let body = field("Что случилось и чем помочь")
        guard body.waitForExistence(timeout: 10) else { XCTFail("Нет поля сообщения"); return }
        scrollTo(body); body.tap(); body.typeText("Проверка сообщений"); hideKeyboard()
        XCTAssertTrue(tap("Отправить"))
        let composer = field("Сообщение")
        guard composer.waitForExistence(timeout: 20) else { XCTFail("Переписка не открылась"); return }
        sleep(2); composer.tap(); composer.typeText("Ещё вопрос")
        ctl("off?scope=support&ms=4000")   // обрыв через 4 с: ошибка придёт, когда клавиатура уже снова открыта
        let send = app.buttons.matching(NSPredicate(format: "label == 'Отправить'")).firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 5), "Нет кнопки «Отправить»"); send.tap()
        // касание кнопки закрывает клавиатуру (KeyboardDismisser) — открываем её снова касанием в поле.
        // У заполненного поля XCUITest не отдаёт подсказку — ищем поле по введённому тексту
        let filled = app.textFields.matching(NSPredicate(format: "value CONTAINS %@", "вопрос")).firstMatch
        XCTAssertTrue(filled.waitForExistence(timeout: 3), "Поле ответа не найдено"); filled.tap()
        let toast2 = text("Нет соединения"), kb = app.keyboards.firstMatch
        XCTAssertTrue(kb.waitForExistence(timeout: 5), "Клавиатура не открылась — проверка не при открытой клавиатуре")
        guard let caught2 = catchToast(toast2, 20) else { XCTFail("Сообщение об ошибке отправки ответа не показано"); return }
        let tf = caught2.frame, kf = kb.frame
        XCTAssertLessThanOrEqual(tf.maxY, kf.minY + 1, "Тост под клавиатурой: \(tf) / \(kf)")
        assertToastVisible(caught2.shots, tf, toast2, "при открытой клавиатуре")
        ctl("on?scope=all")
    }

    // MARK: - 16. Этап C (Q-B1): сбои загрузки в панели и на странице товара — причина и «Повторить», а не пустота

    func test16_AdminLoadErrorsVisible() {
        signInOwner()
        // а) журнал действий: раньше — пустой список, как будто записей нет
        ctl("off?scope=admin/audit")
        launch("/admin?s=audit")
        let failed = text("Не удалось загрузить")
        XCTAssertTrue(failed.waitForExistence(timeout: 25), "Ошибка загрузки журнала не показана")
        shot("16а журнал — нет связи")
        ctl("on?scope=all")
        tap("Повторить")
        XCTAssertTrue(waitGone(failed, 20), "После «Повторить» ошибка журнала не ушла")
        XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 10), "После «Повторить» записей журнала нет (вход владельца в нём есть всегда)")
        shot("16а журнал — после «Повторить»")
        // б) состояние ключа ЮKassa: раньше строка состояния молча пропадала (ключ не меняется — запрос без тела)
        ctl("off?scope=admin/payment-secret")
        launch("/admin?s=payment")
        let keyErr = text("Не удалось узнать, сохранён ли ключ")
        if !keyErr.waitForExistence(timeout: 25) { scrollTo(keyErr, max: 10) }
        XCTAssertTrue(keyErr.exists, "Ошибка состояния ключа не показана")
        scrollTo(keyErr)
        shot("16б ключ оплаты — нет связи")
        ctl("on?scope=all")
        tap("Повторить")
        XCTAssertTrue(waitGone(keyErr, 20), "После «Повторить» ошибка ключа не ушла")
        let keyState = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Ключ не задан' OR label CONTAINS 'ключ ('")).firstMatch
        XCTAssertTrue(keyState.waitForExistence(timeout: 10), "Состояние ключа не показано после «Повторить»")
        shot("16б ключ оплаты — после «Повторить»")
        // в) настройки → состояние магазина: раньше — вечная загрузка
        ctl("off?scope=admin/order-seq")
        launch("/admin?s=settings")
        let state = text("Состояние магазина")
        scrollTo(state, max: 30)
        let stateErr = text("Нет соединения")
        if !stateErr.waitForExistence(timeout: 20) { scrollTo(stateErr, max: 6) }
        XCTAssertTrue(stateErr.exists, "Ошибка загрузки состояния магазина не показана")
        shot("16в состояние магазина — нет связи")
        ctl("on?scope=all")
        tap("Повторить")
        XCTAssertTrue(text("База данных").waitForExistence(timeout: 20), "После «Повторить» состояние магазина не загрузилось")
        shot("16в состояние магазина — после «Повторить»")
        // г) срок доставки на странице товара: раньше при сбое оставались сроки прежнего города.
        // Блок есть всегда: в копии магазина есть способ «СДЭК, пункт выдачи»
        ctl("off?scope=cdek/estimate")
        launch("/product/p5")
        let shipErr = text("Срок доставки не загрузился")
        if !shipErr.waitForExistence(timeout: 20) { scrollTo(shipErr, max: 12) }
        XCTAssertTrue(shipErr.exists, "Ошибка срока доставки не показана")
        shot("16г срок доставки — нет связи")
        ctl("on?scope=all")
        tap("Повторить")
        // ошибка убирается в начале загрузки, ещё до ответа: ждём, пока загрузка закончится, и проверяем, что ошибка не вернулась
        let spinner = app.activityIndicators.firstMatch
        if spinner.exists { _ = waitGone(spinner, 20) }
        sleep(3)
        XCTAssertFalse(shipErr.exists, "После «Повторить» ошибка срока доставки осталась или вернулась")
        shot("16г срок доставки — после «Повторить»")
        // д) массовые изменения по прямой ссылке (L8-03): раньше при сбое загрузки данных панели — пустой список
        // «Выбрать все (0)» без причины и без повтора. Повтор, пока связи нет, ошибку не убирает; после восстановления —
        // загружает товары. Второй запуск: то же через «потянуть вниз». Элементы ищутся заново после каждого запуска
        func all() -> XCUIElement { app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Выбрать все ('")).firstMatch }
        func goods() -> Int { Int(all().label.filter(\.isNumber)) ?? 0 }
        ctl("off?scope=admin/data")
        launch("/admin?s=productsBulk")
        var bulkErr = text("Не удалось загрузить")
        XCTAssertTrue(bulkErr.waitForExistence(timeout: 25), "Ошибка загрузки данных панели в массовых изменениях не показана")
        shot("16д массовые изменения — нет связи")
        tap("Повторить")
        sleep(3)
        XCTAssertTrue(bulkErr.exists, "Повтор без связи убрал ошибку, хотя данные не загрузились")
        XCTAssertEqual(goods(), 0, "Без связи в массовых изменениях появились товары")
        ctl("on?scope=all")
        tap("Повторить")
        XCTAssertTrue(waitGone(bulkErr, 20), "После «Повторить» ошибка массовых изменений не ушла")
        XCTAssertTrue(all().waitForExistence(timeout: 10), "Список массовых изменений не показан")
        XCTAssertGreaterThan(goods(), 0, "После «Повторить» товаров нет: \(all().label)")
        shot("16д массовые изменения — после «Повторить»")
        ctl("off?scope=admin/data")
        launch("/admin?s=productsBulk")
        bulkErr = text("Не удалось загрузить")
        XCTAssertTrue(bulkErr.waitForExistence(timeout: 25), "Ошибка загрузки данных панели не показана (второй запуск)")
        ctl("on?scope=all")
        // потянуть вниз от строк списка, ниже карточки ошибки: нажатие на «Повторить» здесь не должно случиться
        let w = app.windows.firstMatch
        w.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)).press(forDuration: 0.05, thenDragTo: w.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
        XCTAssertTrue(waitGone(bulkErr, 20), "Потянуть вниз — ошибка массовых изменений не ушла")
        XCTAssertGreaterThan(goods(), 0, "Потянуть вниз — товаров нет: \(all().label)")
        shot("16д массовые изменения — после «потянуть вниз»")
        ctl("on?scope=all")
    }

    // MARK: - 17. Выход из кабинета: данные покупателя не остаются на телефоне (этап F, F-1)

    /// Раньше после выхода корзина, избранное, черновик оформления (имя, телефон, почта, адрес) и ключи заказов оставались:
    /// следующий, кто входил на этом iPhone, получал их в свой аккаунт, видел чужие данные в оформлении и чужие заказы.
    /// Корзина в аккаунте при этом должна сохраниться — очищается только телефон, как на сайте
    func test17_LogoutClearsPersonalData() {
        let phone = "79070000171"
        signInOwner()
        startClean()                                   // корзина владельца пуста и на телефоне, и в аккаунте
        // заказ из кабинета: его ключ сохраняется на телефоне (OrderTokens), контакты — в черновике оформления
        addToCart(product: "p2", size: "M")
        launch("/checkout")
        fillCheckout(phone: phone)
        shot("17а оформление владельца заполнено")
        let c = button("Подтвердить заказ"); scrollTo(c); c.tap()
        XCTAssertTrue(waitOrderOpened(), "Заказ владельца не оформился")
        addToCart(product: "p2", size: "M"); sleep(2)  // корзина аккаунта (сохранение на сервер — через 0,8 с)
        // выход
        launch("/account")
        logoutFromAccount()
        // после выхода (и перезапуска) корзина пуста, а в оформлении гостя нет данных владельца
        launch("/cart")
        XCTAssertTrue(text("В корзине пока пусто").waitForExistence(timeout: 10), "После выхода в корзине остались вещи аккаунта")
        shot("17б корзина после выхода")
        // «Мои заказы» гостя: заказ прежнего покупателя (с его именем, телефоном, адресом) не виден
        launch("/account?tab=orders")
        XCTAssertTrue(text("У Вас пока нет заказов").waitForExistence(timeout: 20), "После выхода гостю видны заказы прежнего покупателя")
        shot("17б2 заказы гостя после выхода")
        addToCart(product: "p4", size: "S")
        launch("/checkout")
        _ = text("Оформление").waitForExistence(timeout: 15)
        shot("17в оформление гостя после выхода")
        for p in Self.customerFields {
            let v = field(p).value as? String ?? ""
            XCTAssertTrue(v.isEmpty || v == p, "После выхода в поле «\(p)» остались данные прежнего покупателя: \(v)")
        }
        // снова вход: корзина аккаунта на месте (p2) и объединилась с корзиной гостя (p4) — две строки
        signInOwner()
        launch("/cart")
        let lines = app.buttons.matching(NSPredicate(format: "label == 'Удалить' AND NOT (identifier IN {'minus', 'plus'})"))
        _ = lines.firstMatch.waitForExistence(timeout: 10)
        shot("17г корзина после повторного входа")
        XCTAssertEqual(lines.count, 2, "Корзина аккаунта не сохранилась на сервере или не объединилась с корзиной гостя")
        startClean()
    }

    // MARK: - 18–19. Панель после выхода сотрудника и при запуске по ссылке (этап H, SEC-1)

    /// Раньше экраны панели открывались по ссылке или старому уведомлению сотрудника и после выхода. Теперь после выхода
    /// ссылка в панель даёт «Нет доступа» без заказов и покупателей. openLink перезапускает приложение, поэтому стирание
    /// данных в памяти того же процесса проверяет юнит-тест AdminOwnerTests
    func test18_StaffLogoutAdminLinkShowsNoData() {
        let last = "Покупатель-Восемнадцать"
        signInOwner()
        startClean()
        addToCart(product: "p6", size: "M")
        launch("/checkout")
        fillCheckout(phone: "79070000181", name: "Секрет", last: last)
        let c = button("Подтвердить заказ"); scrollTo(c); c.tap()
        XCTAssertTrue(waitOrderOpened(), "Заказ не оформился")
        // панель у сотрудника: список заказов загружен, новый заказ с фамилией покупателя виден.
        // XCUIApplication.open перезапускает приложение (как переход из push), поэтому прежние данные в памяти здесь
        // не проверить — это делает юнит-тест AdminOwnerTests; здесь — что ссылка после выхода не открывает панель
        openLink("albakov://admin?s=orders")
        let list = app.segmentedControls.buttons["В работе"]
        XCTAssertTrue(waitClosingPrompts(40) { list.exists && text(last).exists }, "В списке заказов панели нет нового заказа — проверка после выхода была бы пустой")
        shot("18а заказы в панели у сотрудника")
        openLink("albakov://account")
        _ = waitClosingPrompts(10) { false }   // окна запуска появляются в первые секунды — закрыть до прокрутки к «Выйти»
        logoutFromAccount()
        // ссылка в панель после выхода — как старое уведомление сотрудника
        openLink("albakov://admin?s=orders")
        XCTAssertTrue(waitClosingPrompts(30) { text("Нет доступа").exists }, "После выхода ссылка открыла панель без прав")
        shot("18б ссылка в панель после выхода")
        XCTAssertFalse(text(last).exists, "После выхода видны данные покупателя из панели")
        XCTAssertFalse(app.segmentedControls.buttons["В работе"].exists, "После выхода открылся список заказов панели")
    }

    /// Холодный запуск ссылкой в панель: ссылка приходит раньше, чем загружена витрина и известно, что вошёл сотрудник.
    /// Сотрудник должен попасть в панель, а не получить отказ (нажатие на push идёт тем же путём — Router.open)
    func test19_StaffColdStartAdminLink() {
        // заказ с фамилией, которую покажет только ответ admin/data: «Заказов нет» или пустой список тест не примет
        let last = "Покупатель-Девятнадцать"
        signInOwner()
        startClean()
        addToCart(product: "p6", size: "M")
        launch("/checkout")
        fillCheckout(phone: "79070000191", name: "Холодный", last: last)
        let c = button("Подтвердить заказ"); scrollTo(c); c.tap()
        XCTAssertTrue(waitOrderOpened(), "Заказ не оформился")
        app.terminate()
        openLink("albakov://admin?s=orders")
        let list = app.segmentedControls.buttons["В работе"]
        _ = waitClosingPrompts(60) { list.exists && text(last).exists }
        XCTAssertTrue(list.exists, "Сотрудник не попал в список заказов панели при запуске по ссылке")
        XCTAssertFalse(text("Нет доступа").exists, "Сотруднику показан отказ в доступе")
        XCTAssertTrue(text(last).exists, "В панели нет заказа сотрудника — данные admin/data не загрузились")
        shot("19 запуск по ссылке — заказы панели")
    }

    // MARK: - 20. Этап J, M-1: несколько фото цвета товара — все прикреплены, лишних загрузок нет; замер фото (DEF-1)

    /// Фото, загруженные в панели, по данным посредника (ci/audit-proxy.js): адрес, код ответа, байты, размеры, время
    func uploads() -> [[String: Any]] { (ctl("uploads")["uploads"] as? [[String: Any]]) ?? [] }
    /// Фото первого цвета товара — по данным витрины копии магазина
    func colorImages(_ product: String) -> [String] {
        let products = ((http("/api/state")["data"] as? [String: Any])?["products"] as? [[String: Any]]) ?? []
        let colors = products.first { $0["id"] as? String == product }?["colors"] as? [[String: Any]]
        return colors?.first?["images"] as? [String] ?? []
    }

    func test20_ColorPhotosAllAttached() {
        signInOwner()
        let before = colorImages("p1"), sent = uploads().count
        launch("/admin?s=products&id=p1")
        XCTAssertTrue(text("Цвета, фото и остатки").waitForExistence(timeout: 25), "Карточка товара не открылась")
        let add = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Фото этого цвета'")).firstMatch
        scrollTo(add)
        guard add.exists else { XCTFail("Нет кнопки «Фото этого цвета»"); shot("20 нет кнопки фото"); return }
        mark("color-photos-start")
        add.tap(); sleep(3)
        guard pickPhotos(3, "20") else { return }
        // загрузка идёт по одному фото; ждём три ответа сервера (большие снимки, медленный Mac — с запасом)
        let deadline = Date().addingTimeInterval(240)
        while uploads().count < sent + 3 && Date() < deadline { sleep(2) }
        sleep(3)
        mark("color-photos-loaded")
        let mine = Array(uploads().dropFirst(sent))
        let shotImage = XCUIScreen.main.screenshot().image
        let scale = (shotImage.size.width * shotImage.scale / app.frame.width).rounded()   // пиксели снимка экрана на точку
        for u in mine {
            let line = "DEF1 фото цвета: код \(u["status"] ?? "?"), JPEG \(u["bytes"] ?? 0) Б, \(u["w"] ?? 0)×\(u["h"] ?? 0) px, \(u["ms"] ?? 0) мс; масштаб экрана \(scale)"
            print(line); note(line)
        }
        shot("20 три фото цвета")
        XCTAssertEqual(mine.count, 3, "Загрузок не 3 — лишние или потерянные: \(mine)")
        XCTAssertTrue(mine.allSatisfy { $0["status"] as? Int == 200 }, "Не все фото приняты сервером: \(mine)")
        // DEF-1 (этап J.1): на сервер уходит не крупнее 2000 px по длинной стороне и не больше 8 МБ — на любом экране
        for u in mine {
            let w = u["w"] as? Int ?? 0, h = u["h"] as? Int ?? 0, bytes = u["bytes"] as? Int ?? 0
            XCTAssertTrue(max(w, h) > 0 && max(w, h) <= 2000, "Фото \(w)×\(h) px — больше 2000 по длинной стороне")
            XCTAssertLessThanOrEqual(bytes, 8 * 1024 * 1024, "Фото \(bytes) Б — больше предела сервера 8 МБ")
        }
        let urls = mine.compactMap { $0["url"] as? String }
        let save = button("Сохранить")
        scrollTo(save)
        guard save.exists else { XCTFail("Нет кнопки «Сохранить»"); return }
        save.tap()
        // у цвета — прежние фото и все три новых по порядку; ни одно загруженное не осталось «ничьим»
        var after: [String] = []
        let saved = Date().addingTimeInterval(30)
        repeat { sleep(2); after = colorImages("p1") } while after == before && Date() < saved
        shot("20 товар сохранён")
        XCTAssertEqual(after, before + urls, "У цвета не все выбранные фото: было \(before.count), загружено \(urls.count), стало \(after.count) — \(after)")
        XCTAssertEqual(uploads().count, sent + 3, "После сохранения появились лишние загрузки")
    }

    // MARK: - 21. Этап J, M-2: сумма возврата — для текущего выбора; пока сумма пересчитывается, вернуть деньги нельзя

    func test21_RefundSumFollowsSelection() {
        // заказ «Возврат Проверкин» (две вещи, M и S) создан и помечен оплаченным онлайн в audit.yml
        guard let id = ProcessInfo.processInfo.environment["AUDIT_REFUND_ORDER"], !id.isEmpty else {
            return XCTFail("Нет заказа для проверки возврата: audit.yml не передал AUDIT_REFUND_ORDER")
        }
        signInOwner()
        launch("/admin?s=orders&id=\(id)")
        let open = button("Вернуть деньги")
        if !open.waitForExistence(timeout: 25) { scrollTo(open) }
        guard open.exists else {
            XCTFail("Нет кнопки «Вернуть деньги» — заказ не оплачен онлайн?"); shot("21 нет возврата"); return
        }
        scrollTo(open); open.tap(); sleep(1)
        let m = app.switches.matching(NSPredicate(format: "label CONTAINS 'размер M'")).firstMatch
        let s = app.switches.matching(NSPredicate(format: "label CONTAINS 'размер S'")).firstMatch
        // кнопка возврата: «Выберите позиции», «Вернуть N ₽» или «Подтвердить возврат N ₽» — на экране вместе с позициями
        let pay = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "((Вернуть|Подтвердить возврат) [0-9].*|Выберите позиции)")).firstMatch
        // Позиции M и S и кнопка возврата — вместе, между навигацией и панелью вкладок. Короткие сдвиги без инерции
        // (палец держится в конце жеста) в сторону, которую показывает фактическое положение элементов, не больше
        // 16 шагов. Этап K.2: раньше свайпы только вверх с инерцией докатывали список дальше — кнопка оказывалась
        // на экране, а позиции уходили за его верх, и тест падал «позиции и кнопка не видны вместе»
        let win = app.windows.firstMatch.frame
        let top = win.minY + 70, bottom = win.maxY - 90
        func drag(up: Bool, by f: CGFloat) {
            let w = app.windows.firstMatch
            let from = w.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.5 + f : 0.5))
            let to = w.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.5 : 0.5 + f))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        var k = 0, step: CGFloat = 0.12, last: Bool?
        while k < 16 {
            let shown = [m, s, pay].allSatisfy { $0.exists && $0.isHittable }
            if shown && m.frame.minY >= top && pay.frame.maxY <= bottom { break }
            // позиции видны или ещё ниже — листаем дальше вниз по странице; ушли за верх (или их уже нет, а кнопка
            // на экране) — назад. Сменили направление — шаг вдвое меньше, чтобы не качаться между двумя положениями
            let up = !(m.exists ? m.frame.minY < top : (pay.exists && pay.frame.maxY <= bottom))
            if let last, last != up { step = max(step / 2, 0.03) }
            drag(up: up, by: step); last = up
            k += 1
        }
        note("21: позиции и кнопка возврата — шагов \(k) из 16")
        shot("21 позиции и кнопка возврата")
        guard m.exists, s.exists, m.isHittable, s.isHittable, pay.exists else {
            XCTFail("Позиции заказа и кнопка возврата не видны вместе"); shot("21 нет позиций"); return
        }
        func rub() -> Int { Int(pay.label.filter(\.isNumber)) ?? 0 }
        func flip(_ sw: XCUIElement) {
            let was = sw.value as? String
            sw.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            let changed = NSPredicate(format: "value != %@", was ?? "")
            XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: changed, evaluatedWith: sw)], timeout: 3), .completed, "Переключатель не сработал")
        }
        let path = "admin/orders/\(id)/refund"
        func delayed() -> Int { ctl("stats")["delayed"] as? Int ?? -1 }

        // 1) ответ на прежний выбор (только M) приходит позже ответа на новый (M и S) — сумма остаётся для M и S
        let d0 = delayed()
        ctl("slow-once?scope=\(path)&ms=6000")
        flip(m); usleep(500_000); flip(s)
        let quoted = Date().addingTimeInterval(5)
        while rub() == 0 && Date() < quoted { usleep(200_000) }
        let both = rub()
        XCTAssertGreaterThan(both, 0, "Нет суммы возврата за две позиции")
        sleep(8)   // опоздавший ответ уже пришёл
        shot("21 после опоздавшего ответа")
        XCTAssertEqual(rub(), both, "Опоздавший ответ на прежний выбор заменил сумму возврата: была \(both), стала \(rub())")
        XCTAssertEqual(delayed(), d0 + 1, "Посредник не задержал ответ — проверка опоздавшего ответа ничего не проверила")

        // 2) выбор изменился, ответ ещё в пути — прежняя сумма не должна уйти на подтверждение
        let shown = rub()
        ctl("slow-once?scope=\(path)&ms=6000")
        flip(m); usleep(700_000)
        shot("21 сумма пересчитывается")
        XCTAssertFalse(pay.isEnabled && rub() == shown, "Пока сумма пересчитывается, доступна кнопка с прежней суммой \(shown)")
        let deadline = Date().addingTimeInterval(12)
        while (!pay.isEnabled || rub() == shown) && Date() < deadline { usleep(300_000) }
        let single = rub()
        XCTAssertEqual(delayed(), d0 + 2, "Посредник не задержал второй пересчёт — проверка кнопки ничего не проверила")
        note("21: за две позиции \(both) ₽, за одну \(single) ₽")
        XCTAssertTrue(single > 0 && single < both, "Сумма за одну позицию не пересчиталась: \(single) (за две — \(both))")
    }

    /// K-M2 (этап K.1): после удаления товара файл остатков выгружается заново. Раньше кнопка «Поделиться файлом
    /// остатков» продолжала отдавать файл, выгруженный до удаления, — с уже удалённым товаром.
    /// Удаляется p10 «Сумка-тоут из кожи» копии магазина: другие тесты его не используют, тест идёт последним
    func test22_StockFileRefreshedAfterDelete() {
        signInOwner()
        // как сотрудник: из списка товаров (он загружает данные панели) — экран массовых изменений сам их не загружает
        launch("/admin?s=products")
        let tools = button("Массовые изменения и остатки в Excel")
        guard tools.waitForExistence(timeout: 25) else { XCTFail("Список товаров панели не открылся"); shot("22 нет товаров панели"); return }
        tools.tap()
        let export = button("Выгрузить остатки")
        let share = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Поделиться файлом остатков'")).firstMatch
        guard export.waitForExistence(timeout: 25) else { XCTFail("Экран массовых изменений не открылся"); shot("22 нет экрана"); return }
        export.tap()
        XCTAssertTrue(share.waitForExistence(timeout: 25), "Файл остатков не выгрузился"); shot("22 файл выгружен")
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Сумка-тоут из кожи'")).firstMatch
        scrollTo(row)
        guard row.exists else { XCTFail("Нет товара «Сумка-тоут из кожи» в списке"); shot("22 нет товара"); return }
        row.tap()
        let del = button("Удалить выбранные")
        var n = 0
        while !del.isHittable && n < 14 { app.swipeDown(velocity: .slow); n += 1 }
        del.tap()
        let confirm = app.buttons.matching(NSPredicate(format: "label == 'Удалить'")).firstMatch
        guard confirm.waitForExistence(timeout: 10) else { XCTFail("Нет подтверждения удаления"); shot("22 нет подтверждения"); return }
        confirm.tap()
        n = 0
        while !export.exists && n < 14 { app.swipeDown(velocity: .slow); n += 1 }
        XCTAssertTrue(export.waitForExistence(timeout: 25), "После удаления товара осталась кнопка прежнего файла, а не «Выгрузить остатки»")
        XCTAssertFalse(share.exists, "После удаления товара предлагается прежний файл остатков")
        shot("22 после удаления")
        // выгрузить заново — новый файл с сервера, уже без удалённого товара
        export.tap()
        XCTAssertTrue(share.waitForExistence(timeout: 25), "Файл остатков не выгрузился заново")
        let left = (http("/api/state")["data"] as? [String: Any])?["products"] as? [[String: Any]] ?? []
        XCTAssertFalse(left.isEmpty, "Не получили витрину копии магазина")
        XCTAssertFalse(left.contains { $0["id"] as? String == "p10" }, "Товар не удалился на сервере — проверка ничего не проверила")
    }

    /// Этап K.2: прямая ссылка на массовые изменения сразу после запуска (сотрудник уже вошёл) — экран сам загружает
    /// данные панели, один раз; открытый повторно из меню панели (данные уже есть) — не загружает. Раньше по ссылке
    /// список был пустым.
    /// Перед test22 (тот удаляет товар): число товаров при обоих открытиях одно и то же
    func test21a_BulkDeepLinkLoadsData() {
        signInOwner()
        func loads() -> Int { ctl("stats")["adminData"] as? Int ?? -1 }
        let before = loads()
        launch("/admin?s=productsBulk")
        let all = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Выбрать все ('")).firstMatch
        guard all.waitForExistence(timeout: 25) else { XCTFail("По прямой ссылке список товаров пуст или не загрузился"); shot("21a пустой список"); return }
        shot("21a по прямой ссылке")
        let n = Int(all.label.filter(\.isNumber)) ?? 0
        XCTAssertGreaterThan(n, 0, "По прямой ссылке нет товаров: \(all.label)")
        XCTAssertFalse(button("Снять выбор").exists, "Экран показывает пустой список")
        XCTAssertEqual(loads() - before, 1, "Данные панели по прямой ссылке загружены не один раз")
        // Повторно — как сотрудник: главная панели → «Товары» → «Массовые изменения». Данные уже есть — экран массовых
        // изменений их не загружает. Не через ссылку на список товаров: под ним главная панели, ни разу не показанная, и при
        // переходе дальше SwiftUI запускает её загрузку (журнал посредника, этап K.2) — это главная, а не этот экран
        launch("/admin")
        let goods = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Товары'")).firstMatch
        guard goods.waitForExistence(timeout: 25) else { XCTFail("Главная панели не открылась"); shot("21a нет главной панели"); return }
        goods.tap()
        let tools = button("Массовые изменения и остатки в Excel")
        guard tools.waitForExistence(timeout: 25) else { XCTFail("Список товаров панели не открылся"); shot("21a нет товаров панели"); return }
        // список товаров закончил свою загрузку (строки товаров на экране) — дальше считаем только экран массовых изменений
        // строка товара — «ALB-0008 · Верхняя одежда · 38 900 ₽ · остаток 19»; конкретный товар может быть ниже экрана
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'остаток '")).firstMatch   // строка — кнопка или текст в ней
        guard row.waitForExistence(timeout: 25) else { XCTFail("Список товаров панели не загрузился"); shot("21a список не загрузился"); return }
        let again = loads()
        tools.tap()
        XCTAssertTrue(all.waitForExistence(timeout: 15), "Массовые изменения из списка товаров открылись без товаров")
        XCTAssertEqual(Int(all.label.filter(\.isNumber)), n, "Повторно открытый экран показывает другое число товаров")
        sleep(2)
        // Главная панели загружает данные при каждом своём .task без условия, и SwiftUI запускает его, когда в стек уходит
        // экран глубже, хотя главная не видна: ровно одна загрузка от главной (журнал посредника с местом вызова, этап K.2:
        // AdminViews.swift:99). Экран массовых изменений, загрузи он данные заново, дал бы вторую
        XCTAssertLessThanOrEqual(loads() - again, 1, "Повторно открытый экран снова загрузил данные панели (кроме главной)")
    }

    // MARK: - 24. Этап L.2.36: отмена загрузки фото цвета — реальное нажатие на ✕ «Отмена» во время загрузки

    /// Дождаться условия: проверка раз в 0,1 с до срока. Синхронизация — по состоянию посредника или экрана, срок —
    /// только предел ожидания (тест падает с понятным текстом). Пауза между проверками — XCTWaiter (крутит цикл событий),
    /// не sleep
    func waitUntil(_ timeout: TimeInterval, _ ready: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if ready() { return true }
            if Date() >= deadline { return false }
            _ = XCTWaiter.wait(for: [XCTestExpectation(description: "опрос")], timeout: 0.1)
        }
    }
    /// Удержанные посредником загрузки (режим hold): сейчас держится, из них оборвало приложение, всего пришло, всего оборвано
    func held() -> (held: Int, aborted: Int, received: Int, abortedTotal: Int) {
        let j = ctl("held")
        return (j["held"] as? Int ?? -1, j["aborted"] as? Int ?? -1, j["received"] as? Int ?? -1, j["abortedTotal"] as? Int ?? -1)
    }
    /// Приметы окна выбора фото (как в pickPhotos): подписи его нижней панели и кнопки подтверждения выбора. В карточке
    /// товара есть свои «Добавить» (строки списков) — поэтому сравнивается число примет до нажатия и после, а не их наличие
    func photoPickerMarks() -> Int {
        let bar = ["Выбрать фото", "Choose Photos", "Select Photos", "Показать выбранные", "Show Selected"]
        return app.descendants(matching: .any).matching(NSPredicate(format: "label IN %@", bar)).count
            + app.buttons.matching(NSPredicate(format: "label IN %@", ["Добавить", "Add", "Готово", "Done"])).count
    }
    /// Ряд фото цвета — горизонтальная лента: плитка в её конце может уйти за правый край экрана (у товара уже много фото).
    /// Листаем ленту влево, пока элемент целиком не окажется на экране, — иначе нажатие по координате придётся мимо
    func revealInRow(_ e: XCUIElement) -> Bool {
        let screen = app.windows.firstMatch.frame.insetBy(dx: 4, dy: 0)
        var n = 0
        while e.exists && !screen.contains(e.frame) && n < 8 {
            let y = e.frame.midY / max(app.frame.height, 1)
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: y)), to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: y))
            from.press(forDuration: 0.05, thenDragTo: to)
            n += 1
        }
        return e.exists && screen.contains(e.frame)
    }
    /// Кнопки «Отмена» на плитке «Фото этого цвета»
    func cancelsOn(_ tile: XCUIElement) -> [XCUIElement] {
        app.buttons.matching(NSPredicate(format: "label == 'Отмена'")).allElementsBoundByIndex.filter { $0.exists && $0.frame.intersects(tile.frame) }
    }

    /// Три фото цвета: первое загружается, второе посредник держит — нажатие на ✕ «Отмена» (в её зоне 44×44, но мимо
    /// видимого кружка) отменяет загрузку, галерея не открывается, «Сохранить» снова доступна; приложение само обрывает
    /// запрос второго фото, третье не отправляется; файл второго фото, дошедший до магазина поздно, к цвету не привязан.
    /// Каждый шаг ждёт подтверждения посредника (hold, ci/audit-proxy.js) или экрана, а не времени. Режим hold снимает
    /// tearDown (on?scope=all обрывает всё удержанное) — и при падении теста
    func test24_ColorPhotosCancelUpload() {
        signInOwner()
        ctl("on?scope=all")
        let before = colorImages("p1"), sent = uploads().count
        ctl("hold?scope=admin/upload")
        let h0 = held()   // счётчики посредника накопительные — дальше сравниваются приросты от этого состояния
        XCTAssertEqual(h0.held, 0, "Посредник уже держит загрузки до начала теста")
        launch("/admin?s=products&id=p1")
        XCTAssertTrue(text("Цвета, фото и остатки").waitForExistence(timeout: 25), "Карточка товара не открылась")
        let tile = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Фото этого цвета'")).firstMatch
        scrollTo(tile)
        guard tile.exists, revealInRow(tile) else { XCTFail("Нет плитки «Фото этого цвета» на экране: \(tile.frame)"); shot("24 нет плитки"); return }
        tile.tap()
        guard pickPhotos(3, "24") else { return }

        // 1. Первое фото: посредник его держит → отпускаем в магазин → оно загружено до отмены
        guard waitUntil(60, { self.held().held == 1 }) else { XCTFail("Запрос первого фото не дошёл до посредника: \(held())"); shot("24 нет первого запроса"); return }
        let released = Date()
        ctl("release?n=1&forward=1")
        guard waitUntil(25, { self.uploads().count == sent + 1 }) else { XCTFail("Первое фото не загрузилось: \(uploads().dropFirst(sent))"); return }
        let first = uploads()[sent]
        XCTAssertEqual(first["status"] as? Int, 200, "Первое фото не принято магазином: \(first)")
        let firstURL = first["url"] as? String ?? ""

        // 2. Второе фото посредник держит — загрузка идёт, приложение ждёт ответа
        guard waitUntil(60, { let h = self.held(); return h.held == 1 && h.received - h0.received == 2 }) else { XCTFail("Запрос второго фото не дошёл до посредника: \(held())"); shot("24 нет второго запроса"); return }
        let heldAt = Date(), photoTime = heldAt.timeIntervalSince(released)   // ответ на первое фото + обработка второго на этой машине
        XCTAssertEqual(held().aborted, 0, "Запрос второго фото оборван ещё до нажатия «Отмена»")
        // первое фото добавилось в ленту — плитка сдвинулась вправо; листаем ленту, пока «Отмена» целиком не на экране
        let shown = cancelsOn(tile).first.map { revealInRow($0) } ?? false
        XCTAssertTrue(shown, "«Отмена» не удалось вывести на экран: \(cancelsOn(tile).first?.frame ?? .zero)")

        // 3–5. «Отмена» видна, зона не меньше 44×44, в правом верхнем углу плитки; «Сохранить» недоступна
        let cancels = cancelsOn(tile)
        guard cancels.count == 1, let cancel = cancels.first else {
            XCTFail("Во время загрузки на плитке не одна кнопка «Отмена», а \(cancels.count)"); shot("24 нет отмены"); return
        }
        let f = cancel.frame, t = tile.frame
        note("24: «Отмена» \(f), плитка \(t), ответ на первое фото и обработка второго — \(Int(photoTime * 1000)) мс")
        XCTAssertTrue(cancel.isHittable, "«Отмена» не нажимается")
        XCTAssertGreaterThanOrEqual(f.width, 44, "Зона «Отмена» уже 44 pt: \(f)")
        XCTAssertGreaterThanOrEqual(f.height, 44, "Зона «Отмена» ниже 44 pt: \(f)")
        XCTAssertEqual(f.maxX, t.maxX, accuracy: 1.5, "«Отмена» не у правого края плитки: \(f) / \(t)")
        XCTAssertEqual(f.minY, t.minY, accuracy: 1.5, "«Отмена» не у верхнего края плитки: \(f) / \(t)")
        let save = button("Сохранить")
        XCTAssertTrue(save.exists, "Нет кнопки «Сохранить»")
        XCTAssertFalse(save.isEnabled, "Во время загрузки фото «Сохранить» доступна")
        let marks = photoPickerMarks()   // приметы окна выбора до нажатия (свои «Добавить» карточки товара)

        // 6. Нажатие в зоне «Отмена», но мимо видимого кружка: кружок 22 pt с отступом 4 pt от угла — центр в 15 pt от правого
        // и верхнего краёв зоны, радиус 11 pt; точка — в 30 pt от краёв: внутри зоны, в ≈21 pt от центра кружка
        let center = CGPoint(x: f.maxX - 15, y: f.minY + 15), point = CGPoint(x: f.maxX - 30, y: f.minY + 30)
        let distance = hypot(point.x - center.x, point.y - center.y)
        XCTAssertTrue(f.contains(point), "Точка нажатия \(point) вне зоны «Отмена» \(f)")
        XCTAssertTrue(app.windows.firstMatch.frame.contains(point), "Точка нажатия \(point) за краем экрана")
        XCTAssertGreaterThan(distance, 11 + 4, "Точка нажатия \(point) слишком близко к кружку (\(distance) pt)")
        // приложение ждёт ответа не дольше 25 с (URLSession), после — ошибка «нет связи» и следующее фото: нажимаем раньше,
        // пока второе фото по-прежнему держится и не оборвано
        let waited = Date().timeIntervalSince(heldAt)
        XCTAssertLessThan(waited, 20, "От удержания второго фото до нажатия прошло \(Int(waited)) с — близко к 25 с ожидания приложения")
        XCTAssertEqual(held().aborted, 0, "Запрос второго фото оборван до нажатия «Отмена» (истекло ожидание приложения?)")
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x, dy: point.y)).tap()

        // 7–9. Нажатие отменило загрузку: «Отмена» исчезла, галерея не открылась, плитка на месте, «Сохранить» доступна
        XCTAssertTrue(waitUntil(10, { self.cancelsOn(tile).isEmpty }), "После нажатия «Отмена» осталась — загрузка не отменена")
        // окно выбора открывается с анимацией (в отдельном процессе) — ждём его появления с запасом, его не должно быть
        XCTAssertFalse(waitUntil(3, { self.photoPickerMarks() != marks }), "Нажатие в зоне «Отмена» открыло окно выбора фото")
        XCTAssertTrue(tile.exists && tile.isHittable, "Плитка «Фото этого цвета» закрыта или пропала после нажатия")
        XCTAssertTrue(waitUntil(10, { save.isEnabled }), "После отмены «Сохранить» недоступна")
        shot("24 после отмены")

        // 10. Посредник подтверждает: приложение само закрыло соединение второго фото (отмена URLSession)
        XCTAssertTrue(waitUntil(10, { let h = self.held(); return h.aborted == 1 && h.abortedTotal - h0.abortedTotal == 1 }), "Посредник не видит обрыва запроса второго фото приложением: \(held())")
        // 11. Третье фото не отправлено. Отменённая очередь в приложении останавливается на втором фото (модульные тесты
        // L.2.33); снаружи её конец не виден, поэтому — ожидание запроса третьего фото с запасом: втрое дольше, чем на этой
        // машине заняли ответ на первое фото и обработка второго, и не меньше 10 с. Запрос, если бы он был, посредник
        // держал бы — received не пропустит его
        let window = min(60, max(10, photoTime * 3))
        XCTAssertFalse(waitUntil(window, { self.held().received - h0.received > 2 }), "После отмены приложение отправило третье фото: \(held())")
        note("24: третьего запроса нет за \(Int(window)) с; посредник: \(held())")

        // 12. Поздний файл: второе фото всё же доходит до магазина (тело запроса посредник уже получил) и остаётся там
        // непривязанным. Ответ приложению не придёт — соединение закрыто, поэтому со стороны приложения привязать его нечем;
        // проверяется итог на сервере: после сохранения карточки этого файла у цвета нет
        ctl("release?forward=1")
        guard waitUntil(25, { self.uploads().count == sent + 2 }) else { XCTFail("Поздний файл второго фото не дошёл до магазина: \(uploads().dropFirst(sent))"); return }
        let lateURL = uploads()[sent + 1]["url"] as? String ?? ""
        XCTAssertFalse(lateURL.isEmpty, "Магазин не вернул адрес позднего файла")
        XCTAssertEqual(held().held, 0)

        scrollTo(save)
        guard save.exists, save.isEnabled else { XCTFail("«Сохранить» недоступна"); return }
        save.tap()
        guard waitUntil(30, { self.colorImages("p1") != before }) else { XCTFail("Товар не сохранился: \(colorImages("p1"))"); shot("24 не сохранён"); return }
        let after = colorImages("p1")
        shot("24 товар сохранён")
        XCTAssertEqual(after, before + [firstURL], "У цвета не прежние фото и первое загруженное: было \(before), стало \(after)")
        XCTAssertFalse(after.contains(lateURL), "Поздний файл отменённого второго фото привязан к цвету: \(lateURL)")

        // 13. Повторно: экран товара открыт заново (данные панели загружаются снова) — новых загрузок от этого нет; данные
        // цвета ещё раз прочитаны с сервера (/api/state) — позднего файла нет
        launch("/admin?s=products&id=p1")
        XCTAssertTrue(text("Цвета, фото и остатки").waitForExistence(timeout: 25), "Карточка товара не открылась повторно")
        let again = colorImages("p1")
        XCTAssertEqual(again, before + [firstURL], "После повторной загрузки у цвета другие фото: \(again)")
        XCTAssertFalse(again.contains(lateURL), "После повторной загрузки поздний файл привязан к цвету")
        XCTAssertEqual(uploads().count, sent + 2, "Появились лишние загрузки: \(uploads().dropFirst(sent))")
        let h = held()
        XCTAssertEqual(h.received - h0.received, 2, "Посредник получил не два запроса загрузки: \(h)")
        XCTAssertEqual(h.held, 0)
    }
}
