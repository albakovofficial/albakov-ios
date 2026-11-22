import XCTest
@testable import Albakov

/// Этап L.2.33: отмена загрузки фото. ImageField и LogoSlot — «Отмена» на время загрузки (PhotoUpload.cancel), ColorPhotos —
/// ✕ на плитке «Фото этого цвета» (PhotoBatchUpload.cancel). Здесь настоящие PhotoUpload, PhotoBatchUpload и
/// PhotoUploadingKey.reduce (как AdminPage решает, можно ли сохранить). Загрузка устроена как в полях: обработка фото
/// («имя: jpeg»), проверка отмены, отправка на сервер («имя: upload»); результат — в поле формы (Doc) или к фото цвета.
/// Обработка и ответ сервера — «ворота», которые тест открывает сам (успехом или ошибкой): порядок задаёт тест, без пауз.
/// Ограничения: замыкания полей здесь повторены, а не вызваны; скачивание из iCloud (PhotosPickerItem) в тесте не создать
@MainActor
final class UploadCancellationTests: XCTestCase {
    private struct Boom: Error { let name: String }
    private var gates: [String: CheckedContinuation<String, any Error>] = [:]
    private var sent: [String] = [], shown: [String] = [], finished: [String] = []
    /// Форма: два поля фото (hero пустое, editorial с фото) и два цвета товара. lazy: Doc — главного актора
    private lazy var doc: Doc = {
        let colors: [[String: Any]] = [["id": "c1", "images": ["c1-0.jpg"]], ["id": "c2", "images": [String]()]]
        return Doc(["hero": "", "editorial": "old-ed.jpg", "colors": colors])
    }()

    // MARK: Помощники

    private func gate(_ key: String) async throws -> String {
        try await withCheckedThrowingContinuation { gates[key] = $0 }
    }
    /// Загрузка одного фото, как в полях: обработка, проверка отмены, отправка
    private func work(_ name: String) async throws -> String {
        defer { finished.append(name) }
        _ = try await gate(name + ": jpeg")
        try Task.checkCancellation()
        sent.append(name)
        return try await gate(name + ": upload")
    }
    /// fail поля: каждый вызов записывается — и с ошибкой отмены тоже (в приложении он показал бы тост, если бы ошибка
    /// была не отменой), чтобы «fail после отмены не вызывался» проверялось честно
    private func show(_ e: any Error) { shown.append((e as? Boom)?.name ?? "\(type(of: e))") }
    /// Можно ли сохранить форму — как AdminPage: ни одно поле не грузит
    private func canSave(_ busy: [Bool]) -> Bool {
        var v = PhotoUploadingKey.defaultValue
        for b in busy { PhotoUploadingKey.reduce(value: &v) { b } }
        return !v
    }
    private func images(_ color: Int) -> [String] { ((doc.v["colors"] as? [[String: Any]])?[color]["images"] as? [String]) ?? [] }

    /// Выбрать фото name для поля k — как .onChange(of: item) в ImageField (fail — Toast.show(userMessage))
    private func pick(_ u: PhotoUpload, _ k: String, _ name: String) async throws {
        let field = doc.text(k)
        u.start({ [self] () async throws -> String in try await work(name) }, apply: { field.wrappedValue = $0 }, fail: { [self] in show($0) })
        let started = try await until { self.gates[name + ": jpeg"] != nil }
        XCTAssertTrue(started, "Загрузка \(name) не началась")
    }
    /// Выбрать фото names для цвета color — как .onChange(of: picks) в ColorPhotos (add — к фото этого цвета)
    private func pickPhotos(_ u: PhotoBatchUpload, color: Int, _ names: [String]) async throws {
        u.start(names, { [self] (n: String) async throws -> String in try await work(n) }, add: { [self] url in
            var cs = doc.v["colors"] as? [[String: Any]] ?? []
            cs[color]["images"] = ((cs[color]["images"] as? [String]) ?? []) + [url]
            doc.v["colors"] = cs
        }, fail: { [self] in show($0) })
        let started = try await until { self.gates[names[0] + ": jpeg"] != nil }
        XCTAssertTrue(started, "Загрузка \(names[0]) не началась")
    }
    /// Открыть ворота key (успехом или ошибкой) и дождаться then
    private func open(_ key: String, throwing error: (any Error)? = nil, then ready: () -> Bool) async throws {
        let g = try XCTUnwrap(gates.removeValue(forKey: key), "Никто не ждёт «\(key)»")
        let name = String(key.prefix { $0 != ":" })
        if let error { g.resume(throwing: error) } else { g.resume(returning: name + ".jpg") }
        let ok = try await until { ready() }
        XCTAssertTrue(ok, "После «\(key)» работа не продвинулась")
    }
    /// Обработка name закончилась — фото уходит на сервер
    private func processed(_ name: String) async throws { try await open(name + ": jpeg") { self.gates[name + ": upload"] != nil } }
    /// Сервер ответил на name (или ошибкой) — работа name закончилась
    private func answered(_ name: String, throwing error: (any Error)? = nil) async throws {
        try await open(name + ": upload", throwing: error) { self.finished.contains(name) }
    }

