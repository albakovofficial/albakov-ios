import XCTest
import SwiftUI
@testable import Albakov

/// Этап L.2.30: выбор фото во время сохранения формы. AdminPage передаёт своё busy («идёт сохранение») полям формы,
/// а PhotosPicker в ImageField, LogoSlot и ColorPhotos закрыт модификатором photoPickingLockedWhileSaving — пока форма
/// сохраняется, выбрать фото нельзя. Здесь настоящий AdminPage показан на экране (UIHostingController в окне приложения-
/// хоста), а вместо PhotosPicker — проба с тем же модификатором: она записывает, доступна ли она (isEnabled, его выставляет
/// .disabled). Сохранение — как в формах: busy = true, ожидание ответа сервера («ворота» открывает тест), busy = false.
/// Ограничение: что модификатор стоит именно на PhotosPicker трёх полей — видно по коду, модульным тестом не проверить
@MainActor
final class PhotoPickingDuringSaveTests: XCTestCase {
    private struct Boom: Error {}
    private var window: UIWindow?
    private var serverAnswer: CheckedContinuation<Void, any Error>?
    private var saved: [String] = []
    private var gates: [String: CheckedContinuation<String, any Error>] = [:]
    private var added: [String] = []

    /// Убрать форму с экрана (в конце каждого теста)
    private func hide() {
        window?.isHidden = true; window?.rootViewController = nil; window = nil
        PickerProbe.enabled = [:]; SavingWitness.seen = []
    }

