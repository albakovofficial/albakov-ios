import XCTest
import UIKit
@testable import Albakov

/// Юнит-тесты этапа D. Только проверка, в приложение не входят. Собираются целью AlbakovUnit (audit.yml).

// MARK: - Q-B3: кэш картинок

/// Подставной сервер картинок: считает запросы по адресу, отвечает с задержкой (чтобы запросы успели пересечься).
/// Ответ не кладётся в URLCache — каждый запрос, дошедший до сети, виден здесь.
final class ImageStub: URLProtocol {
    private static let lock = NSLock()
    private static var hits: [String: Int] = [:]
    private static var broken: Set<String> = []
    static let png = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).pngData { $0.cgContext.setFillColor(UIColor.red.cgColor); $0.fill(CGRect(x: 0, y: 0, width: 4, height: 4)) }
    static func count(_ u: URL) -> Int { lock.lock(); defer { lock.unlock() }; return hits[u.path] ?? 0 }
    static func setBroken(_ u: URL, _ on: Bool) { lock.lock(); defer { lock.unlock() }; if on { broken.insert(u.path) } else { broken.remove(u.path) } }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "stub.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, let resp = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) else { return }
        Self.lock.lock(); Self.hits[url.path, default: 0] += 1; let bad = Self.broken.contains(url.path); Self.lock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
            self.client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: bad ? Data("не картинка".utf8) : Self.png)
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}

final class ImageCacheTests: XCTestCase {
    private func cache() -> ImageCache {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [ImageStub.self]
        return ImageCache(configuration: c)
    }
    /// Свой адрес на каждый тест: счётчики и кэши тестов не пересекаются
    private func url() throws -> URL { try XCTUnwrap(URL(string: "http://stub.test/\(UUID().uuidString).png")) }

    /// 20 одновременных запросов одного адреса (сетка каталога, карточка и миниатюра) — одна загрузка, картинка у всех
    func test01_ConcurrentSameURLLoadsOnce() async throws {
        let c = cache(), u = try url()
        let got = await withTaskGroup(of: Bool.self) { g in
            for _ in 0..<20 { g.addTask { await c.load(u) != nil } }
            return await g.reduce(0) { $0 + ($1 ? 1 : 0) }
        }
        XCTAssertEqual(got, 20, "Не все получили картинку")
        XCTAssertEqual(ImageStub.count(u), 1, "Один адрес качался несколько раз")
    }

    /// Повторный показ — из памяти, без новой загрузки
    func test02_RepeatLoadFromMemory() async throws {
        let c = cache(), u = try url()
        let first = await c.load(u)
        XCTAssertNotNil(first)
        XCTAssertNotNil(c.cached(u), "Картинка не легла в кэш")
        let again = await c.load(u)
        XCTAssertNotNil(again)
        XCTAssertEqual(ImageStub.count(u), 1)
    }

    /// Неудачная загрузка не кэшируется и не залипает в списке загрузок: следующий показ пробует снова
    func test03_FailedLoadRetried() async throws {
        let c = cache(), u = try url()
        ImageStub.setBroken(u, true)
        let none = await c.load(u)
        XCTAssertNil(none); XCTAssertNil(c.cached(u))
        ImageStub.setBroken(u, false)
        let img = await c.load(u)
        XCTAssertNotNil(img, "После сбоя картинка больше не загружается")
        XCTAssertEqual(ImageStub.count(u), 2)
    }

    /// Отмена того, кто ждёт (ячейку пролистали), не прерывает загрузку для остальных и не теряет картинку для следующего показа
    func test04_CancelledWaiterDoesNotBreakLoad() async throws {
        let c = cache(), u = try url()
        let first = Task { await c.load(u) }
        first.cancel()
        let second = await c.load(u)
        XCTAssertNotNil(second, "Отмена первого ждущего сорвала загрузку второму")
        _ = await first.value
        XCTAssertNotNil(c.cached(u))
        XCTAssertEqual(ImageStub.count(u), 1, "После отмены адрес качался ещё раз")
    }

