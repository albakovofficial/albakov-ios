import XCTest
import SwiftUI
@testable import Albakov

/// Этап L.2.34: доступность ✕ отмены загрузки на плитке «Фото этого цвета». Здесь настоящий ColorPhotos показан на экране
/// (UIHostingController в окне приложения-хоста) с настоящим PhotoBatchUpload, у которого идёт загрузка («ворота» открывает
/// тест). Проверяется то, что видит VoiceOver, — дерево элементов доступности SwiftUI: отдельная кнопка «Отмена», её область
/// не меньше 44×44 pt и лежит в углу плитки, активация (двойное касание VoiceOver) отменяет загрузку, а не открывает галерею.
/// Дерево доступности SwiftUI строит, только когда им пользуется вспомогательная технология (VoiceOver, UI-тесты): на время
/// теста включается режим автоматизации доступности (_AXSSetAutomationEnabled из libAccessibility — как в библиотеке
/// AccessibilitySnapshot; закрытая функция системы, только в тестовой цели, в приложение не попадает), после — прежнее значение.
/// Ограничение: касание пальцем модульным тестом не сымитировать — что оно попадает в ту же область, видно по коду
/// (contentShape на рамке 44×44 у кнопки, которая лежит над PhotosPicker в ZStack)
@MainActor
final class ColorPhotosCancelAccessibilityTests: XCTestCase {
    private var window: UIWindow?
    private var gate: CheckedContinuation<String, any Error>?
    private var images: [String] = []
    private var added: [String] = []
    private var workDone = false
    private var restoreAccessibility: (() -> Void)?