    /// Показать форму на AdminPage: поля фото (с замком) и обычные поля (без него)
    private func show(_ form: SaveForm, photos: [String], plain: [String] = []) throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene, "Нет сцены приложения-хоста")
        hide()
        let w = UIWindow(windowScene: scene)
        w.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        w.rootViewController = UIHostingController(rootView: ProbeForm(form: form, photos: photos, plain: plain))
        w.isHidden = false
        w.rootViewController?.view.layoutIfNeeded()
        window = w
    }
    /// Все пробы с именами names в состоянии enabled
    private func probes(_ names: [String], enabled: Bool) async throws -> Bool {
        try await until { names.allSatisfy { PickerProbe.enabled[$0] == enabled } }
    }
    /// «Сохранить» — как save() в формах: busy на время ожидания ответа сервера, ошибка — в error
    private func startSave(_ form: SaveForm) async throws {
        Task { [self] in
            form.error = nil
            form.busy = true; defer { form.busy = false }
            do { try await withCheckedThrowingContinuation { serverAnswer = $0 }; saved.append("ok") } catch { form.error = "Не сохранилось" }
        }
        let waiting = try await until { self.serverAnswer != nil }
        XCTAssertTrue(waiting, "Сохранение не началось")
    }
    private func answer(failing: Bool = false) throws {
        let a = try XCTUnwrap(serverAnswer); serverAnswer = nil
        if failing { a.resume(throwing: Boom()) } else { a.resume() }
    }

    /// 1. Пока форма сохраняется, выбрать фото нельзя; до сохранения — можно
    func test01_PickingLockedWhileSaving() async throws {
        defer { hide() }
        let form = SaveForm()
        try show(form, photos: ["photo"])
        let before = try await probes(["photo"], enabled: true)
        XCTAssertTrue(before, "Выбор фото недоступен до сохранения: \(PickerProbe.enabled)")
        try await startSave(form)
        let locked = try await probes(["photo"], enabled: false)
        XCTAssertTrue(locked, "Во время сохранения можно выбрать фото: \(PickerProbe.enabled)")
        try answer()
        _ = try await probes(["photo"], enabled: true)
    }

    /// 2. После успешного сохранения выбор фото снова доступен
    func test02_UnlockedAfterSuccessfulSave() async throws {
        defer { hide() }
        let form = SaveForm()
        try show(form, photos: ["photo"])
        try await startSave(form)
        _ = try await probes(["photo"], enabled: false)
        try answer()
        let unlocked = try await probes(["photo"], enabled: true)
        XCTAssertTrue(unlocked, "После сохранения выбор фото недоступен: \(PickerProbe.enabled)")
        XCTAssertEqual(saved, ["ok"]); XCTAssertFalse(form.busy)
    }

    /// 3. После ошибки сохранения выбор фото снова доступен (ошибка показана под формой, как раньше)
    func test03_UnlockedAfterFailedSave() async throws {
        defer { hide() }
        let form = SaveForm()
        try show(form, photos: ["photo"])
        try await startSave(form)
        _ = try await probes(["photo"], enabled: false)
        try answer(failing: true)
        let unlocked = try await probes(["photo"], enabled: true)
        XCTAssertTrue(unlocked, "После ошибки сохранения выбор фото недоступен: \(PickerProbe.enabled)")
        XCTAssertEqual(form.error, "Не сохранилось"); XCTAssertEqual(saved, [])
    }

    /// 4. Загрузка, начатая до «Сохранить», не может завершиться во время сохранения: пока она идёт, сохранить нельзя
    /// (PhotoUploadingKey, L.2.28), а когда «Сохранить» становится доступной, фото уже в форме и уходит в её копии
    func test04_UploadStartedBeforeSave() async throws {
        defer { hide() }
        let doc = Doc(["image": "old.jpg"])
        let upload = PhotoUpload()
        upload.start({ [self] () async throws -> String in try await withCheckedThrowingContinuation { gates["A"] = $0 } }, apply: { doc.v["image"] = $0 }, fail: { _ in })
        _ = try await until { self.gates["A"] != nil }
        var blocked = PhotoUploadingKey.defaultValue
        PhotoUploadingKey.reduce(value: &blocked) { upload.busy }
        XCTAssertTrue(blocked, "Во время загрузки форму можно сохранить")
        try XCTUnwrap(gates.removeValue(forKey: "A")).resume(returning: "new.jpg")
        _ = try await until { !upload.busy }
        XCTAssertEqual(doc.str("image"), "new.jpg", "«Сохранить» доступна, а фото ещё не в форме")
        // теперь сохранение возьмёт копию с новым фото; во время него выбрать другое фото нельзя
        let form = SaveForm()
        try show(form, photos: ["image"])
        let copy = doc.v; try await startSave(form)
        let locked = try await probes(["image"], enabled: false)
        XCTAssertTrue(locked); XCTAssertEqual(copy["image"] as? String, "new.jpg")
        try answer()
        _ = try await probes(["image"], enabled: true)
    }

    /// 5. Форма с несколькими полями фото («Разделы»: по фото на раздел): закрыты все на время сохранения, открыты все после
    func test05_SeveralPhotoFields() async throws {
        defer { hide() }
        let form = SaveForm(), names = ["image_women", "image_men", "image_kids"]
        try show(form, photos: names)
        _ = try await probes(names, enabled: true)
        try await startSave(form)
        let locked = try await probes(names, enabled: false)
        XCTAssertTrue(locked, "Не все поля фото закрыты во время сохранения: \(PickerProbe.enabled)")
        try answer()
        let unlocked = try await probes(names, enabled: true)
        XCTAssertTrue(unlocked, "Не все поля фото открыты после сохранения: \(PickerProbe.enabled)")
    }

    /// 6. ColorPhotos: две параллельные загрузки одного цвета — сохранить нельзя, пока не закончатся обе (PhotoBatchUpload,
    /// L.2.29); затем сохранение закрывает выбор фото у всех цветов, и новых загрузок во время него не начать
    func test06_ColorPhotosParallelUploads() async throws {
        defer { hide() }
        let batch = PhotoBatchUpload()
        for names in [["P1", "P2"], ["Q1"]] {
            batch.start(names, { [self] (n: String) async throws -> String in try await withCheckedThrowingContinuation { gates[n] = $0 } }, add: { [self] in added.append($0) }, fail: { _ in })
        }
        _ = try await until { self.gates["P1"] != nil && self.gates["Q1"] != nil }
        XCTAssertEqual(batch.running, 2); XCTAssertTrue(batch.busy, "Во время загрузок фото цвета форму можно сохранить")
        try XCTUnwrap(gates.removeValue(forKey: "Q1")).resume(returning: "Q1.jpg")
        _ = try await until { batch.running == 1 }
        XCTAssertTrue(batch.busy, "Конец одной загрузки разблокировал сохранение, пока идёт другая")
        try XCTUnwrap(gates.removeValue(forKey: "P1")).resume(returning: "P1.jpg")
        _ = try await until { self.gates["P2"] != nil }
        try XCTUnwrap(gates.removeValue(forKey: "P2")).resume(returning: "P2.jpg")
        _ = try await until { !batch.busy }
        XCTAssertEqual(added.sorted(), ["P1.jpg", "P2.jpg", "Q1.jpg"])
        let form = SaveForm(), colors = ["color_c1", "color_c2"]
        try show(form, photos: colors)
        try await startSave(form)
        let locked = try await probes(colors, enabled: false)
        XCTAssertTrue(locked, "Во время сохранения карточки можно выбрать фото цвета: \(PickerProbe.enabled)")
        try answer()
        _ = try await probes(colors, enabled: true)
    }

    /// 7. Обычные поля: с этапа L.2.31 во время сохранения закрыто всё содержимое формы (AdminPage .disabled(busy)),
    /// не только выбор фото, — поля без фото тоже недоступны, а после сохранения снова доступны
    func test07_FieldsWithoutPhotosLockedToo() async throws {
        defer { hide() }
        let form = SaveForm()
        try show(form, photos: [], plain: ["name", "price"])
        _ = try await probes(["name", "price"], enabled: true)
        try await startSave(form)
        let rendered = try await until { SavingWitness.seen.last == true }
        XCTAssertTrue(rendered, "Форма не перерисовалась с сохранением")
        let locked = try await probes(["name", "price"], enabled: false)
        XCTAssertTrue(locked, "Во время сохранения поле без фото доступно: \(PickerProbe.enabled)")
        try answer()
        let unlocked = try await probes(["name", "price"], enabled: true)
        XCTAssertTrue(unlocked, "После сохранения поле без фото недоступно: \(PickerProbe.enabled)")
    }
}

