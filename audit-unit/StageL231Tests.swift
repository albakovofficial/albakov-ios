import XCTest
import SwiftUI
@testable import Albakov

/// Этап L.2.31: пока форма сохраняется, её содержимое недоступно — AdminPage ставит .disabled(busy) на content. Здесь
/// настоящий AdminPage показан на экране (UIHostingController в окне приложения-хоста, внутри NavigationStack, как экраны
/// панели), а вместо полей и кнопок формы — пробы: каждая записывает, доступна ли она (isEnabled — его выставляет .disabled,
/// и по нему работают TextField, Toggle, Button, PhotosPicker). Сохранение — как в формах: busy = true, ожидание ответа
/// сервера («ворота» открывает тест), busy = false. Ограничение: настоящие TextField, Toggle и кнопки форм модульным тестом
/// не нажать — что они внутри content, видно по коду форм; что они слушаются isEnabled — стандартное поведение SwiftUI
@MainActor
final class FormEditLockTests: XCTestCase {
    private struct Boom: Error {}
    private var window: UIWindow?
    private var serverAnswer: CheckedContinuation<Void, any Error>?
    private var saved = 0

    private func hide() {
        window?.isHidden = true; window?.rootViewController = nil; window = nil
        LockProbe.enabled = [:]; LockProbe.dismiss = nil
    }
    /// Показать экран навигации; форма на AdminPage открывается переходом (как экраны панели)
    private func show(_ nav: LockNav) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene, "Нет сцены приложения-хоста")
        hide()
        let w = UIWindow(windowScene: scene)
        w.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        w.rootViewController = UIHostingController(rootView: LockRoot(nav: nav))
        w.isHidden = false
        w.rootViewController?.view.layoutIfNeeded()
        window = w
        nav.path = [1]
        let opened = try await until { LockProbe.enabled[nav.fields.first ?? "toolbar"] != nil && LockProbe.dismiss != nil }
        XCTAssertTrue(opened, "Форма не открылась: \(LockProbe.enabled)")
        // переход закончился (анимация не идёт): дальше закрытие экрана — обычное, а не посреди перехода
        let settled = try await until { self.navigation().map { $0.viewControllers.count == 2 && $0.transitionCoordinator == nil } ?? true }
        XCTAssertTrue(settled, "Переход на форму не закончился")
    }
    /// UINavigationController, на котором NavigationStack показывает экраны (если SwiftUI строит его так)
    private func navigation() -> UINavigationController? {
        var stack: [UIViewController] = window?.rootViewController.map { [$0] } ?? []
        while let vc = stack.popLast() {
            if let n = vc as? UINavigationController { return n }
            stack.append(contentsOf: vc.children)
        }
        return nil
    }
    private func stackDepth() -> Int? { navigation()?.viewControllers.count }
    private func all(_ names: [String], enabled: Bool) async throws -> Bool {
        try await until { names.allSatisfy { LockProbe.enabled[$0] == enabled } }
    }
    /// «Сохранить» — как save() в формах: busy на время ожидания ответа сервера, ошибка — в error
    private func startSave(_ nav: LockNav) async throws {
        Task { [self] in
            nav.error = nil
            nav.busy = true; defer { nav.busy = false }
            do { try await withCheckedThrowingContinuation { serverAnswer = $0 }; saved += 1 } catch { nav.error = "Не сохранилось" }
        }
        let waiting = try await until { self.serverAnswer != nil }
        XCTAssertTrue(waiting, "Сохранение не началось")
    }
    private func answer(failing: Bool = false) throws {
        let a = try XCTUnwrap(serverAnswer); serverAnswer = nil
        if failing { a.resume(throwing: Boom()) } else { a.resume() }
    }

    /// Поля карточки товара: текст, переключатель, действия с фото, «Копировать» и «Удалить»
    private static let product = ["name", "price", "active", "photo.pick", "photo.remove", "photo.move", "copy", "delete"]

    /// 1–4. Во время сохранения недоступны текстовые поля, переключатели, действия с фото, «Копировать» и «Удалить»
    func test01_ContentLockedWhileSaving() async throws {
        defer { hide() }
        let nav = LockNav(fields: Self.product)
        try await show(nav)
        let before = try await all(Self.product, enabled: true)
        XCTAssertTrue(before, "До сохранения не всё доступно: \(LockProbe.enabled)")
        try await startSave(nav)
        let locked = try await all(Self.product, enabled: false)
        XCTAssertTrue(locked, "Во время сохранения форму можно менять: \(LockProbe.enabled)")
        try answer()
        _ = try await all(Self.product, enabled: true)
    }

    /// 5. После успешного сохранения всё снова доступно
    func test02_UnlockedAfterSuccess() async throws {
        defer { hide() }
        let nav = LockNav(fields: Self.product)
        try await show(nav)
        try await startSave(nav)
        _ = try await all(Self.product, enabled: false)
        try answer()
        let unlocked = try await all(Self.product, enabled: true)
        XCTAssertTrue(unlocked, "После сохранения не всё доступно: \(LockProbe.enabled)")
        XCTAssertEqual(saved, 1); XCTAssertNil(nav.error)
    }

    /// 6. После ошибки сохранения всё снова доступно, ошибка показана
    func test03_UnlockedAfterError() async throws {
        defer { hide() }
        let nav = LockNav(fields: Self.product)
        try await show(nav)
        try await startSave(nav)
        _ = try await all(Self.product, enabled: false)
        try answer(failing: true)
        let unlocked = try await all(Self.product, enabled: true)
        XCTAssertTrue(unlocked, "После ошибки сохранения не всё доступно: \(LockProbe.enabled)")
        XCTAssertEqual(nav.error, "Не сохранилось"); XCTAssertEqual(saved, 0)
    }

    /// 7. Навигация и закрытие экрана: кнопка в панели навигации экрана формы доступна во время сохранения, а экран
    /// закрывается (dismiss, как SlideEdit после ответа сервера) — блокировка содержимого их не задевает
    func test04_NavigationAndDismissWork() async throws {
        defer { hide() }
        let nav = LockNav(fields: ["name"])
        try await show(nav)
        try await startSave(nav)
        let locked = try await all(["name"], enabled: false)
        XCTAssertTrue(locked)
        let toolbar = try await until { LockProbe.enabled["toolbar.saving"] != nil }
        XCTAssertTrue(toolbar, "Панель навигации не перерисовалась с сохранением: \(LockProbe.enabled)")
        XCTAssertEqual(LockProbe.enabled["toolbar.saving"], true, "Блокировка формы задела панель навигации")
        try XCTUnwrap(LockProbe.dismiss, "Нет закрытия экрана")()
        let closed = try await until { nav.path.isEmpty && self.stackDepth().map { $0 == 1 } ?? true }
        XCTAssertTrue(closed, "Экран не закрылся во время сохранения (глубина \(String(describing: self.stackDepth())))")
        try answer()
        _ = try await until { !nav.busy }
    }

    /// 8. Форма без фото (как «Оплата и доставка», «Обмен и возвраты») тоже защищена; после сохранения — доступна
    func test05_FormWithoutPhotos() async throws {
        defer { hide() }
        let fields = ["label", "enabled", "method.move", "method.remove", "secret.save"]
        let nav = LockNav(fields: fields)
        try await show(nav)
        try await startSave(nav)
        let locked = try await all(fields, enabled: false)
        XCTAssertTrue(locked, "Форма без фото не защищена: \(LockProbe.enabled)")
        try answer()
        let unlocked = try await all(fields, enabled: true)
        XCTAssertTrue(unlocked, "После сохранения форма без фото недоступна: \(LockProbe.enabled)")
    }

    /// Клавиатура: если при «Сохранить» в поле формы шёл ввод, поле отпускает клавиатуру — ввод в недоступное поле не
    /// продолжается; после сохранения поле снова доступно. Здесь настоящий TextField SwiftUI (UITextField внутри)
    func test07_KeyboardReleasedOnSave() async throws {
        defer { hide() }
        let nav = LockNav(fields: ["name"], textField: true)
        try await show(nav)
        window?.makeKey()
        let field = try XCTUnwrap(textField(), "В форме нет поля ввода")
        XCTAssertTrue(field.becomeFirstResponder(), "Поле не приняло ввод")
        try await startSave(nav)
        let released = try await until { !field.isFirstResponder }
        XCTAssertTrue(released, "Во время сохранения в поле формы можно продолжать ввод")
        try answer()
        _ = try await until { !nav.busy }
        let unlocked = try await all(["name"], enabled: true)
        XCTAssertTrue(unlocked)
    }
    private func textField() -> UITextField? {
        var stack: [UIView] = window.map { [$0] } ?? []
        while let v = stack.popLast() {
            if let t = v as? UITextField { return t }
            stack.append(contentsOf: v.subviews)
        }
        return nil
    }

    /// Выбор фото: замок L.2.30 и замок содержимого вместе — недоступен во время сохранения, доступен после
    func test06_PhotoPickerStillLocked() async throws {
        defer { hide() }
        let nav = LockNav(fields: ["photo.pick"], photoLock: true)
        try await show(nav)
        try await startSave(nav)
        let locked = try await all(["photo.pick"], enabled: false)
        XCTAssertTrue(locked)
        try answer()
        let unlocked = try await all(["photo.pick"], enabled: true)
        XCTAssertTrue(unlocked)
    }
}