    private func hide() {
        gate?.resume(throwing: CancellationError()); gate = nil
        window?.isHidden = true; window?.rootViewController = nil; window = nil
        restoreAccessibility?(); restoreAccessibility = nil
    }
    /// Включить режим автоматизации доступности (как AccessibilitySnapshot); возвращает, как вернуть прежнее значение
    private static func enableAccessibilityAutomation() -> (() -> Void)? {
        let root = ProcessInfo.processInfo.environment["IPHONE_SIMULATOR_ROOT"] ?? ""
        guard let lib = dlopen(root + "/usr/lib/libAccessibility.dylib", RTLD_NOW) ?? dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW),
              let getSym = dlsym(lib, "_AXSAutomationEnabled"), let setSym = dlsym(lib, "_AXSSetAutomationEnabled") else { return nil }
        typealias GetFn = @convention(c) () -> Int32
        typealias SetFn = @convention(c) (Int32) -> Void
        let get = unsafeBitCast(getSym, to: GetFn.self), set = unsafeBitCast(setSym, to: SetFn.self)
        let before = get()
        set(1)
        return { set(before) }
    }
    /// Поле фото цвета на экране; busy — с идущей загрузкой
    private func show(busy: Bool) async throws -> PhotoBatchUpload {
        restoreAccessibility = Self.enableAccessibilityAutomation()
        XCTAssertNotNil(restoreAccessibility, "Не удалось включить режим автоматизации доступности")
        let uploads = PhotoBatchUpload()
        if busy {
            uploads.start(["X"], { [self] (_: String) async throws -> String in
                defer { workDone = true }
                return try await withCheckedThrowingContinuation { gate = $0 }
            },
                          add: { [self] in added.append($0) }, fail: { _ in })
            let started = try await until { self.gate != nil }
            XCTAssertTrue(started, "Загрузка не началась")
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene, "Нет сцены приложения-хоста")
        let w = UIWindow(windowScene: scene)
        w.frame = CGRect(x: 0, y: 0, width: 390, height: 300)
        let view = ColorPhotos(images: Binding(get: { [self] in images }, set: { [self] in images = $0 }), add: { [self] in added.append($0) }, uploads: uploads)
        w.rootViewController = UIHostingController(rootView: view.padding(20))
        w.isHidden = false
        w.rootViewController?.view.layoutIfNeeded()
        window = w
        return uploads
    }
    /// Элементы доступности экрана — как их перебирает VoiceOver
    private func elements() -> [NSObject] {
        var out: [NSObject] = []
        func walk(_ o: NSObject) {
            if o.isAccessibilityElement { out.append(o); return }
            if let els = o.accessibilityElements, !els.isEmpty { for e in els { if let n = e as? NSObject { walk(n) } }; return }
            if let v = o as? UIView { for s in v.subviews where !s.isHidden { walk(s) } }
        }
        if let v = window?.rootViewController?.view { walk(v) }
        return out
    }
    private func element(_ label: String, exact: Bool = true) -> NSObject? {
        elements().first { exact ? $0.accessibilityLabel == label : ($0.accessibilityLabel ?? "").contains(label) }
    }

    /// Во время загрузки ✕ — отдельная кнопка «Отмена» (не часть плитки), без подсказки; плитка — своя кнопка
    func test01_CancelIsSeparateLabelledButton() async throws {
        defer { hide() }
        _ = try await show(busy: true)
        let found = try await until { self.element("Отмена") != nil && self.element("Фото этого цвета", exact: false) != nil }
        XCTAssertTrue(found, "Нет «Отмена» или плитки среди элементов VoiceOver: \(elements().map { $0.accessibilityLabel ?? "—" })")
        let cancel = try XCTUnwrap(element("Отмена")), tile = try XCTUnwrap(element("Фото этого цвета", exact: false))
        XCTAssertFalse(cancel === tile, "«Отмена» слилась с плиткой в один элемент")
        XCTAssertTrue(cancel.accessibilityTraits.contains(.button), "«Отмена» — не кнопка для VoiceOver")
        XCTAssertTrue(tile.accessibilityTraits.contains(.button))
        XCTAssertTrue((cancel.accessibilityHint ?? "").isEmpty, "У «Отмена» лишняя подсказка")
        XCTAssertEqual(elements().filter { $0.accessibilityLabel == "Отмена" }.count, 1)
    }

    /// Область «Отмена» — не меньше 44×44 pt и в правом верхнем углу плитки (там, где кружок)
    func test02_CancelAreaIs44InTileCorner() async throws {
        defer { hide() }
        _ = try await show(busy: true)
        let found = try await until { self.element("Отмена") != nil && self.element("Фото этого цвета", exact: false) != nil }
        XCTAssertTrue(found, "Нет «Отмена» или плитки среди элементов VoiceOver: \(elements().map { $0.accessibilityLabel ?? "—" })")
        let cancel = try XCTUnwrap(element("Отмена")).accessibilityFrame
        let tile = try XCTUnwrap(element("Фото этого цвета", exact: false)).accessibilityFrame
        XCTAssertGreaterThanOrEqual(cancel.width, 44, "Область «Отмена» уже 44 pt: \(cancel)")
        XCTAssertGreaterThanOrEqual(cancel.height, 44, "Область «Отмена» ниже 44 pt: \(cancel)")
        XCTAssertEqual(cancel.maxX, tile.maxX, accuracy: 1, "«Отмена» не у правого края плитки: \(cancel) / \(tile)")
        XCTAssertEqual(cancel.minY, tile.minY, accuracy: 1, "«Отмена» не у верхнего края плитки: \(cancel) / \(tile)")
        XCTAssertTrue(tile.insetBy(dx: -1, dy: -1).contains(cancel), "«Отмена» выходит за плитку: \(cancel) / \(tile)")
    }

    /// Активация «Отмена» (двойное касание VoiceOver) отменяет загрузку цвета и не открывает галерею; ✕ исчезает,
    /// плитка остаётся; уже добавленные фото не трогаются; поздний ответ ничего не добавляет
    func test03_ActivateCancelsWithoutOpeningPicker() async throws {
        defer { hide() }
        images = ["c1-0.jpg"]
        let uploads = try await show(busy: true)
        let found = try await until { self.element("Отмена") != nil }
        XCTAssertTrue(found, "Нет «Отмена» среди элементов VoiceOver: \(elements().map { $0.accessibilityLabel ?? "—" })")
        XCTAssertTrue(try XCTUnwrap(element("Отмена")).accessibilityActivate(), "«Отмена» не активируется")
        let cancelled = try await until { !uploads.busy && self.element("Отмена") == nil }
        XCTAssertTrue(cancelled, "Активация «Отмена» не отменила загрузку")
        XCTAssertEqual(uploads.running, 0)
        XCTAssertNil(window?.rootViewController?.presentedViewController, "Вместо отмены открылась галерея")
        XCTAssertNotNil(element("Фото этого цвета", exact: false), "Плитка пропала")
        XCTAssertEqual(images, ["c1-0.jpg"], "Отмена тронула добавленные фото")
        try XCTUnwrap(gate).resume(returning: "X.jpg"); gate = nil
        // загрузка доработала: после ответа задача без ожиданий проверяет отмену и выходит — добавить фото она могла бы
        // только в этом же шаге, до того как опрос увидит workDone
        let done = try await until { self.workDone }
        XCTAssertTrue(done, "Отменённая загрузка не доработала")
        XCTAssertEqual(added, [], "Поздний ответ после отмены добавил фото"); XCTAssertEqual(uploads.running, 0)
    }

    /// Без загрузки ✕ нет — плитка, как раньше, только выбор фото
    func test04_NoCancelWhenIdle() async throws {
        defer { hide() }
        _ = try await show(busy: false)
        let tile = try await until { self.element("Фото этого цвета", exact: false) != nil }
        XCTAssertTrue(tile, "Нет плитки среди элементов VoiceOver: \(elements().map { $0.accessibilityLabel ?? "—" })")
        XCTAssertNil(element("Отмена"), "«Отмена» видна без загрузки")
    }
}
