import XCTest
@testable import Albakov

/// Этап L.2.11: настройки сайта и элементы коллекций уходят из панели как RequestBody — записываются на главном акторе,
/// где их собирают экраны. Контракт с сервером прежний: PUT admin/settings и PUT admin/<коллекция>/<id>, тело {"value": …}
/// с той же вложенностью и теми же значениями; недопустимое значение — ошибка до отправки
@MainActor
final class AdminAPIBodyTests: XCTestCase {
    /// Последний запрос по этому пути (журнал NetStub общий — по пути, а не просто последний) и его тело, разобранное обратно
    private func sent(_ path: String) throws -> (seen: NetStub.Seen, body: NSDictionary) {
        let seen = try XCTUnwrap(NetStub.seen.last { $0.path == path }, "Запроса \(path) не было")
        let data = try XCTUnwrap(seen.body, "Запрос без тела")
        return (seen, try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? NSDictionary))
    }

    /// Настройки целиком, с вложенными объектами и массивами, — в «value», ключ в ключ, значение в значение
    func test01_SaveSettingsContract() async throws {
        NetStub.reset { _, _ in .json(["ok": true]) }
        let s: [String: Any] = [
            "storeName": "ALBAKOV", "rate": 12.5, "limit": 3,
            "slider": ["autoplay": true, "slides": [["id": "sl1", "title": "Новая\n*коллекция*", "btn1": ["label": "Смотреть", "link": "#/catalog"]]]],
            "payment": ["online": true, "cod": false, "yookassa": ["shopId": "123", "taxSystem": 2]],
            "notify": ["enabled": false, "text": "{товар} снова в наличии — «{цвет}», −10%"],
            "seo": ["yandex": "", "indexnow": NSNull()]
        ]
        try await AdminAPI.saveSettings(s, api: NetStub.api())
        let (seen, body) = try sent("admin/settings")
        XCTAssertEqual(seen.method, "PUT")
        XCTAssertEqual(seen.headers["Content-Type"], "application/json")
        XCTAssertEqual(body, NSDictionary(dictionary: ["value": s]), "Тело настроек изменилось")
    }

    /// Элемент коллекции — PUT по его id, тело {"value": элемент}; ответ сервера возвращается как есть
    func test02_UpsertContract() async throws {
        NetStub.reset { _, _ in .json(["ok": true, "value": ["id": "p1", "updatedAt": "2026-11-21T10:00:00.000Z"]]) }
        let item: [String: Any] = ["id": "p1", "name": "Футболка", "price": 4200, "hidden": false, "tags": ["new"],
                                   "colors": [["id": "c1", "name": "Белый", "images": ["uploads/a.jpg"], "sizes": [["size": "S", "stock": 3]]]]]
        let r = try await AdminAPI.upsert("products", item, api: NetStub.api())
        let (seen, body) = try sent("admin/products/p1")
        XCTAssertEqual(seen.method, "PUT")
        XCTAssertEqual(body, NSDictionary(dictionary: ["value": item]), "Тело элемента изменилось")
        XCTAssertEqual(r["value"]["updatedAt"].str, "2026-11-21T10:00:00.000Z")
    }

    /// Значение, которое нельзя записать в JSON, — та же ошибка, что раньше (APIError.invalidBody), и запрос не уходит
    func test03_InvalidValueNotSent() async {
        NetStub.reset { _, _ in .json(["ok": true]) }
        do { try await AdminAPI.saveSettings(["sale": ["endsAt": Date()]], api: NetStub.api()); XCTFail("Настройки с датой ушли без ошибки") }
        catch { XCTAssertEqual((error as? APIError)?.status, APIError.invalidBody.status, "\(error)") }
        do { _ = try await AdminAPI.upsert("products", ["id": "p1", "price": Double.nan], api: NetStub.api()); XCTFail("Товар с NaN ушёл без ошибки") }
        catch { XCTAssertEqual((error as? APIError)?.status, APIError.invalidBody.status, "\(error)") }
        XCTAssertTrue(NetStub.paths().filter { $0.hasPrefix("admin/") }.isEmpty, "Запрос с недопустимым телом дошёл до сервера")
    }
}
