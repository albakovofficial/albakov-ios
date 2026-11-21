import XCTest
import SwiftUI
import Combine
@testable import Albakov

/// Этап L.2.27: загрузка фото в поле формы панели (ImageField). Поле устроено так же, как здесь: PhotoUpload, результат
/// пишется в Binding поля формы (doc.text(k) — как в FieldView), ошибка — в тост, между обработкой фото и отправкой
/// на сервер — Task.checkCancellation. Обработка и отправка здесь — «ворота», которые тест открывает сам (успехом
/// или ошибкой), поэтому порядок завершения задаёт тест, без пауз и таймингов. Сам экран SwiftUI (выбор в PhotosPicker,
/// .onChange, время жизни @StateObject) модульным тестом не проверить — PhotosPickerItem в тесте не создать
@MainActor
final class ImageFieldUploadTests: XCTestCase {
    private struct Boom: Error { let name: String }
    private var gates: [String: CheckedContinuation<String, any Error>] = [:]
    private var sent: [String] = [], shown: [String] = [], finished: [String] = []
    private var cancelledAtEnd: [String: Bool] = [:]
    /// Форма с прежним фото. lazy: Doc — главного актора, а инициализаторы XCTestCase не изолированы
    private lazy var doc = Doc(["photo": "old.jpg"])
    private var value: Binding<String> { doc.text("photo") }

    /// Пройти ворота name: ждать, пока тест их откроет
    private func gate(_ name: String) async throws -> String {
        try await withCheckedThrowingContinuation { gates[name] = $0 }
    }
    /// Выбрать фото name — как .onChange(of: item) в ImageField: обработка («name: jpeg»), проверка отмены,
    /// отправка («name: upload») → адрес фото на сервере
    private func pick(_ u: PhotoUpload, _ name: String) async throws {
        let field = value
        u.start({ [self] () async throws -> String in
            defer { finished.append(name); cancelledAtEnd[name] = Task.isCancelled }
            _ = try await gate(name + ": jpeg")
            try Task.checkCancellation()
            sent.append(name)
            return try await gate(name + ": upload")
        }, apply: { field.wrappedValue = $0 }, fail: { [self] in shown.append(($0 as? Boom)?.name ?? "\($0)") })
        let started = try await until { self.gates[name + ": jpeg"] != nil }
        XCTAssertTrue(started, "Загрузка \(name) не началась")
    }
    /// Открыть ворота и дождаться, пока работа дойдёт до следующих ворот (или завершится)
    private func open(_ key: String, failing: Bool = false, then next: () -> Bool) async throws {
        let g = try XCTUnwrap(gates.removeValue(forKey: key), "Никто не ждёт «\(key)»")
        let name = String(key.prefix { $0 != ":" })
        if failing { g.resume(throwing: Boom(name: name)) } else { g.resume(returning: name + ".jpg") }
        let ok = try await until { next() }
        XCTAssertTrue(ok, "После «\(key)» работа не продвинулась")
    }
    /// Обработка name закончилась — фото ушло на сервер
    private func processed(_ name: String) async throws {
        try await open(name + ": jpeg") { self.gates[name + ": upload"] != nil }
    }
    /// Сервер ответил на запрос name (или ошибкой). Когда работа отметилась завершённой, PhotoUpload уже решил, применять
    /// ли её результат: между концом работы и этим решением нет ожидания — всё на главном акторе
    private func answered(_ name: String, failing: Bool = false) async throws {
        try await open(name + ": upload", failing: failing) { self.finished.contains(name) }
    }

    /// Фото A, затем B; сервер отвечает на B раньше, чем на A — в поле B, запоздавший ответ на A его не заменяет
    func test01_NewerAnsweredFirst() async throws {
        let u = PhotoUpload()
        try await pick(u, "A"); try await processed("A")
        try await pick(u, "B"); try await processed("B")
        XCTAssertEqual(sent, ["A", "B"]); XCTAssertTrue(u.busy)
        try await answered("B")
        XCTAssertEqual(value.wrappedValue, "B.jpg"); XCTAssertFalse(u.busy)
        try await answered("A")
        XCTAssertEqual(value.wrappedValue, "B.jpg", "Запоздавший ответ на старое фото заменил новое")
        XCTAssertEqual(doc.str("photo"), "B.jpg")
        XCTAssertFalse(u.busy); XCTAssertEqual(shown, [])
        XCTAssertEqual(cancelledAtEnd["A"], true, "Устаревшая загрузка не отменена"); XCTAssertEqual(cancelledAtEnd["B"], false)
    }

