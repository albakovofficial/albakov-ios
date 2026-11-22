import XCTest
import Combine
@testable import Albakov

/// Этап L.2.29: «Сохранить» во время загрузки логотипа (LogoSlot → PhotoUpload) и фото цвета (ColorPhotos →
/// PhotoBatchUpload). Поля сообщают busy через PhotoUploadingKey, AdminPage объединяет его reduce по всем полям формы.
/// Здесь — настоящие PhotoUpload, PhotoBatchUpload и PhotoUploadingKey.reduce; запись результата — как в полях: логотип
/// в настройки бренда, фото цвета — добавлением к фото цвета товара (Doc). Загрузки — «ворота», которые тест открывает
/// сам (успехом или ошибкой), без пауз. Сам экран (onPreferenceChange, затемнённая кнопка) модульным тестом не проверить
@MainActor
final class SaveDuringLogoAndColorUploadTests: XCTestCase {
    private struct Boom: Error { let name: String }
    private var gates: [String: CheckedContinuation<String, any Error>] = [:]
    private var shown: [String] = [], finished: [String] = []
    /// Настройки бренда (b в AdminBrand) и карточка товара с двумя цветами
    private var brand: [String: String] = ["mark": "old-mark.png", "word": "old-word.png"]
    /// lazy: Doc — главного актора, а инициализаторы XCTestCase не изолированы
    private lazy var product: Doc = {
        let colors: [[String: Any]] = [["id": "c1", "images": ["c1-0.jpg"]], ["id": "c2", "images": [String]()]]
        return Doc(["colors": colors])
    }()
    /// Что лежит в форме в моменты, когда загрузка поля закончилась
    private var snapshots: [String] = []
    private var subs: [AnyCancellable] = []

    // MARK: Поля формы

    /// Можно ли сохранить форму: как AdminPage — ни одно поле не грузит
    private func canSave(_ busy: [Bool]) -> Bool {
        var v = PhotoUploadingKey.defaultValue
        for b in busy { PhotoUploadingKey.reduce(value: &v) { b } }
        return !v
    }
    private func images(_ color: Int) -> [String] {
        ((product.v["colors"] as? [[String: Any]])?[color]["images"] as? [String]) ?? []
    }
    private func state() -> String { "mark=\(brand["mark"] ?? "") word=\(brand["word"] ?? "") c1=\(images(0)) c2=\(images(1))" }
    private func logoSlot() -> PhotoUpload {
        let u = PhotoUpload()
        subs.append(u.$busy.dropFirst().filter { !$0 }.sink { [unowned self] _ in snapshots.append(state()) })
        return u
    }
    private func colorPhotos() -> PhotoBatchUpload {
        let u = PhotoBatchUpload()
        subs.append(u.$running.dropFirst().filter { $0 == 0 }.sink { [unowned self] _ in snapshots.append(state()) })
        return u
    }
    /// Ворота загрузки name: ждут, пока тест ответит
    private func gate(_ name: String) async throws -> String {
        defer { finished.append(name) }
        return try await withCheckedThrowingContinuation { gates[name] = $0 }
    }
    /// Выбрать логотип name для места k (mark / word) — как .onChange(of: item) в LogoSlot
    private func pickLogo(_ u: PhotoUpload, _ k: String, _ name: String) async throws {
        u.start({ [self] in try await gate(name) }, apply: { [self] in brand[k] = $0 }, fail: { [self] in shown.append(($0 as? Boom)?.name ?? "\($0)") })
        let started = try await until { self.gates[name] != nil }
        XCTAssertTrue(started, "Загрузка \(name) не началась")
    }
    /// Выбрать фото names для цвета color — как .onChange(of: picks) в ColorPhotos (add — добавить к фото этого цвета)
    private func pickPhotos(_ u: PhotoBatchUpload, color: Int, _ names: [String]) async throws {
        u.start(names, { [self] in try await gate($0) }, add: { [self] url in
            var cs = product.v["colors"] as? [[String: Any]] ?? []
            cs[color]["images"] = ((cs[color]["images"] as? [String]) ?? []) + [url]
            product.v["colors"] = cs
        }, fail: { [self] in shown.append(($0 as? Boom)?.name ?? "\($0)") })
        let started = try await until { self.gates[names[0]] != nil }
        XCTAssertTrue(started, "Загрузка \(names[0]) не началась")
    }
    /// Сервер ответил на name (или ошибкой); then — чего дождаться после ответа (по умолчанию — конца работы name)
    private func answer(_ name: String, failing: Bool = false, then next: String? = nil) async throws {
        let g = try XCTUnwrap(gates.removeValue(forKey: name), "Загрузка \(name) не ждёт ответа")
        if failing { g.resume(throwing: Boom(name: name)) } else { g.resume(returning: name + ".jpg") }
        let ok = try await until { next.map { self.gates[$0] != nil } ?? self.finished.contains(name) }
        XCTAssertTrue(ok, "После ответа на \(name) работа не продвинулась")
        if next != nil { let done = try await until { self.finished.contains(name) }; XCTAssertTrue(done) }
    }

