import XCTest
@testable import Albakov

/// Этап L.2.26: загрузка логотипа в одно место (LogoUpload, его использует LogoSlot). Актуально только последнее действие —
/// новое фото или «Убрать». Каждая «загрузка» здесь ждёт, пока тест её завершит (успехом или ошибкой), — порядок завершения
/// задаёт тест, без пауз и таймингов. Проверяется, что устаревшая загрузка не перезаписывает новый выбор, не гасит
/// «Загружаю…» актуальной, не показывает свою ошибку и отменяется (в LogoSlot отменённая загрузка после обработки
/// на сервер не отправляется — Task.checkCancellation перед API.upload)
@MainActor
final class LogoUploadTests: XCTestCase {
    private struct Boom: Error { let name: String }
    private var gates: [String: CheckedContinuation<String, any Error>] = [:]
    private var applied: [String] = [], failed: [String] = [], finished: [String] = []
    private var cancelledAtEnd: [String: Bool] = [:]

    /// Начать загрузку name — как выбор фото в LogoSlot
    private func start(_ u: LogoUpload, _ name: String) async throws {
        u.start({ [self] () async throws -> String in
            defer { finished.append(name); cancelledAtEnd[name] = Task.isCancelled }
            return try await withCheckedThrowingContinuation { gates[name] = $0 }
        }, apply: { [self] in applied.append($0) }, fail: { [self] in failed.append(($0 as? Boom)?.name ?? "\($0)") })
        let started = try await until { self.gates[name] != nil }
        XCTAssertTrue(started, "Загрузка \(name) не началась")
    }
    /// Завершить загрузку name. Когда она отметилась завершённой, LogoUpload уже решил, применять ли её результат:
    /// между концом работы и этим решением нет ожидания — всё на главном акторе
    private func finish(_ name: String, failing: Bool = false) async throws {
        let g = try XCTUnwrap(gates.removeValue(forKey: name), "Загрузка \(name) не ждёт завершения")
        if failing { g.resume(throwing: Boom(name: name)) } else { g.resume(returning: name) }
        let done = try await until { self.finished.contains(name) }
        XCTAssertTrue(done, "Загрузка \(name) не завершилась")
    }

    /// Фото A, затем B; B завершается раньше A — остаётся B, запоздавшая A ничего не меняет и была отменена
    func test01_NewerFinishesFirst() async throws {
        let u = LogoUpload()
        try await start(u, "A"); try await start(u, "B")
        XCTAssertTrue(u.busy)
        try await finish("B")
        XCTAssertEqual(applied, ["B"]); XCTAssertFalse(u.busy)
        try await finish("A")
        XCTAssertEqual(applied, ["B"], "Устаревшая загрузка перезаписала новый выбор")
        XCTAssertFalse(u.busy, "Устаревшая загрузка включила «Загружаю…»"); XCTAssertEqual(failed, [])
        XCTAssertEqual(cancelledAtEnd["A"], true, "Устаревшая загрузка не отменена — её отправка на сервер не прервалась бы")
        XCTAssertEqual(cancelledAtEnd["B"], false)
    }

    /// Фото A, затем B; A завершается первой — её результат не записывается, «Загружаю…» горит, пока идёт B
    func test02_StaleFinishKeepsCurrentBusy() async throws {
        let u = LogoUpload()
        try await start(u, "A"); try await start(u, "B")
        try await finish("A")
        XCTAssertEqual(applied, [], "Устаревшая загрузка записала результат")
        XCTAssertTrue(u.busy, "Устаревшая загрузка погасила «Загружаю…», пока идёт актуальная")
        try await finish("B")
        XCTAssertEqual(applied, ["B"], "Актуальная загрузка не записала результат"); XCTAssertFalse(u.busy)
    }

    /// «Убрать» во время загрузки A: «Загружаю…» гаснет сразу, A отменена, её результат потом не возвращает логотип;
    /// следующее фото загружается как обычно
    func test03_RemoveDuringUpload() async throws {
        let u = LogoUpload()
        try await start(u, "A")
        u.cancel()
        XCTAssertFalse(u.busy)
        try await finish("A")
        XCTAssertEqual(applied, [], "Результат загрузки вернул убранный логотип"); XCTAssertEqual(failed, []); XCTAssertFalse(u.busy)
        XCTAssertEqual(cancelledAtEnd["A"], true)
        try await start(u, "B"); XCTAssertTrue(u.busy)
        try await finish("B")
        XCTAssertEqual(applied, ["B"]); XCTAssertFalse(u.busy)
    }

    /// A завершается ошибкой, когда уже идёт B: ошибка A не показывается, «Загружаю…» горит, B записывает результат
    func test04_StaleErrorHidden() async throws {
        let u = LogoUpload()
        try await start(u, "A"); try await start(u, "B")
        try await finish("A", failing: true)
        XCTAssertEqual(failed, [], "Показана ошибка устаревшей загрузки"); XCTAssertTrue(u.busy)
        try await finish("B")
        XCTAssertEqual(applied, ["B"]); XCTAssertEqual(failed, []); XCTAssertFalse(u.busy)
    }

    /// A, затем B; A завершилась; затем «Убрать» — отменяется именно B (устаревшая A не потеряла ссылку на неё),
    /// результат B не записывается
    func test06_RemoveAfterStaleFinished() async throws {
        let u = LogoUpload()
        try await start(u, "A"); try await start(u, "B")
        try await finish("A")
        u.cancel()
        XCTAssertFalse(u.busy)
        try await finish("B")
        XCTAssertEqual(applied, [], "«Убрать» не отменило актуальную загрузку"); XCTAssertEqual(cancelledAtEnd["B"], true); XCTAssertFalse(u.busy)
    }

    /// Ошибка актуальной загрузки показывается, результат не записывается, «Загружаю…» гаснет
    func test05_CurrentErrorShown() async throws {
        let u = LogoUpload()
        try await start(u, "A")
        try await finish("A", failing: true)
        XCTAssertEqual(failed, ["A"]); XCTAssertEqual(applied, []); XCTAssertFalse(u.busy)
    }
}
