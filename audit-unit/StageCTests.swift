import XCTest
@testable import Albakov

/// Юнит-тесты этапа C. Только проверка, в приложение не входят. Собираются целью AlbakovUnit (audit.yml).

// MARK: - Q-B2: шаблоны ответов поддержки

/// Модель листа «Шаблоны ответов» (SupportTemplatesSheet): список (название, текст) и ключи RowKeys.
/// Каждый вызов ниже — тот же, что делает лист: поле пишет через update по ключу, свайп — remove(atOffsets:),
/// «Добавить шаблон» — append. Ключи подстроены сразу, как в init листа.
final class SupportTemplatesTests: XCTestCase {
    private typealias Row = (String, String)
    private func rows(_ n: Int) -> [Row] { (0..<n).map { ("Шаблон \($0)", "Текст \($0)") } }
    private func titles(_ r: [Row]) -> [String] { r.map { $0.0 } }
    private func matched(_ n: Int) -> RowKeys { var k = RowKeys(); k.match(count: n); return k }
    /// Запись из поля «Название» строки с ключом id — как Binding.set в листе
    @discardableResult private func type(_ v: String, _ id: UUID, _ k: RowKeys, _ r: inout [Row]) -> Bool { k.update(id, in: &r) { $0.0 = v } }

    /// Правка: меняется только та строка, в поле которой печатают
    func test01_EditChangesOnlyThisRow() {
        var r = rows(3); let k = matched(3); let ids = k.displayKeys(count: 3)
        XCTAssertTrue(k.update(ids[1], in: &r) { $0.1 = "Новый текст" })
        XCTAssertTrue(type("Доставка", ids[1], k, &r))
        XCTAssertEqual(titles(r), ["Шаблон 0", "Доставка", "Шаблон 2"])
        XCTAssertEqual(r.map { $0.1 }, ["Текст 0", "Новый текст", "Текст 2"])
        XCTAssertEqual(k.row(ids[1], in: r)?.0, "Доставка")
    }

    /// Удаление свайпом строки, пока её поле в фокусе: поле при потере фокуса пишет ещё раз —
    /// запись никуда не попадает и не падает (раньше: list[i] по старому номеру — «Index out of range» или чужой шаблон)
    func test02_DeleteWhileEditingDropsLateWrite() {
        // последняя строка: старый номер выходит за список
        var r = rows(3); var k = matched(3); var ids = k.displayKeys(count: 3)
        k.remove(atOffsets: [2], from: &r)
        XCTAssertFalse(type("поздняя запись", ids[2], k, &r), "Запись в удалённый шаблон")
        XCTAssertNil(k.row(ids[2], in: r), "Поле удалённой строки что-то показывает")
        XCTAssertEqual(titles(r), ["Шаблон 0", "Шаблон 1"])
        // средняя строка: старый номер теперь у соседа — запись не должна попасть в него
        r = rows(3); k = matched(3); ids = k.displayKeys(count: 3)
        k.remove(atOffsets: [1], from: &r)
        XCTAssertFalse(type("поздняя запись", ids[1], k, &r))
        XCTAssertEqual(titles(r), ["Шаблон 0", "Шаблон 2"], "Поздняя запись попала в соседний шаблон")
    }

    /// После удаления правка соседних строк попадает именно в них, хотя их номера сдвинулись
    func test03_EditNeighbourAfterDelete() {
        var r = rows(4); var k = matched(4); let ids = k.displayKeys(count: 4)
        k.remove(atOffsets: [0], from: &r)
        XCTAssertTrue(type("второй", ids[1], k, &r))
        XCTAssertTrue(type("четвёртый", ids[3], k, &r))
        XCTAssertEqual(titles(r), ["второй", "Шаблон 2", "четвёртый"])
        XCTAssertEqual(k.displayKeys(count: r.count), Array(ids.dropFirst()), "Ключи оставшихся строк сменились — поля потеряют фокус")
    }