    // MARK: Логотип (LogoSlot)

    /// 1, 7. Загрузка логотипа блокирует сохранение; доступной кнопка становится, когда новый логотип уже в настройках
    func test01_LogoUploadBlocksSave() async throws {
        let mark = logoSlot(), word = logoSlot()
        XCTAssertTrue(canSave([mark.busy, word.busy]))
        try await pickLogo(mark, "mark", "M")
        XCTAssertFalse(canSave([mark.busy, word.busy]), "Во время загрузки логотипа форму можно сохранить")
        try await answer("M")
        XCTAssertTrue(canSave([mark.busy, word.busy]))
        XCTAssertEqual(snapshots, ["mark=M.jpg word=old-word.png c1=[\"c1-0.jpg\"] c2=[]"], "«Сохранить» стала доступной раньше, чем логотип попал в настройки")
    }

    /// 3, 4. Знак и надпись грузятся одновременно; ошибка надписи не разблокирует, пока грузится знак
    func test02_TwoLogoSlotsAndError() async throws {
        let mark = logoSlot(), word = logoSlot()
        try await pickLogo(mark, "mark", "M"); try await pickLogo(word, "word", "W")
        try await answer("W", failing: true)
        XCTAssertEqual(shown, ["W"]); XCTAssertEqual(brand["word"], "old-word.png")
        XCTAssertFalse(canSave([mark.busy, word.busy]), "Ошибка надписи разблокировала форму, пока грузится знак")
        try await answer("M")
        XCTAssertTrue(canSave([mark.busy, word.busy])); XCTAssertEqual(brand["mark"], "M.jpg")
    }

    /// 5. «Отмена», затем «Убрать» во время загрузки знака (с L.2.33 — две кнопки по очереди) разблокирует сохранение; поздний ответ не возвращает убранный логотип
    func test03_LogoRemoveUnblocksSave() async throws {
        let mark = logoSlot()
        try await pickLogo(mark, "mark", "M")
        mark.cancel(); brand["mark"] = ""   // как «Отмена» (upload.cancel()), затем «Убрать» (set(nil)) в LogoSlot
        XCTAssertTrue(canSave([mark.busy]), "После «Отмена» и «Убрать» форму нельзя сохранить")
        try await answer("M")
        XCTAssertTrue(canSave([mark.busy])); XCTAssertEqual(brand["mark"], "", "Поздний ответ вернул убранный логотип"); XCTAssertEqual(shown, [])
    }

    /// 6. Знак A заменили на B: ответ на устаревшую A не меняет знак и не разблокирует, пока грузится B
    func test04_LogoStaleResultIgnored() async throws {
        let mark = logoSlot()
        try await pickLogo(mark, "mark", "A"); try await pickLogo(mark, "mark", "B")
        try await answer("A")
        XCTAssertEqual(brand["mark"], "old-mark.png", "Устаревший логотип записан"); XCTAssertFalse(canSave([mark.busy]))
        try await answer("B")
        XCTAssertEqual(brand["mark"], "B.jpg"); XCTAssertTrue(canSave([mark.busy]))
        XCTAssertEqual(snapshots, ["mark=B.jpg word=old-word.png c1=[\"c1-0.jpg\"] c2=[]"])
    }

