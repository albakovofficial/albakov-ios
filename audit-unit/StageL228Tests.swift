import XCTest
import Combine
@testable import Albakov

/// Этап L.2.28: «Сохранить» во время загрузки фото. Пока хоть одно поле фото формы грузит (PhotoUpload.busy), AdminPage
/// не даёт сохранить форму: поля сообщают busy через PhotoUploadingKey, AdminPage объединяет их reduce. Здесь — то же
/// объединение (настоящий PhotoUploadingKey.reduce) по нескольким полям одной формы, настоящий PhotoUpload и запись фото
/// в Binding поля Doc, как в ImageField. Загрузки — «ворота», которые тест открывает сам (успехом или ошибкой), без пауз.
/// Сам экран (onPreferenceChange в AdminPage, затемнённая кнопка) модульным тестом не проверить
@MainActor
final class SaveDuringPhotoUploadTests: XCTestCase {
    private struct Boom: Error { let name: String }
    private var gates: [String: CheckedContinuation<String, any Error>] = [:]
    private var shown: [String] = [], finished: [String] = []
    /// Форма с двумя полями фото. lazy: Doc — главного актора, а инициализаторы XCTestCase не изолированы
    private lazy var doc = Doc(["hero": "old-hero.jpg", "editorial": "old-ed.jpg"])
    /// Состояние формы в моменты, когда «Сохранить» становилась доступной (что ушло бы на сервер при нажатии)
    private var savable: [[String: String]] = []
    private var subs: [AnyCancellable] = []

    /// Можно ли сохранить форму: как AdminPage — ни одно поле фото не грузит
    private func canSave(_ fields: [PhotoUpload]) -> Bool {
        var v = PhotoUploadingKey.defaultValue
        for f in fields { PhotoUploadingKey.reduce(value: &v) { f.busy } }
        return !v
    }
    /// Поле фото формы: каждый раз, когда загрузка в нём заканчивается, запоминается, что в этот момент лежит в форме
    private func field() -> PhotoUpload {
        let u = PhotoUpload()
        subs.append(u.$busy.dropFirst().filter { !$0 }.sink { [self] _ in
            savable.append(["hero": doc.str("hero"), "editorial": doc.str("editorial")])
        })
        return u
    }
    /// Выбрать фото name для поля k — как .onChange(of: item) в ImageField
    private func pick(_ u: PhotoUpload, _ k: String, _ name: String) async throws {
        let value = doc.text(k)
        u.start({ [self] () async throws -> String in
            defer { finished.append(name) }
            return try await withCheckedThrowingContinuation { gates[name] = $0 }
        }, apply: { value.wrappedValue = $0 }, fail: { [self] in shown.append(($0 as? Boom)?.name ?? "\($0)") })
        let started = try await until { self.gates[name] != nil }
        XCTAssertTrue(started, "Загрузка \(name) не началась")
    }
    /// Сервер ответил на загрузку name (или ошибкой)
    private func answer(_ name: String, failing: Bool = false) async throws {
        let g = try XCTUnwrap(gates.removeValue(forKey: name), "Загрузка \(name) не ждёт ответа")
        if failing { g.resume(throwing: Boom(name: name)) } else { g.resume(returning: name + ".jpg") }
        let done = try await until { self.finished.contains(name) }
        XCTAssertTrue(done, "Загрузка \(name) не завершилась")
    }

    /// Пока фото грузится, сохранить нельзя; доступной «Сохранить» становится, когда новое фото уже в форме
    func test01_SaveWaitsForUploadedPhoto() async throws {
        let hero = field()
        XCTAssertTrue(canSave([hero]))
        try await pick(hero, "hero", "A")
        XCTAssertFalse(canSave([hero]), "Во время загрузки форму можно сохранить — сохранится прежнее фото")
        try await answer("A")
        XCTAssertTrue(canSave([hero]))
        XCTAssertEqual(savable, [["hero": "A.jpg", "editorial": "old-ed.jpg"]], "«Сохранить» стала доступной раньше, чем фото попало в форму")
        XCTAssertEqual(shown, [])
    }