    // MARK: ImageField / LogoSlot — PhotoUpload

    /// 1. Пустое поле: «Отмена» во время отправки — busy гаснет сразу, сохранить можно, поле пустое; поздний ответ сервера
    /// в поле не попадает
    func test01_CancelInEmptyField() async throws {
        let hero = PhotoUpload()
        try await pick(hero, "hero", "A"); try await processed("A")
        XCTAssertFalse(canSave([hero.busy]))
        hero.cancel()   // «Отмена»
        XCTAssertFalse(hero.busy); XCTAssertTrue(canSave([hero.busy]), "После «Отмена» форму нельзя сохранить")
        XCTAssertEqual(doc.str("hero"), "")
        try await answered("A")
        XCTAssertEqual(doc.str("hero"), "", "Поздний ответ записал фото после «Отмена»")
        XCTAssertFalse(hero.busy); XCTAssertEqual(shown, [])
    }

    /// 2. Замена фото: «Отмена» оставляет прежнее фото, ответ сервера его не заменяет
    func test02_CancelReplacementKeepsOldPhoto() async throws {
        let editorial = PhotoUpload()
        try await pick(editorial, "editorial", "A"); try await processed("A")
        editorial.cancel()
        XCTAssertEqual(doc.str("editorial"), "old-ed.jpg", "«Отмена» стёрла прежнее фото")
        try await answered("A")
        XCTAssertEqual(doc.str("editorial"), "old-ed.jpg", "Поздний ответ заменил прежнее фото"); XCTAssertEqual(shown, [])
    }

    /// 3. «Отмена» во время обработки: фото на сервер не уходит (Task.checkCancellation перед отправкой)
    func test03_CancelBeforeSending() async throws {
        let hero = PhotoUpload()
        try await pick(hero, "hero", "A")
        hero.cancel()
        try await open("A: jpeg") { self.finished.contains("A") }
        XCTAssertEqual(sent, [], "Отменённое фото отправлено на сервер"); XCTAssertNil(gates["A: upload"])
        XCTAssertEqual(shown, [], "Отмена показана как ошибка"); XCTAssertEqual(doc.str("hero"), ""); XCTAssertFalse(hero.busy)
    }

    /// 4. «Отмена», затем новый выбор: новое фото загружается как обычно; поздний ответ отменённой загрузки не гасит
    /// «Загружаю…» новой и не разблокирует сохранение
    func test04_CancelThenNewPick() async throws {
        let hero = PhotoUpload()
        try await pick(hero, "hero", "A"); try await processed("A")
        hero.cancel()
        try await pick(hero, "hero", "B")
        try await answered("A")
        XCTAssertTrue(hero.busy, "Отменённая загрузка погасила «Загружаю…» новой"); XCTAssertFalse(canSave([hero.busy]))
        XCTAssertEqual(doc.str("hero"), "")
        try await processed("B"); try await answered("B")
        XCTAssertEqual(doc.str("hero"), "B.jpg"); XCTAssertFalse(hero.busy); XCTAssertTrue(canSave([hero.busy]))
    }

    /// 5. Два поля в форме: «Отмена» в одном не разблокирует сохранение, пока грузит другое, и не трогает его загрузку
    func test05_CancelOneWhileOtherActive() async throws {
        let hero = PhotoUpload(), editorial = PhotoUpload()
        try await pick(hero, "hero", "H"); try await pick(editorial, "editorial", "E")
        hero.cancel()
        XCTAssertFalse(hero.busy); XCTAssertTrue(editorial.busy, "«Отмена» одного поля сбросила загрузку другого")
        XCTAssertFalse(canSave([hero.busy, editorial.busy]), "«Отмена» одного поля разблокировала форму, пока грузит другое")
        try await processed("E"); try await answered("E")
        XCTAssertTrue(canSave([hero.busy, editorial.busy])); XCTAssertEqual(doc.str("editorial"), "E.jpg"); XCTAssertEqual(doc.str("hero"), "")
        try await open("H: jpeg") { self.finished.contains("H") }
        XCTAssertEqual(sent, ["E"], "Отменённое фото отправлено на сервер"); XCTAssertEqual(doc.str("hero"), ""); XCTAssertEqual(shown, [])
    }