    // MARK: Фото цвета (ColorPhotos)

    /// 2, 7. Загрузка нескольких фото цвета блокирует сохранение до последнего; тогда в карточке все фото, по порядку
    func test05_ColorPhotosBlockSave() async throws {
        let c1 = colorPhotos()
        try await pickPhotos(c1, color: 0, ["P1", "P2"])
        XCTAssertFalse(canSave([c1.busy]))
        try await answer("P1", then: "P2")
        XCTAssertEqual(images(0), ["c1-0.jpg", "P1.jpg"])
        XCTAssertFalse(canSave([c1.busy]), "Первое фото разблокировало форму, пока второе грузится")
        try await answer("P2")
        XCTAssertTrue(canSave([c1.busy]))
        XCTAssertEqual(snapshots, ["mark=old-mark.png word=old-word.png c1=[\"c1-0.jpg\", \"P1.jpg\", \"P2.jpg\"] c2=[]"])
    }

    /// 3. Второй выбор фото во время первой загрузки того же цвета: конец первой не разблокирует, пока идёт вторая;
    /// все фото обоих выборов добавлены
    func test06_ColorPhotosTwoPicksSameColor() async throws {
        let c1 = colorPhotos()
        try await pickPhotos(c1, color: 0, ["P1"]); try await pickPhotos(c1, color: 0, ["Q1", "Q2"])
        XCTAssertEqual(c1.running, 2)
        try await answer("P1")
        XCTAssertFalse(canSave([c1.busy]), "Конец первой загрузки разблокировал форму, пока идёт вторая")
        try await answer("Q1", then: "Q2"); try await answer("Q2")
        XCTAssertTrue(canSave([c1.busy])); XCTAssertEqual(images(0), ["c1-0.jpg", "P1.jpg", "Q1.jpg", "Q2.jpg"])
    }

    /// 3, 4. Фото двух цветов одной карточки: ошибка фото первого цвета не разблокирует, пока грузится второй цвет
    func test07_TwoColorsAndError() async throws {
        let c1 = colorPhotos(), c2 = colorPhotos()
        try await pickPhotos(c1, color: 0, ["P1"]); try await pickPhotos(c2, color: 1, ["R1"])
        try await answer("P1", failing: true)
        XCTAssertEqual(shown, ["P1"]); XCTAssertEqual(images(0), ["c1-0.jpg"])
        XCTAssertFalse(canSave([c1.busy, c2.busy]), "Ошибка одного цвета разблокировала форму, пока грузится другой")
        try await answer("R1")
        XCTAssertTrue(canSave([c1.busy, c2.busy])); XCTAssertEqual(images(1), ["R1.jpg"])
    }

    /// 4. Ошибка первого фото выбора не останавливает остальные и не разблокирует, пока они грузятся
    func test08_ColorPhotoErrorInsideBatch() async throws {
        let c1 = colorPhotos()
        try await pickPhotos(c1, color: 0, ["P1", "P2"])
        try await answer("P1", failing: true, then: "P2")
        XCTAssertEqual(shown, ["P1"]); XCTAssertFalse(canSave([c1.busy]))
        try await answer("P2")
        XCTAssertTrue(canSave([c1.busy])); XCTAssertEqual(images(0), ["c1-0.jpg", "P2.jpg"])
    }

    /// Форма без полей фото и пустой выбор: сохранять можно, загрузка не начинается
    func test09_NoUploadsNoBlock() {
        XCTAssertTrue(canSave([]))
        let c1 = colorPhotos()
        c1.start([String](), { _ in "" }, add: { _ in XCTFail("Пустой выбор что-то добавил") }, fail: { _ in })
        XCTAssertEqual(c1.running, 0); XCTAssertTrue(canSave([c1.busy]))
    }
}
