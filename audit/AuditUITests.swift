import XCTest
import UIKit
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
    func signInOwner() {
        launch("/account")
        let pw = app.secureTextFields.firstMatch
        if pw.waitForExistence(timeout: 8) {
            let login = app.textFields.firstMatch
            login.tap(); login.typeText("owner-audit@example.com")
            // Пароль: поле должно получить фокус, и в нём должно оказаться 10 знаков (секретное поле показывает точки).
            // Пароль из цифр: в секретном поле открывается русская раскладка, латинские буквы XCUITest не набирает —
            // раньше вход молча не удавался, и тесты панели шли без входа (этап A.1, видео теста 11)
            var typed = false
            for _ in 1...3 where !typed {
                pw.tap()
                guard app.keyboards.firstMatch.waitForExistence(timeout: 5) else { continue }
                let had = (pw.value as? String)?.count ?? 0
                if had > 0 && had != 10 { pw.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: had + 2)) }
                if had != 10 { pw.typeText("5739146280") }
                typed = (pw.value as? String)?.count == 10
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
    /// Ссылка albakov://… в приложение: в запущенное — без перезапуска (как нажатие на ссылку или уведомление),
    /// в закрытое — холодный запуск с этой ссылкой
    func openLink(_ link: String) {
        guard let url = URL(string: link) else { return XCTFail("Неверная ссылка \(link)") }
        guard #available(iOS 16.4, *) else { return XCTFail("Открыть ссылку в приложении из теста можно с iOS 16.4") }
        app.open(url)
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "Приложение не открылось по ссылке")
        sleep(3)
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
            XCTFail("\(step): по подписям не отличить снимки audit.yml от стандартных: " + all.map(\.label).joined(separator: " | ")); return false
        }
        let usable = Array(ours(all).filter { $0.frame.minY >= 0 && $0.frame.maxY <= barTop }.prefix(n))
        note("\(step): снимков в окне \(all.count), своих \(ours(all).count), нижняя панель с \(Int(barTop)) pt; выбираем: " + usable.map(\.label).joined(separator: " | "))
        guard usable.count == n else { XCTFail("\(step): в окне выбора видно своих снимков \(usable.count) из \(n); подписи: " + all.map(\.label).joined(separator: " | ")); return false }
        let origin = app.coordinate(withNormalizedOffset: .zero)
        for c in usable { origin.withOffset(CGVector(dx: c.frame.midX, dy: c.frame.midY)).tap(); usleep(400_000) }
        let marked = cells().filter(\.isSelected), selected = marked.count
        // где отметки видны — все отмеченные должны быть своими (сетка могла сдвинуться после первого нажатия)
        guard ours(marked).count == marked.count else { XCTFail("\(step): отмечены не те снимки: " + marked.map(\.label).joined(separator: " | ")); return false }
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

    /// Раньше данные панели оставались в памяти после выхода: ссылка или старое уведомление сотрудника показывали
    /// заказы и покупателей. Выход и ссылка — в том же запуске приложения, без перезапуска (иначе память и так пуста)
    func test18_StaffLogoutAdminLinkShowsNoData() {
        let last = "Покупатель-Восемнадцать"
        signInOwner()
        startClean()
        addToCart(product: "p6", size: "M")
        launch("/checkout")
        fillCheckout(phone: "79070000181", name: "Секрет", last: last)
        let c = button("Подтвердить заказ"); scrollTo(c); c.tap()
        XCTAssertTrue(waitOrderOpened(), "Заказ не оформился")
        // панель в этом же запуске: список заказов загружен, новый заказ с фамилией покупателя виден
        openLink("albakov://admin?s=orders")
        XCTAssertTrue(app.segmentedControls.buttons["В работе"].waitForExistence(timeout: 20), "Список заказов панели не открылся")
        XCTAssertTrue(text(last).waitForExistence(timeout: 30), "В списке заказов панели нет нового заказа — проверка после выхода была бы пустой")
        shot("18а заказы в панели у сотрудника")
        // выход в том же запуске
        openLink("albakov://account")
        logoutFromAccount()
        // ссылка в панель после выхода — как старое уведомление сотрудника
        openLink("albakov://admin?s=orders")
        XCTAssertTrue(text("Нет доступа").waitForExistence(timeout: 15), "После выхода ссылка открыла панель без прав")
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
        // обычный запуск (без -screen): могут всплыть окна «Включите уведомления» и «Вышло обновление» — к проверке не относятся
        let list = app.segmentedControls.buttons["В работе"]
        let deadline = Date().addingTimeInterval(60)
        while !(list.exists && text(last).exists), Date() < deadline {
            for b in ["Не сейчас", "Позже"] where button(b).exists { button(b).tap() }
            sleep(1)
        }
        XCTAssertTrue(list.exists, "Сотрудник не попал в список заказов панели при запуске по ссылке")
        XCTAssertFalse(text("Нет доступа").exists, "Сотруднику показан отказ в доступе")
        XCTAssertTrue(text(last).exists, "В панели нет заказа сотрудника — данные admin/data не загрузились")
        shot("19 запуск по ссылке — заказы панели")
    }
}