    // MARK: ColorPhotos — PhotoBatchUpload

    /// 6. Три фото цвета: первое добавлено, второе обрабатывается — ✕: первое остаётся, второе не отправляется и не
    /// добавляется, третье не начинается; сохранить можно сразу
    func test06_CancelQueueAfterFirstAdded() async throws {
        let c1 = PhotoBatchUpload()
        try await pickPhotos(c1, color: 0, ["P1", "P2", "P3"])
        try await processed("P1")
        try await open("P1: upload") { self.gates["P2: jpeg"] != nil }
        XCTAssertEqual(images(0), ["c1-0.jpg", "P1.jpg"])
        c1.cancel()   // ✕ на плитке
        XCTAssertEqual(c1.running, 0); XCTAssertTrue(canSave([c1.busy]), "После ✕ форму нельзя сохранить")
        try await open("P2: jpeg") { self.finished.contains("P2") }
        XCTAssertEqual(sent, ["P1"], "После ✕ фото отправлено на сервер")
        XCTAssertNil(gates["P3: jpeg"], "После ✕ началась загрузка следующего фото")
        XCTAssertEqual(images(0), ["c1-0.jpg", "P1.jpg"], "✕ удалил добавленное фото или добавил отменённое")
        XCTAssertEqual(c1.running, 0); XCTAssertEqual(shown, [])
    }

    /// 7. Две параллельные очереди одного цвета, обе на отправке — ✕ отменяет обе; поздние ответы ничего не добавляют,
    /// очередь не продолжается, счётчик не уходит в минус
    func test07_CancelParallelQueues() async throws {
        let c1 = PhotoBatchUpload()
        try await pickPhotos(c1, color: 0, ["P1", "P2"]); try await pickPhotos(c1, color: 0, ["Q1"])
        try await processed("P1"); try await processed("Q1")
        XCTAssertEqual(c1.running, 2)
        c1.cancel()
        XCTAssertEqual(c1.running, 0); XCTAssertFalse(c1.busy)
        try await answered("P1"); try await answered("Q1")
        XCTAssertEqual(images(0), ["c1-0.jpg"], "Поздний ответ отменённой очереди добавил фото")
        XCTAssertNil(gates["P2: jpeg"], "После ✕ очередь продолжилась")
        XCTAssertEqual(c1.running, 0, "Отменённые очереди изменили счётчик"); XCTAssertTrue(canSave([c1.busy]))
    }

    /// 8. Новый выбор сразу после ✕: поздний ответ отменённой очереди не уменьшает счётчик новой и не разблокирует
    /// сохранение раньше времени; новое фото добавляется
    func test08_NewPickRightAfterCancel() async throws {
        let c1 = PhotoBatchUpload()
        try await pickPhotos(c1, color: 0, ["P1"]); try await processed("P1")
        c1.cancel()
        try await pickPhotos(c1, color: 0, ["R1"])
        XCTAssertEqual(c1.running, 1)
        try await answered("P1")
        XCTAssertEqual(c1.running, 1, "Отменённая очередь уменьшила счётчик новой")
        XCTAssertTrue(c1.busy); XCTAssertFalse(canSave([c1.busy]), "Сохранение разблокировано, пока грузится новое фото")
        XCTAssertEqual(images(0), ["c1-0.jpg"])
        try await processed("R1"); try await answered("R1")
        XCTAssertEqual(c1.running, 0); XCTAssertTrue(canSave([c1.busy])); XCTAssertEqual(images(0), ["c1-0.jpg", "R1.jpg"])
    }

