import XCTest
@testable import Albakov

/// Юнит-тесты этапа E (Q-B10). Только проверка, в приложение не входят. Собираются целью AlbakovUnit (audit.yml).
/// Ожидаемые значения — по правилам сайта (public/js/pricing.js: productPrice, inWindow — даты по Москве),
/// посчитаны вручную, а не повтором кода приложения.

private func utc(_ s: String) -> Date {
    let f = ISO8601DateFormatter()
    guard let d = f.date(from: s) else { preconditionFailure("неверная дата в тесте: \(s)") }
    return d
}

// MARK: - Цена товара (Shop.price)

final class PriceTests: XCTestCase {
    private let now = utc("2026-11-17T10:00:00Z")
    private func product(_ price: Any?, compareAt: Int = 0, category: String = "tees", id: String = "p1") -> Product {
        var j: [String: Any] = ["id": id, "name": "Футболка", "categoryId": category, "compareAt": compareAt, "colors": [["id": "c1", "sizes": [["size": "M", "stock": 3]]]]]
        if let price { j["price"] = price }
        return Product(JSON(j))
    }
    private func promo(_ type: String, _ value: Any?, scope: String = "all", ids: [String] = [], title: String = "Акция",
                       starts: String = "", ends: String = "", active: Bool = true) -> Promotion {
        var j: [String: Any] = ["id": title, "title": title, "type": type, "scope": scope, "startsAt": starts, "endsAt": ends, "active": active,
                                "categoryIds": scope == "categories" ? ids : [], "productIds": scope == "products" ? ids : []]
        if let value { j["value"] = value }
        return Promotion(JSON(j))
    }
    private func price(_ p: Product, _ promos: [Promotion], at t: Date? = nil) -> Price { Shop.price(p, promotions: promos, now: t ?? now) }

    /// Без акций: цена как есть; старая — только если она выше
    func test01_NoPromotion() {
        let a = price(product(2990), [])
        XCTAssertEqual(a.price, 2990); XCTAssertEqual(a.oldPrice, 0); XCTAssertEqual(a.promoTitle, "")
        let b = price(product(2990, compareAt: 3990), [])
        XCTAssertEqual(b.price, 2990); XCTAssertEqual(b.oldPrice, 3990); XCTAssertEqual(b.percent, 25)   // (1 − 2990/3990)·100 = 25,06
        XCTAssertEqual(price(product(2990, compareAt: 2500), []).oldPrice, 0, "Старая цена ниже текущей не показывается")
    }

    /// Процент округляется как Math.round на сайте — половина вверх: 2990 · 0,85 = 2541,5 → 2542, 2970 · 0,85 = 2524,5 → 2525
    /// (банковское округление дало бы 2524); фиксированная — минус сумма
    func test02_PercentAndFixed() {
        let p = price(product(2990), [promo("percent", 15, title: "Минус 15%", ends: "2026-11-30")])
        XCTAssertEqual(p.price, 2542); XCTAssertEqual(p.oldPrice, 2990); XCTAssertEqual(p.promoTitle, "Минус 15%"); XCTAssertEqual(p.promoEnds, "2026-11-30")
        XCTAssertEqual(price(product(2970), [promo("percent", 15)]).price, 2525, "Половина округляется вверх, как Math.round")
        XCTAssertEqual(price(product(2990), [promo("fixed", 500)]).price, 2490)
        XCTAssertEqual(price(product(1999), [promo("percent", 33)]).price, 1339)   // 1999 · 0,67 = 1339,33
    }

    /// Из нескольких действующих — самая низкая цена и название именно этой акции
    func test03_BestOfSeveral() {
        let p = price(product(2990, category: "tees", id: "p7"), [
            promo("percent", 10, title: "Все 10%"),                                      // 2691
            promo("fixed", 500, scope: "categories", ids: ["tees"], title: "Футболки −500"), // 2490
            promo("percent", 20, scope: "products", ids: ["p7"], title: "Товар 20%"),     // 2392
            promo("percent", 50, scope: "products", ids: ["p8"], title: "Чужой товар"),
        ])
        XCTAssertEqual(p.price, 2392); XCTAssertEqual(p.promoTitle, "Товар 20%"); XCTAssertEqual(p.percent, 20)
        // одинаковая цена у двух акций — остаётся первая (на сайте сравнение строгое: price < bestPrice)
        XCTAssertEqual(price(product(2990), [promo("fixed", 299, title: "Первая"), promo("percent", 10, title: "Вторая")]).promoTitle, "Первая")
    }