    /// Перестановка: ключ едет вместе со строкой, правка после неё — в ту же строку на новом месте
    func test04_MoveKeepsKeyWithRow() {
        var r = rows(3); var k = matched(3); let ids = k.displayKeys(count: 3)
        k.move(ids[0], by: 1, in: &r)
        XCTAssertEqual(titles(r), ["Шаблон 1", "Шаблон 0", "Шаблон 2"])
        XCTAssertEqual(k.displayKeys(count: 3), [ids[1], ids[0], ids[2]])
        XCTAssertTrue(type("первый", ids[0], k, &r))
        XCTAssertEqual(titles(r), ["Шаблон 1", "первый", "Шаблон 2"])
        k.move(ids[2], by: 1, in: &r)   // за границу — ничего не меняется
        XCTAssertEqual(titles(r), ["Шаблон 1", "первый", "Шаблон 2"])
    }

    /// «Добавить шаблон»: новая строка с новым ключом, прежние ключи и строки на месте
    func test05_AddKeepsExistingKeys() {
        var r = rows(2); var k = matched(2); let ids = k.displayKeys(count: 2)
        k.append(("", ""), to: &r)
        let after = k.displayKeys(count: r.count)
        XCTAssertEqual(after.count, 3); XCTAssertEqual(Array(after.prefix(2)), ids)
        XCTAssertFalse(ids.contains(after[2]))
        XCTAssertTrue(k.update(after[2], in: &r) { $0 = ("Возврат", "Текст возврата") })
        XCTAssertTrue(type("Первый", ids[0], k, &r))
        XCTAssertEqual(titles(r), ["Первый", "Шаблон 1", "Возврат"])
    }

    /// Несколько удалений подряд (по одному и сразу несколько): ключи и строки остаются согласованы,
    /// поздние записи удалённых строк никуда не попадают, оставшиеся строки правятся по своим ключам
    func test06_SequentialDeletes() {
        var r = rows(6); var k = matched(6); let ids = k.displayKeys(count: 6)
        k.remove(atOffsets: [1], from: &r)          // «Шаблон 1»
        k.remove(atOffsets: [0, 2], from: &r)       // «Шаблон 0» и «Шаблон 3» — свайп двух сразу
        k.remove(atOffsets: [2], from: &r)          // «Шаблон 5»
        XCTAssertEqual(titles(r), ["Шаблон 2", "Шаблон 4"])
        XCTAssertEqual(k.displayKeys(count: r.count), [ids[2], ids[4]], "Ключи разошлись со строками")
        for gone in [0, 1, 3, 5] { XCTAssertFalse(type("поздняя", ids[gone], k, &r)) }
        XCTAssertTrue(type("четвёртый", ids[4], k, &r))
        XCTAssertEqual(titles(r), ["Шаблон 2", "четвёртый"])
        k.remove(atOffsets: [0, 1], from: &r)
        XCTAssertTrue(r.isEmpty); XCTAssertEqual(k.displayKeys(count: 0), [])
    }

    /// Номер вне списка или ключи, не подстроенные под список, ничего не удаляют: стереть чужой шаблон хуже, чем не стереть
    func test07_OutOfRangeOrUnmatchedRemoveNothing() {
        var r = rows(2); var k = matched(2); let ids = k.displayKeys(count: 2)
        k.remove(atOffsets: [1, 2], from: &r)
        XCTAssertEqual(titles(r), ["Шаблон 0", "Шаблон 1"])
        XCTAssertEqual(k.displayKeys(count: 2), ids)
        var other = matched(3)
        other.remove(atOffsets: [0], from: &r)
        XCTAssertEqual(titles(r), ["Шаблон 0", "Шаблон 1"])
    }
}

// MARK: - Q-B8: проверка тела запроса перед JSONSerialization

