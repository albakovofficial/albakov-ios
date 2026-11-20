import XCTest
@testable import Albakov

/// Этап L.2.4: ISO.date — форматтеры свои у каждого потока вместо общих static let f1, f2. Разбор должен остаться прежним.
/// Эталон — прежняя реализация дословно: те же два ISO8601DateFormatter с теми же настройками, сначала f1
private func legacy(_ s: String) -> Date? {
    let f1 = ISO8601DateFormatter(); f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let f2 = ISO8601DateFormatter()
    return f1.date(from: s) ?? f2.date(from: s)
}

/// Разбор в текущем потоке и какие форматтеры после него лежат в этом потоке
private func probe(_ s: String) -> (date: Date?, f1: ObjectIdentifier?, f2: ObjectIdentifier?) {
    let d = Thread.current.threadDictionary
    return (ISO.date(s), (d[ISO.f1Key] as? ISO8601DateFormatter).map(ObjectIdentifier.init), (d[ISO.f2Key] as? ISO8601DateFormatter).map(ObjectIdentifier.init))
}

final class ISODateTests: XCTestCase {
    private func assertSameAsLegacy(_ cases: [String], file: StaticString = #filePath, line: UInt = #line) {
        for s in cases {
            XCTAssertEqual(ISO.date(s), legacy(s), "«\(s)»", file: file, line: line)
        }
    }

    /// Сервер (toISOString — миллисекунды и Z; created_at ЮKassa — так же) и строки, которые собирает приложение
    /// (дата акции или предзаказа «ГГГГ-ММ-ДД» + «T12:00:00Z»). Все они — даты
    func test01_ServerAndAppFormats() {
        let cases = ["2026-11-18T10:00:00.123Z", "2026-11-18T10:00:00.000Z", "2026-12-31T23:59:59.999Z", "2026-11-18T10:00:00Z",
                     "2026-03-01" + "T12:00:00Z", "2024-02-29" + "T12:00:00Z", "2026-11-18T13:00:00+03:00", "2026-11-18T13:00:00.500+03:00"]
        assertSameAsLegacy(cases)
        for s in cases { XCTAssertNotNil(ISO.date(s), s) }
    }

    /// Доли секунды разной длины — сколько цифр принималось и с какой точностью, так и остаётся
    func test02_FractionalSeconds() {
        assertSameAsLegacy(["2026-11-18T10:00:00.1Z", "2026-11-18T10:00:00.12Z", "2026-11-18T10:00:00.1234Z", "2026-11-18T10:00:00.123456Z",
                            "2026-11-18T10:00:00.123456789Z", "2026-11-18T10:00:00.1234567891Z", "2026-11-18T10:00:00.Z", "2026-11-18T10:00:00.123"])
    }

    /// Лишние символы до и после даты, несуществующие дни и время, другие записи даты и пояса, не даты
    func test03_IrregularAndInvalid() {
        assertSameAsLegacy(["2026-11-18T10:00:00Zx", "2026-11-18T10:00:00Z ", " 2026-11-18T10:00:00Z", "2026-11-18T10:00:00.123Z\n", "2026-11-18T10:00:00+03:00x",
                            "2026-02-30T10:00:00Z", "2026-02-29T10:00:00Z", "2026-04-31T10:00:00Z", "2026-13-01T10:00:00Z", "2026-00-10T10:00:00Z",
                            "2026-11-18T24:00:00Z", "2026-11-18T25:00:00Z", "2026-11-18T10:60:00Z", "2026-11-18T10:00:60Z",
                            "2026-11-18T10:00:00+0300", "2026-11-18T10:00:00+03", "2026-11-18T10:00:00GMT", "2026-11-18 10:00:00Z", "2026-11-18t10:00:00z",
                            "20261118T100000Z", "2026-11-18T10:00Z", "2026-11-18", "2026-11-18T10:00:00", "", "не дата", "17.11.2026", "18.11.2026"])
    }

    /// Заказ с сервера разбирает даты (создан, срок оплаты, история) так же, как прежняя реализация
    func test04_OrderDecoding() {
        let at = ["2026-11-18T10:00:00.123Z", "2026-11-18T10:00:00Z", "", "18.11.2026", "2026-11-18T10:00:00Zx"]
        let o = Order(JSON(["id": "o1", "createdAt": at[0], "payBy": at[1], "history": at.map { ["at": $0, "text": $0] }]))
        XCTAssertEqual(o.createdAt, legacy(at[0])); XCTAssertNotNil(o.createdAt)
        XCTAssertEqual(o.payBy, legacy(at[1])); XCTAssertNotNil(o.payBy)
        XCTAssertEqual(o.history.map { $0.text }, at)
        XCTAssertEqual(o.history.map { $0.at }, at.map(legacy))
    }

    /// Форматтер создаётся в потоке один раз и дальше берётся тот же; у другого потока — свой экземпляр.
    /// f2 — только когда понадобился
    func test05_OneFormatterPerThread() async {
        let s = "2026-11-18T10:00:00Z"
        let a = await MainActor.run { probe(s) }, b = await MainActor.run { probe(s) }
        let c = await Task.detached { probe(s) }.value
        // f2 нужен, если прежний f1 строку не разобрал — так было и раньше
        let f1Old = ISO8601DateFormatter(); f1Old.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let needsF2 = f1Old.date(from: s) == nil
        XCTAssertNotNil(a.f1); XCTAssertNotNil(c.f1); XCTAssertEqual(a.f2 != nil, needsF2); XCTAssertEqual(c.f2 != nil, needsF2)
        XCTAssertEqual(a.f1, b.f1, "Тот же поток — тот же форматтер, не новый на каждый разбор"); XCTAssertEqual(a.f2, b.f2)
        XCTAssertNotEqual(a.f1, c.f1, "Другой поток — свой форматтер")
        if needsF2 { XCTAssertNotEqual(a.f2, c.f2) }
        XCTAssertEqual(a.date, legacy(s)); XCTAssertEqual(c.date, legacy(s))
        // много разборов одновременно — результаты те же, что у прежней реализации
        let inputs = ["2026-11-18T10:00:00.123Z", "2026-11-18T10:00:00Z", "2026-11-18T13:00:00+03:00", "не дата"]
        let parsed = await withTaskGroup(of: (Int, Date?).self) { g in
            for i in 0..<200 { g.addTask { (i, ISO.date(inputs[i % inputs.count])) } }
            var r = [(Int, Date?)](); for await x in g { r.append(x) }
            return r
        }
        XCTAssertEqual(parsed.count, 200)
        for (i, d) in parsed { XCTAssertEqual(d, legacy(inputs[i % inputs.count]), inputs[i % inputs.count]) }
    }
}