    /// Акция не применяется: другая категория, выключена, неизвестный охват
    func test04_NotApplicable() {
        let base = product(2990, category: "tees")
        XCTAssertEqual(price(base, [promo("percent", 30, scope: "categories", ids: ["hoodies"])]).price, 2990)
        XCTAssertEqual(price(base, [promo("percent", 30, active: false)]).price, 2990)
        XCTAssertEqual(price(base, [promo("percent", 30, scope: "brand")]).price, 2990)
    }

    /// Граничные значения: скидка больше цены — не ниже 0; со старой ценой — старая берётся бо́льшая из двух
    func test05_Bounds() {
        XCTAssertEqual(price(product(2990), [promo("percent", 100)]).price, 0)
        XCTAssertEqual(price(product(2990), [promo("percent", 120)]).price, 0)
        XCTAssertEqual(price(product(2990), [promo("fixed", 5000)]).price, 0)
        let c = price(product(2990, compareAt: 3990), [promo("percent", 10)])
        XCTAssertEqual(c.price, 2691); XCTAssertEqual(c.oldPrice, 3990, "Старая цена при акции — бо́льшая из цены и «было»")
    }

    /// Сроки акции — по Москве: «до 17 ноября» действует до 23:59:59 МСК (20:59:59 UTC), «с 18 ноября» — с 00:00 МСК
    func test06_WindowInMoscow() {
        let p = product(2990), end = promo("percent", 10, ends: "2026-11-17"), start = promo("percent", 10, starts: "2026-11-18")
        XCTAssertEqual(price(p, [end], at: utc("2026-11-17T20:59:59Z")).price, 2691, "В последнюю секунду дня по Москве акция ещё идёт")
        XCTAssertEqual(price(p, [end], at: utc("2026-11-17T21:00:00Z")).price, 2990, "Через секунду после полуночи по Москве акция закончилась")
        XCTAssertEqual(price(p, [start], at: utc("2026-11-17T20:59:59Z")).price, 2990, "До полуночи по Москве акция ещё не началась")
        XCTAssertEqual(price(p, [start], at: utc("2026-11-17T21:00:00Z")).price, 2691, "С полуночи по Москве акция идёт")
    }

    /// Пустые и некорректные данные: нет значения скидки или цены — ничего не выдумываем
    func test07_EmptyAndInvalid() {
        XCTAssertEqual(price(product(2990), [promo("percent", nil)]).price, 2990, "Акция без значения не меняет цену")
        XCTAssertEqual(price(product(2990), [promo("percent", nil)]).promoTitle, "")
        let noPrice = price(product(nil), [promo("percent", 10)])
        XCTAssertEqual(noPrice.price, 0); XCTAssertEqual(noPrice.oldPrice, 0)
        XCTAssertEqual(price(product(2990), [promo("unknown", 10)]).price, 2691, "Неизвестный вид — как процент (на сайте: всё, что не fixed)")
        XCTAssertEqual(price(product(2990), [promo("percent", 10, ends: "не дата")]).price, 2691, "Неразборчивая дата окончания не обрывает акцию (как на сайте)")
    }
}

// MARK: - Даты на экранах и для сервера