/// Состояние экрана: путь навигации и сохранение формы (busy и error — как @State форм)
@MainActor
private final class LockNav: ObservableObject {
    @Published var path: [Int] = []
    @Published var busy = false
    @Published var error: String?
    @Published var text = ""
    let fields: [String]
    let photoLock: Bool, textField: Bool
    init(fields: [String], photoLock: Bool = false, textField: Bool = false) { self.fields = fields; self.photoLock = photoLock; self.textField = textField }
}

/// Корень с переходом на форму, как разделы панели
private struct LockRoot: View {
    @ObservedObject var nav: LockNav
    var body: some View {
        NavigationStack(path: $nav.path) {
            Text("Панель").navigationDestination(for: Int.self) { _ in LockForm(nav: nav) }
        }
    }
}

/// Форма на настоящем AdminPage: поля — пробы внутри content; кнопка панели навигации — проба в .toolbar формы
private struct LockForm: View {
    @ObservedObject var nav: LockNav
    var body: some View {
        AdminPage(title: "Проба", busy: nav.busy, error: nav.error, onSave: {}) {
            ForEach(nav.fields, id: \.self) { f in
                if nav.photoLock { LockProbe(name: f).photoPickingLockedWhileSaving() } else { LockProbe(name: f) }
            }
            if nav.textField { TextField("Название", text: $nav.text) }
            DismissProbe()
        }
        .toolbar { ToolbarItem(placement: .confirmationAction) { ToolbarProbe(nav: nav) } }
    }
}

/// Кнопка панели навигации экрана формы: перерисовывается вместе с busy и записывает, доступна ли она во время сохранения
private struct ToolbarProbe: View {
    @ObservedObject var nav: LockNav
    @Environment(\.isEnabled) private var isEnabled
    var body: some View {
        let _ = LockProbe.record(nav.busy ? "toolbar.saving" : "toolbar", isEnabled)
        Color.clear.frame(width: 10, height: 10)
    }
}

/// Записывает, доступна ли она (isEnabled) при каждой отрисовке
private struct LockProbe: View {
    @MainActor static var enabled: [String: Bool] = [:]
    @MainActor static var dismiss: DismissAction?
    let name: String
    @Environment(\.isEnabled) private var isEnabled
    var body: some View {
        let _ = LockProbe.record(name, isEnabled)
        Color.clear.frame(width: 10, height: 10)
    }
    @MainActor static func record(_ name: String, _ on: Bool) { enabled[name] = on }
}

/// Закрытие экрана изнутри формы — как dismiss() в SlideEdit
private struct DismissProbe: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        let _ = DismissProbe.keep(dismiss)
        Color.clear.frame(width: 10, height: 10)
    }
    @MainActor static func keep(_ d: DismissAction) { LockProbe.dismiss = d }
}