    /// Загрузка не удалась: ошибка показана, сохранить снова можно, в форме прежнее фото
    func test02_FailedUploadUnblocksSave() async throws {
        let hero = field()
        try await pick(hero, "hero", "A")
        try await answer("A", failing: true)
        XCTAssertTrue(canSave([hero]), "После ошибки загрузки форму нельзя сохранить")
        XCTAssertEqual(shown, ["A"]); XCTAssertEqual(doc.str("hero"), "old-hero.jpg")
        XCTAssertEqual(savable, [["hero": "old-hero.jpg", "editorial": "old-ed.jpg"]])
    }

    /// Два поля фото в одной форме: пока грузится хоть одно, сохранить нельзя; когда оба загрузились — в форме оба фото
    func test03_TwoPhotoFieldsInOneForm() async throws {
        let hero = field(), editorial = field()
        try await pick(hero, "hero", "H"); try await pick(editorial, "editorial", "E")
        XCTAssertFalse(canSave([hero, editorial]))
        try await answer("H")
        XCTAssertFalse(canSave([hero, editorial]), "Второе фото ещё грузится, а форму можно сохранить")
        try await answer("E")
        XCTAssertTrue(canSave([hero, editorial]))
        XCTAssertEqual(doc.str("hero"), "H.jpg"); XCTAssertEqual(doc.str("editorial"), "E.jpg")
        XCTAssertEqual(savable.last, ["hero": "H.jpg", "editorial": "E.jpg"])
    }

    /// Одно из двух фото не загрузилось: блокировку держит только второе поле, после него сохранить можно
    func test04_OneOfTwoFails() async throws {
        let hero = field(), editorial = field()
        try await pick(hero, "hero", "H"); try await pick(editorial, "editorial", "E")
        try await answer("H", failing: true)
        XCTAssertFalse(canSave([hero, editorial]), "Ошибка одного поля разблокировала форму, пока грузится другое")
        try await answer("E")
        XCTAssertTrue(canSave([hero, editorial]))
        XCTAssertEqual(doc.str("hero"), "old-hero.jpg"); XCTAssertEqual(doc.str("editorial"), "E.jpg"); XCTAssertEqual(shown, ["H"])
    }

    /// «Убрать» во время загрузки: сохранить можно сразу, поле пустое, поздний ответ сервера его не меняет
    func test05_RemoveDuringUploadUnblocksSave() async throws {
        let hero = field()
        try await pick(hero, "hero", "A")
        hero.cancel(); doc.text("hero").wrappedValue = ""   // как кнопка «Убрать» в ImageField
        XCTAssertTrue(canSave([hero]), "После «Убрать» форму нельзя сохранить")
        XCTAssertEqual(doc.str("hero"), "")
        try await answer("A")
        XCTAssertTrue(canSave([hero])); XCTAssertEqual(doc.str("hero"), "", "Поздний ответ вернул убранное фото"); XCTAssertEqual(shown, [])
    }

    /// Фото A заменили на B: ответ на устаревшую A не разблокирует сохранение, пока грузится B
    func test06_StaleUploadKeepsSaveBlocked() async throws {
        let hero = field()
        try await pick(hero, "hero", "A"); try await pick(hero, "hero", "B")
        try await answer("A")
        XCTAssertFalse(canSave([hero]), "Устаревшая загрузка разблокировала «Сохранить», пока грузится новое фото")
        XCTAssertEqual(doc.str("hero"), "old-hero.jpg")
        try await answer("B")
        XCTAssertTrue(canSave([hero])); XCTAssertEqual(savable, [["hero": "B.jpg", "editorial": "old-ed.jpg"]])
    }

    /// Объединение по полям формы: нет полей или ни одно не грузит — можно; грузит любое — нельзя
    func test07_ReduceAcrossFields() {
        func merged(_ xs: [Bool]) -> Bool { var v = PhotoUploadingKey.defaultValue; for x in xs { PhotoUploadingKey.reduce(value: &v) { x } }; return v }
        XCTAssertFalse(merged([])); XCTAssertFalse(merged([false, false, false]))
        XCTAssertTrue(merged([true, false, false])); XCTAssertTrue(merged([false, false, true])); XCTAssertTrue(merged([false, true, false]))
    }
}