final class APIBodyTests: XCTestCase {
    /// Тело как у настоящего заказа: вложенные словари и массивы, целые, дробные, логические, строки, null
    private let order: [String: Any] = ["lines": [["productId": "p5", "colorId": "c1", "size": "L", "qty": 1]], "deliveryId": "pvz",
                                        "payment": "online", "useBonus": false, "lat": 55.75, "comment": NSNull(),
                                        "customer": ["firstName": "Пётр", "phone": "79070000001"], "consent": true]
    private func isInvalidBody(_ error: Error) -> Bool { (error as? APIError)?.status == APIError.invalidBody.status }

    /// Корректное тело записывается так же, как раньше JSONSerialization.data — сервер получает те же байты
    func test01_ValidBodyUnchanged() throws {
        let small: [String: Any] = ["qty": 2, "name": "Футболка", "ok": true, "price": 1990.5, "none": NSNull(), "tags": ["a"]]
        XCTAssertEqual(String(decoding: try JSONSerialization.checkedData(small, options: [.sortedKeys]), as: UTF8.self),
                       #"{"name":"Футболка","none":null,"ok":true,"price":1990.5,"qty":2,"tags":["a"]}"#)
        let req = try API.shared.request("POST", "orders", body: RequestBody(order), query: [:])
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(req.httpBody, try JSONSerialization.data(withJSONObject: order))
        XCTAssertEqual(req.url?.path, "/api/orders")
    }

    /// Недопустимые значения — ошибка APIError.invalidBody, а не падение приложения исключением Objective-C.
    /// NaN и бесконечность — например, «nan» или «1e999» в поле «Цена ±%» массовых изменений (Double(…) их принимает)
    func test02_InvalidValuesThrowTypedError() {
        struct Custom {}
        let bad: [(String, Any)] = [("NaN", Double.nan), ("бесконечность", Double.infinity), ("минус бесконечность", -Double.infinity),
                                    ("дата", Date()), ("адрес", URL(fileURLWithPath: "/tmp")), ("данные", Data([1, 2])),
                                    ("свой тип", Custom()), ("ключ не строка", [1: "x"]), ("вложенный NaN", ["lines": [["qty": Double.nan]]])]
        for (name, v) in bad {
            XCTAssertThrowsError(try JSONSerialization.checkedData(["value": v]), name) { XCTAssertTrue(isInvalidBody($0), "\(name): \($0)") }
            XCTAssertThrowsError(try API.shared.request("POST", "admin/products/bulk", body: ["value": v], query: [:]), name) { XCTAssertTrue(isInvalidBody($0)) }
        }
    }

    /// Пустое тело: nil — запрос без тела и без Content-Type (GET и POST без данных, как раньше);
    /// пустой словарь (AdminAPI.post без данных) — «{}»
    func test03_EmptyBody() throws {
        let none = try API.shared.request("GET", "state", body: nil, query: ["q": "1"])
        XCTAssertNil(none.httpBody); XCTAssertNil(none.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertEqual(none.url?.query, "q=1")
        let empty = try API.shared.request("POST", "admin/payment-secret", body: [:], query: [:])
        XCTAssertEqual(empty.httpBody, Data("{}".utf8))
        XCTAssertEqual(empty.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    /// Ошибка сериализации доходит до экрана как обычная ошибка: понятный текст, не «отмена», запрос не уходит.
    /// Ключ повтора заказа и сертификата (CheckoutNonce.idem) — та же проверка и та же ошибка
    func test04_SerializationErrorReachesUser() async throws {
        do {
            _ = try await API.shared.raw("POST", "admin/products/bulk", body: ["ids": ["p1"], "action": "percent", "value": Double.nan])
            XCTFail("Запрос с NaN ушёл без ошибки")
        } catch {
            XCTAssertTrue(isInvalidBody(error), "\(error)")
            XCTAssertFalse(error.isCancel)
            XCTAssertEqual(error.userMessage, APIError.invalidBody.message)
        }
        XCTAssertThrowsError(try CheckoutNonce.idem("n", ["total": Double.infinity])) { XCTAssertTrue(isInvalidBody($0)) }
    }
}