    /// Много адресов, по несколько ждущих на каждый, разом: каждый адрес — одна загрузка, без зависания (не дольше 20 с)
    func test05_ManyURLsConcurrently() async throws {
        let c = cache(), urls = try (0..<40).map { _ in try url() }
        let done = expectation(description: "все загрузки закончились")
        Task {
            await withTaskGroup(of: Void.self) { g in
                for u in urls { for _ in 0..<4 { g.addTask { _ = await c.load(u) } } }
            }
            done.fulfill()
        }
        await fulfillment(of: [done], timeout: 20)
        for u in urls { XCTAssertEqual(ImageStub.count(u), 1, u.path); XCTAssertNotNil(c.cached(u)) }
    }
}

// MARK: - Q-B4: финансы

final class FinanceValuesTests: XCTestCase {
    /// Форма ставок — как её заполняет экран: числа, целые целыми (Doc.number хранит NSNumber)
    private func form() -> [String: Any] {
        ["taxRate": NSNumber(value: 6), "sbpYk": NSNumber(value: 0.4), "sbpPartner": NSNumber(value: 1.5),
         "otherYk": NSNumber(value: 2.8), "otherPartner": NSNumber(value: 1), "partnerMin": NSNumber(value: 0.65), "codFee": NSNumber(value: 3)]
    }
    /// Тело запроса, прочитанное обратно, — как его прочтёт сервер. Строкой не сравниваем: дробные JSONSerialization
    /// пишет с 17 знаками (0.65 → «0.65000000000000002»), так приложение отправляло их и раньше; при чтении это ровно 0.65
    private func parsed(_ d: Data) throws -> NSDictionary { try XCTUnwrap(JSONSerialization.jsonObject(with: d) as? NSDictionary) }

    /// Обычные значения уходят как есть. Сама первопричина (Optional в Any у «Карты: комиссия ЮKassa») видна только
    /// компилятору — её закрывает сборка без предупреждений; здесь — что сервер получит те же числа
    func test01_NormalValuesUnchanged() throws {
        let v = try XCTUnwrap(FinanceSettings.settingsValue(JSON(form()), categories: [["id": "c1", "name": "Реклама", "kind": "fixed"]], costs: ["p1": 450]))
        let expected = #"{"categories":[{"id":"c1","kind":"fixed","name":"Реклама"}],"codFee":3,"costs":{"p1":450},"partnerMin":0.65,"rates":{"other":{"partner":1,"yk":2.8},"sbp":{"partner":1.5,"yk":0.4}},"taxRate":6}"#
        XCTAssertEqual(try parsed(JSONSerialization.checkedData(v)), try parsed(Data(expected.utf8)))
    }

    /// Нет какого-то числа — не сохраняем вовсе (раньше на его месте уходил 0: налог 0% — неверная прибыль)
    func test02_MissingValueNotSaved() {
        for k in form().keys {
            var f = form(); f.removeValue(forKey: k)
            XCTAssertNil(FinanceSettings.settingsValue(JSON(f), categories: [], costs: [String: Any]()), "Без «\(k)» ушло бы значение по умолчанию")
        }
    }

    /// Некорректные данные (не число, NaN, бесконечность) — не сохраняем
    func test03_InvalidValueNotSaved() {
        for bad: Any in ["2,8", NSNumber(value: Double.nan), NSNumber(value: Double.infinity), NSNull()] {
            var f = form(); f["otherYk"] = bad
            XCTAssertNil(FinanceSettings.settingsValue(JSON(f), categories: [], costs: [String: Any]()), "Ушло значение из \(bad)")
        }
    }

    /// Себестоимость: пусто — «нет себестоимости», число — числом (запятая или точка), не число — ошибка, а не 0
    /// (0 сервер понимает как «не задана» — себестоимость пропадала молча)
    func test04_CostValue() {
        XCTAssertEqual(FinanceCosts.value("") as? String, "")
        XCTAssertEqual(FinanceCosts.value("450") as? Double, 450)
        XCTAssertEqual(FinanceCosts.value("450,50") as? Double, 450.5)
        XCTAssertEqual(FinanceCosts.value("12345.67") as? Double, 12345.67)
        for bad in ["1.200,50", "1,2,3", ",", "."] { XCTAssertNil(FinanceCosts.value(bad), bad) }
    }