    /// 8а. Отмена ещё до первого шага задачи и сразу новый выбор: отменённая задача не трогает счётчик новой
    func test08a_CancelBeforeTaskStartsThenNewPick() async throws {
        let c1 = PhotoBatchUpload()
        c1.start(["X1"], { [self] (n: String) async throws -> String in try await work(n) }, add: { _ in XCTFail("Добавлено фото отменённой загрузки") }, fail: { [self] in show($0) })
        c1.cancel()   // задача ещё не начала работу
        XCTAssertEqual(c1.running, 0)
        try await pickPhotos(c1, color: 0, ["R1"])
        XCTAssertEqual(c1.running, 1, "Отменённая задача уменьшила счётчик новой")
        XCTAssertNil(gates["X1: jpeg"], "Отменённая до начала загрузка начала работу")
        try await processed("R1"); try await answered("R1")
        XCTAssertEqual(c1.running, 0); XCTAssertEqual(images(0), ["c1-0.jpg", "R1.jpg"]); XCTAssertEqual(shown, [])
    }

    /// 9. Ошибка, пришедшая после отмены, не показывается — ни у поля, ни у фото цвета
    func test09_StaleErrorAfterCancel() async throws {
        let hero = PhotoUpload(), c1 = PhotoBatchUpload()
        try await pick(hero, "hero", "A"); try await processed("A")
        try await pickPhotos(c1, color: 0, ["P1"]); try await processed("P1")
        hero.cancel(); c1.cancel()
        try await answered("A", throwing: Boom(name: "A")); try await answered("P1", throwing: Boom(name: "P1"))
        XCTAssertEqual(shown, [], "Показана ошибка отменённой загрузки")
        XCTAssertEqual(doc.str("hero"), ""); XCTAssertEqual(images(0), ["c1-0.jpg"]); XCTAssertEqual(c1.running, 0)
    }

    /// 10. Два цвета: ✕ у одного не трогает загрузку другого, сохранение ждёт второй цвет
    func test10_TwoColorsCancelOne() async throws {
        let c1 = PhotoBatchUpload(), c2 = PhotoBatchUpload()
        try await pickPhotos(c1, color: 0, ["P1"]); try await pickPhotos(c2, color: 1, ["R1"])
        c1.cancel()
        XCTAssertEqual(c1.running, 0); XCTAssertEqual(c2.running, 1, "✕ одного цвета отменил загрузку другого")
        XCTAssertFalse(canSave([c1.busy, c2.busy]))
        try await processed("R1"); try await answered("R1")
        XCTAssertEqual(images(1), ["R1.jpg"]); XCTAssertTrue(canSave([c1.busy, c2.busy]))
        try await open("P1: jpeg") { self.finished.contains("P1") }
        XCTAssertEqual(images(0), ["c1-0.jpg"]); XCTAssertEqual(sent, ["R1"])
    }

    /// 11. Без отмены всё как раньше: фото поля записывается; фото цвета добавляются по порядку, сохранение ждёт последнее
    func test11_SuccessWithoutCancel() async throws {
        let hero = PhotoUpload(), c1 = PhotoBatchUpload()
        try await pick(hero, "hero", "A"); try await processed("A"); try await answered("A")
        XCTAssertEqual(doc.str("hero"), "A.jpg"); XCTAssertFalse(hero.busy)
        try await pickPhotos(c1, color: 0, ["P1", "P2"])
        try await processed("P1")
        try await open("P1: upload") { self.gates["P2: jpeg"] != nil }
        XCTAssertFalse(canSave([c1.busy]), "Сохранение разблокировано до последнего фото")
        try await processed("P2"); try await answered("P2")
        XCTAssertEqual(images(0), ["c1-0.jpg", "P1.jpg", "P2.jpg"]); XCTAssertEqual(c1.running, 0); XCTAssertTrue(canSave([c1.busy]))
        XCTAssertEqual(sent, ["A", "P1", "P2"]); XCTAssertEqual(shown, [])
    }

    /// 12. Отмена не показывается как ошибка: отменённая загрузка завершается CancellationError или URLError.cancelled
    /// (так прерывается запрос URLSession) — тостов нет; и сами эти ошибки для человека — «не ошибка» (userMessage nil)
    func test12_CancelNotShownAsError() async throws {
        XCTAssertNil(CancellationError().userMessage); XCTAssertNil(URLError(.cancelled).userMessage)
        let hero = PhotoUpload(), c1 = PhotoBatchUpload()
        try await pick(hero, "hero", "A"); try await processed("A")
        try await pickPhotos(c1, color: 0, ["P1"]); try await processed("P1")
        hero.cancel(); c1.cancel()
        try await answered("A", throwing: URLError(.cancelled)); try await answered("P1", throwing: CancellationError())
        XCTAssertEqual(shown, [], "После отмены вызван fail — отмена обработана как ошибка")
    }
}