    /// Фото A, затем B; сервер отвечает на A первым — в поле остаётся прежнее фото, «Загружаю…» горит, пока идёт B
    func test02_StaleAnsweredFirst() async throws {
        let u = PhotoUpload()
        try await pick(u, "A"); try await processed("A")
        try await pick(u, "B"); try await processed("B")
        try await answered("A")
        XCTAssertEqual(value.wrappedValue, "old.jpg", "Поле получило фото устаревшей загрузки")
        XCTAssertTrue(u.busy, "Устаревшая загрузка погасила «Загружаю…», пока идёт актуальная")
        try await answered("B")
        XCTAssertEqual(value.wrappedValue, "B.jpg", "Актуальная загрузка не записала фото"); XCTAssertFalse(u.busy)
    }

    /// Ошибка устаревшей загрузки A, когда уже идёт B, не показывается и не гасит «Загружаю…»; B записывается
    func test03_StaleErrorHidden() async throws {
        let u = PhotoUpload()
        try await pick(u, "A"); try await processed("A")
        try await pick(u, "B")
        try await answered("A", failing: true)
        XCTAssertEqual(shown, [], "Показана ошибка устаревшей загрузки"); XCTAssertTrue(u.busy)
        XCTAssertEqual(value.wrappedValue, "old.jpg")
        try await processed("B"); try await answered("B")
        XCTAssertEqual(value.wrappedValue, "B.jpg"); XCTAssertEqual(shown, []); XCTAssertFalse(u.busy)
    }

    /// Ошибка актуальной загрузки показывается, прежнее фото в поле остаётся, «Загружаю…» гаснет
    func test04_CurrentErrorShown() async throws {
        let u = PhotoUpload()
        try await pick(u, "A"); try await processed("A")
        try await answered("A", failing: true)
        XCTAssertEqual(shown, ["A"]); XCTAssertEqual(value.wrappedValue, "old.jpg"); XCTAssertFalse(u.busy)
    }

    /// Ошибка обработки актуального фото (не открылось, не сжалось) показывается, на сервер ничего не уходит
    func test05_CurrentProcessingErrorShown() async throws {
        let u = PhotoUpload()
        try await pick(u, "A")
        try await open("A: jpeg", failing: true) { self.finished.contains("A") }
        XCTAssertEqual(shown, ["A"]); XCTAssertEqual(sent, []); XCTAssertEqual(value.wrappedValue, "old.jpg"); XCTAssertFalse(u.busy)
    }

    /// «Убрать» во время загрузки (как кнопка в ImageField: upload.cancel(), затем пустое поле) — поле остаётся пустым,
    /// ответ сервера фото не возвращает, ошибки нет; следующее фото загружается как обычно
    func test06_RemoveDuringUpload() async throws {
        let u = PhotoUpload()
        try await pick(u, "A"); try await processed("A")
        u.cancel(); value.wrappedValue = ""
        XCTAssertFalse(u.busy)
        try await answered("A")
        XCTAssertEqual(value.wrappedValue, "", "Ответ сервера вернул убранное фото"); XCTAssertEqual(shown, []); XCTAssertFalse(u.busy)
        XCTAssertEqual(cancelledAtEnd["A"], true)
        try await pick(u, "B"); XCTAssertTrue(u.busy)
        try await processed("B"); try await answered("B")
        XCTAssertEqual(value.wrappedValue, "B.jpg"); XCTAssertFalse(u.busy)
    }

    /// Отмена: фото A ещё обрабатывалось, когда выбрали B, — после обработки A на сервер не уходит (Task.checkCancellation),
    /// отмена не показывается как ошибка и не гасит «Загружаю…» B
    func test07_CancelledBeforeSending() async throws {
        let u = PhotoUpload()
        try await pick(u, "A")
        try await pick(u, "B")
        try await open("A: jpeg") { self.finished.contains("A") }
        XCTAssertEqual(sent, [], "Устаревшее фото отправлено на сервер"); XCTAssertNil(gates["A: upload"])
        XCTAssertEqual(shown, [], "Отмена показана как ошибка"); XCTAssertTrue(u.busy)
        try await processed("B"); try await answered("B")
        XCTAssertEqual(sent, ["B"]); XCTAssertEqual(value.wrappedValue, "B.jpg"); XCTAssertFalse(u.busy)
    }

    /// Три фото подряд, ответы в обратном порядке: в поле попадает только последнее, и записывается оно один раз
    func test08_OnlyCurrentResultWritten() async throws {
        let u = PhotoUpload()
        var writes: [String] = []
        let c = doc.objectWillChange.sink { _ in writes.append("w") }
        defer { c.cancel() }
        for n in ["A", "B", "C"] { try await pick(u, n); try await processed(n) }
        try await answered("C"); try await answered("B"); try await answered("A")
        XCTAssertEqual(value.wrappedValue, "C.jpg"); XCTAssertEqual(writes.count, 1, "Поле формы менялось не только от актуального результата")
        XCTAssertEqual(shown, []); XCTAssertFalse(u.busy)
    }
}