    /// Себестоимость и сумма операции в поле — как пришли с сервера. Прежний %g давал «12345.7» и «1.23457e+06»,
    /// и сохранение без правки меняло сумму
    func test05_NumberTextExact() {
        XCTAssertEqual(String(format: "%g", 12345.67), "12345.7")   // так было
        XCTAssertEqual(String(format: "%g", 1234567.0), "1.23457e+06")
        XCTAssertEqual(JSON(NSNumber(value: 12345.67)).numberText, "12345.67")
        XCTAssertEqual(JSON(NSNumber(value: 1234567)).numberText, "1234567")
        XCTAssertEqual(JSON(NSNumber(value: 1200)).numberText, "1200")
        XCTAssertEqual(JSON(NSNumber(value: 450.5)).numberText, "450.5")
        XCTAssertEqual(JSON(nil).numberText, "")
        XCTAssertEqual(FinanceCosts.value(JSON(NSNumber(value: 12345.67)).numberText) as? Double, 12345.67, "Сохранение без правки меняет сумму")
    }

    /// Числовое поле панели (налог, ставки, цены): огромное или бесконечное число не роняет приложение (Int(1e19) — падение)
    func test06_NumberFieldHugeValueNoCrash() {
        let doc = Doc([:]), field = doc.number("taxRate")
        field.wrappedValue = "9999999999999999999"
        XCTAssertEqual((doc.v["taxRate"] as? NSNumber)?.doubleValue, 1e19)
        field.wrappedValue = "inf"
        XCTAssertEqual((doc.v["taxRate"] as? NSNumber)?.doubleValue, .infinity)
        var f = form(); f["taxRate"] = doc.v["taxRate"]
        XCTAssertNil(FinanceSettings.settingsValue(JSON(f), categories: [], costs: [String: Any]()), "Бесконечная ставка из поля ушла бы на сервер")
        field.wrappedValue = "450"
        let n = doc.v["taxRate"] as? NSNumber
        XCTAssertEqual(n?.intValue, 450)
        XCTAssertFalse(n.map { CFNumberIsFloatType($0 as CFNumber) } ?? true, "Целое перестало храниться целым (на сервер ушло бы 450.0)")
        field.wrappedValue = "2,8"
        XCTAssertEqual((doc.v["taxRate"] as? NSNumber)?.doubleValue, 2.8)
    }
}

// MARK: - Q-B5: время сервера

final class ServerClockTests: XCTestCase {
    private func header(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "GMT"); f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f.string(from: d)
    }

    /// Заголовок Date разбирается в расхождение часов; мусор — nil (прежнее значение остаётся)
    func test01_Offset() throws {
        XCTAssertEqual(try XCTUnwrap(ServerClock.offset(header(Date().addingTimeInterval(60)))), 60.5, accuracy: 1.5)
        XCTAssertEqual(try XCTUnwrap(ServerClock.offset(header(Date().addingTimeInterval(-3600)))), -3599.5, accuracy: 1.5)
        XCTAssertNil(ServerClock.offset("вчера"))
        XCTAssertNil(ServerClock.offset(""))
    }

    /// Запись из многих потоков разом и чтение — без падения; читается всегда одно из записанных значений.
    /// Гонку данных как таковую ловит только Thread Sanitizer (на GitHub не запускается), здесь — работа под нагрузкой.
    /// Приложение-хозяин тоже ходит в магазин и пишет своё расхождение (≈0,5 с) — оно тоже допустимо
    func test02_ConcurrentSyncAndRead() async {
        let a = header(Date().addingTimeInterval(100)), b = header(Date().addingTimeInterval(200))
        let reads = await withTaskGroup(of: TimeInterval?.self) { g in
            for i in 0..<400 {
                g.addTask {
                    if i.isMultiple(of: 2) { ServerClock.sync(i.isMultiple(of: 4) ? a : b); return nil }
                    return ServerClock.skew
                }
            }
            var out: [TimeInterval] = []
            for await r in g { if let r { out.append(r) } }
            return out
        }
        let allowed: [TimeInterval] = [0, 0.5, 100.5, 200.5]
        for r in reads + [ServerClock.skew] {
            XCTAssertTrue(allowed.contains { abs($0 - r) < 3 }, "Прочитано значение, которого никто не писал: \(r)")
        }
        ServerClock.sync(header(Date()))   // расхождение — общее для процесса: возвращаем как у настоящего ответа
    }
}