/// Состояние сохранения формы — busy и error, как @State в SettingsForm, CollectionEdit, SlideEdit, AdminBrand
@MainActor
private final class SaveForm: ObservableObject {
    @Published var busy = false
    @Published var error: String?
}

/// Форма на настоящем AdminPage: поля фото — пробы с замком photoPickingLockedWhileSaving (как PhotosPicker в полях),
/// обычные поля — пробы без него
private struct ProbeForm: View {
    @ObservedObject var form: SaveForm
    let photos: [String], plain: [String]
    var body: some View {
        AdminPage(title: "Проба", busy: form.busy, error: form.error, onSave: {}) {
            ForEach(photos, id: \.self) { PickerProbe(name: $0).photoPickingLockedWhileSaving() }
            ForEach(plain, id: \.self) { PickerProbe(name: $0) }
            SavingWitness()
        }
    }
}

/// Записывает, доступна ли она (isEnabled) при каждой отрисовке
private struct PickerProbe: View {
    @MainActor static var enabled: [String: Bool] = [:]
    let name: String
    @Environment(\.isEnabled) private var isEnabled
    var body: some View {
        let _ = PickerProbe.record(name, isEnabled)
        Color.clear.frame(width: 10, height: 10)
    }
    @MainActor static func record(_ name: String, _ on: Bool) { enabled[name] = on }
}

/// Записывает, какое «идёт сохранение» (adminSaving) AdminPage передал полям формы при каждой отрисовке
private struct SavingWitness: View {
    @MainActor static var seen: [Bool] = []
    @Environment(\.adminSaving) private var saving
    var body: some View {
        let _ = SavingWitness.record(saving)
        Color.clear.frame(width: 10, height: 10)
    }
    @MainActor static func record(_ on: Bool) { seen.append(on) }
}