final class DateFormatTests: XCTestCase {
    /// Дата в поясе устройства, григорианский календарь (как у форматтеров с ru_RU и en_US_POSIX):
    /// тесты не зависят ни от пояса Mac, ни от календаря в его настройках
    private let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = .current; return c }()
    private func local(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        guard let x = cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min)) else { preconditionFailure() }
        return x
    }
    private func iso(_ d: Date) -> String { ISO8601DateFormatter().string(from: d) }

    /// Даты в карточках и списках — по-русски, месяц в родительном падеже
    func test01_FmtDate() {
        let d = local(2026, 11, 17, 14, 5)
        XCTAssertEqual(Fmt.date(d), "17 ноября 2026")
        XCTAssertEqual(Fmt.date(d, time: true), "17 ноября, 14:05")
        XCTAssertEqual(Fmt.date(local(2026, 3, 1)), "1 марта 2026")
        XCTAssertEqual(Fmt.date(nil), "")
        XCTAssertEqual(Fmt.monthYear(iso(local(2026, 11, 17))), "ноября 2026")
        XCTAssertEqual(Fmt.monthYear("не дата"), "")
    }

    /// Ответы сервера: с долями секунды и без; мусор — nil
    func test02_ISODate() throws {
        XCTAssertEqual(try XCTUnwrap(ISO.date("2026-11-17T10:00:00.123Z")).timeIntervalSince1970, utc("2026-11-17T10:00:00Z").timeIntervalSince1970 + 0.123, accuracy: 0.001)
        XCTAssertEqual(ISO.date("2026-11-17T10:00:00Z"), utc("2026-11-17T10:00:00Z"))
        XCTAssertNil(ISO.date("")); XCTAssertNil(ISO.date("17.11.2026"))
        XCTAssertEqual(ISO.day("2026-03-01"), local(2026, 3, 1, 0))
        XCTAssertEqual(ISO.day("2026-03-01T15:00:00Z"), local(2026, 3, 1, 0), "Берётся только день")
        XCTAssertNil(ISO.day("2026-3-1")); XCTAssertNil(ISO.day("2026-13-45"))
    }

    /// Поддержка: сегодня — время, вчера — «Вчера», раньше — «9 марта»
    func test03_SupportDates() {
        guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) else { return XCTFail() }   // «Вчера» — по календарю телефона, как в Support.day
        let today = Date(), old = local(2025, 3, 9, 9, 30)
        XCTAssertEqual(Support.day(iso(today)), "Сегодня")
        XCTAssertEqual(Support.day(iso(yesterday)), "Вчера")
        XCTAssertEqual(Support.day(iso(old)), "9 марта")
        XCTAssertEqual(Support.time(iso(old)), "9 марта")
        let hm = Calendar.current.dateComponents([.hour, .minute], from: today)
        XCTAssertEqual(Support.time(iso(today)), String(format: "%02d:%02d", hm.hour ?? 0, hm.minute ?? 0))
        XCTAssertEqual(Support.clock(iso(old)), "09:30")   // время — в языке телефона (на CI en_US, 24 ч по формату «HH:mm»)
        XCTAssertEqual(Support.clock("не дата"), ""); XCTAssertEqual(Support.day(""), "")
    }

    /// День статистики — как у сервера: по Москве (UTC+3), григорианский «ГГГГ-ММ-ДД» при любом поясе телефона
    func test04_MoscowStatsDay() {
        XCTAssertEqual(DateParse.moscowDay(utc("2026-11-16T21:30:00Z")), "2026-11-17", "00:30 по Москве — уже 17-е")
        XCTAssertEqual(DateParse.moscowDay(utc("2026-11-16T20:59:59Z")), "2026-11-16")
        XCTAssertEqual(DateParse.moscowDay(utc("2026-12-31T21:00:00Z")), "2027-01-01", "Новый год по Москве")
        // день формы панели (этап K: общий форматтер ISO.ymd вместо DateParse.ymd и семи своих копий)
        XCTAssertEqual(ISO.ymd.date(from: "2026-11-17"), local(2026, 11, 17, 0))
        XCTAssertNil(ISO.ymd.date(from: "17-11-2026"))
        XCTAssertEqual(ISO.ymd.string(from: local(2026, 11, 17, 23)), "2026-11-17")
    }

    /// Окно акции и слайда без дат — всегда; выключенная — никогда (Promotion.inWindow)
    func test05_WindowEmptyDates() {
        XCTAssertTrue(Promotion(JSON(["active": true])).inWindow(Date()))
        XCTAssertFalse(Promotion(JSON(["active": false])).inWindow(Date()))
        XCTAssertFalse(Promotion(JSON([String: Any]())).inWindow(Date()), "Без признака active акция не действует")
    }
}
