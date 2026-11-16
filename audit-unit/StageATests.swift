import XCTest
import UIKit
import ImageIO
import UniformTypeIdentifiers
@testable import Albakov

/// Юнит-тесты этапа A (аудит 16.11): IOS-01, IOS-03, IOS-04, IOS-05.
/// Только проверка, в приложение не входят. Собираются целью AlbakovUnit, которую создаёт audit.yml (project.yml не меняется).

// MARK: - IOS-01: ключ повтора заказа

final class CheckoutNonceTests: XCTestCase {
    private var d: UserDefaults!
    private var suite = ""
    private let body: [String: Any] = ["lines": [["productId": "p5", "colorId": "c1", "size": "L", "qty": 1]], "deliveryId": "pvz", "payment": "online",
                                       "customer": ["firstName": "Пётр", "lastName": "Тестов", "phone": "79070000001", "email": "t@example.com"], "consent": true]

    override func setUp() {
        suite = "stage-a-nonce-" + UUID().uuidString
        d = UserDefaults(suiteName: suite)
    }
    override func tearDown() { d.removePersistentDomain(forName: suite) }

    /// Первый запуск оформления: ключа ещё нет — он создаётся и сохраняется сразу, до отправки заказа
    func test01_FirstCheckoutSavesKeyBeforeSending() {
        XCTAssertNil(d.string(forKey: CheckoutNonce.key))
        CheckoutNonce.prepare(d)
        let saved = d.string(forKey: CheckoutNonce.key)
        XCTAssertNotNil(saved, "Ключ не сохранён при открытии оформления")
        XCTAssertEqual(CheckoutNonce.current(d), saved)
    }

    /// Повторное открытие экрана (и перезапуск приложения — новое чтение той же памяти) — ключ тот же
    func test02_ReopenKeepsSameKey() {
        CheckoutNonce.prepare(d)
        let first = CheckoutNonce.current(d)
        CheckoutNonce.prepare(d)                       // экран оформления открыли снова
        XCTAssertEqual(CheckoutNonce.current(d), first)
        let again = UserDefaults(suiteName: suite)!     // «перезапуск»: память читается заново
        XCTAssertEqual(CheckoutNonce.current(again), first)
    }

    /// Обрыв связи: заказ не подтверждён — ключ не меняется, повторная отправка того же заказа даёт тот же idem
    func test03_ConnectionDropRetrySameIdem() {
        CheckoutNonce.prepare(d)
        let sent = CheckoutView.idem(CheckoutNonce.current(d), body)
        // ответ не пришёл — rotate() не вызывается
        CheckoutNonce.prepare(d)
        let retry = CheckoutView.idem(CheckoutNonce.current(d), body)
        XCTAssertEqual(sent, retry, "Повтор после обрыва ушёл с другим ключом — сервер создаст второй заказ")
        XCTAssertEqual(sent.count, 40)
    }

    /// Повторная отправка с другими данными — это уже другой заказ: другой idem
    func test04_ResendWithChangedOrderGetsOtherIdem() {
        CheckoutNonce.prepare(d)
        var other = body; other["deliveryId"] = "door"
        XCTAssertNotEqual(CheckoutView.idem(CheckoutNonce.current(d), body), CheckoutView.idem(CheckoutNonce.current(d), other))
    }

    /// Успешное создание заказа: ключ меняется, следующий заказ с теми же данными — новый
    func test05_SuccessRotatesKey() {
        CheckoutNonce.prepare(d)
        let before = CheckoutNonce.current(d)
        let idemBefore = CheckoutView.idem(before, body)
        let after = CheckoutNonce.rotate(d)
        XCTAssertNotEqual(before, after)
        XCTAssertEqual(CheckoutNonce.current(d), after, "Новый ключ не сохранён")
        XCTAssertNotEqual(CheckoutView.idem(CheckoutNonce.current(d), body), idemBefore)
    }

    /// Обновление с прошлой версии: ключ, уже сохранённый у покупателя, не теряется
    func test06_ExistingKeyFromPreviousVersionKept() {
        d.set("ключ-из-1.0.3", forKey: "checkoutNonce")
        CheckoutNonce.prepare(d)
        XCTAssertEqual(CheckoutNonce.current(d), "ключ-из-1.0.3")
    }
}

// MARK: - IOS-04, IOS-05: стабильные ключи строк

final class RowKeysTests: XCTestCase {
    private func rows(_ n: Int) -> [[String: Any]] { (0..<n).map { ["id": "r\($0)", "name": "строка \($0)"] } }
    private func names(_ r: [[String: Any]]) -> [String] { r.map { $0["name"] as? String ?? "" } }

    /// Удаление последней строки, пока её поле в фокусе: поле при потере фокуса пишет ещё раз — запись не выполняется, падения нет
    func test01_DeleteLastWhileEditingDropsLateWrite() {
        var r = rows(3); var k = RowKeys(count: 3)
        let last = k.ids[2]
        k.remove(&r, last)
        XCTAssertEqual(r.count, 2); XCTAssertEqual(k.ids.count, 2)
        XCTAssertFalse(k.update(&r, last, { $0["name"] = "поздняя запись" }), "Запись в удалённую строку")
        XCTAssertNil(k.value(r, last))
        XCTAssertEqual(names(r), ["строка 0", "строка 1"])
    }

    /// После удаления правка соседней строки попадает именно в неё
    func test02_EditNeighbourAfterDelete() {
        var r = rows(4); var k = RowKeys(count: 4)
        let second = k.ids[1], third = k.ids[2]
        k.remove(&r, second)
        XCTAssertTrue(k.update(&r, third, { $0["name"] = "правка" }))
        XCTAssertEqual(names(r), ["строка 0", "правка", "строка 3"])
        XCTAssertEqual(r[1]["id"] as? String, "r2")
    }

    /// Перестановка ↑ ↓: ключ едет вместе со строкой
    func test03_MoveKeepsKeyWithRow() {
        var r = rows(3); var k = RowKeys(count: 3)
        let first = k.ids[0]
        k.move(&r, first, by: 1)
        XCTAssertEqual(r[1]["id"] as? String, "r0")
        k.update(&r, first, { $0["name"] = "после перестановки" })
        XCTAssertEqual(names(r), ["строка 1", "после перестановки", "строка 2"])
        k.move(&r, first, by: 5)   // за границу — ничего не меняется
        XCTAssertEqual(r[1]["id"] as? String, "r0")
    }

    /// «Добавить» и сразу удалить; повторное удаление того же ключа — без изменений
    func test04_AppendThenDeleteTwice() {
        var r = rows(2); var k = RowKeys(count: 2)
        k.append(&r, ["id": "new", "name": ""])
        let added = k.ids.last!
        XCTAssertEqual(r.count, 3)
        k.remove(&r, added); k.remove(&r, added)
        XCTAssertEqual(r.count, 2); XCTAssertEqual(k.ids.count, 2)
    }

    /// Список заменили целиком (загрузка с сервера): ключи подстраиваются под новое число строк
    func test05_SyncAfterExternalReplace() {
        var k = RowKeys(count: 2)
        let old = k.ids
        k.sync(2); XCTAssertEqual(k.ids, old, "При том же числе строк ключи не должны меняться")
        k.sync(5); XCTAssertEqual(k.ids.count, 5)
        XCTAssertEqual(k.ids(for: 5), k.ids)
        XCTAssertEqual(k.ids(for: 3).count, 3)   // временные ключи до подстройки
    }

    /// Упаковки СДЭК (IOS-05): удалить последнюю, пока её поле веса в фокусе; правка соседней — по ключу
    func test06_PacksDeleteLastWhileEditingWeight() {
        var packs: [[String: Any]] = [["id": "bag", "name": "Пакет", "weight": 20], ["id": "m", "name": "Коробка M", "weight": 150], ["id": "pk1", "name": "", "weight": 50]]
        var k = RowKeys(count: packs.count)
        let last = k.ids[2], neighbour = k.ids[1]
        k.update(&packs, last, { $0["weight"] = 777 })
        k.remove(&packs, last)
        XCTAssertFalse(k.update(&packs, last, { $0["weight"] = 7777 }))
        XCTAssertTrue(k.update(&packs, neighbour, { $0["weight"] = 155; $0["name"] = "Коробка M 2" }))
        XCTAssertEqual(packs.count, 2)
        XCTAssertEqual(packs[1]["weight"] as? Int, 155)
        XCTAssertEqual(packs[1]["name"] as? String, "Коробка M 2")
    }
}

// MARK: - IOS-03: фото в поддержке

@MainActor
final class SupportPhotosTests: XCTestCase {
    /// JPEG заданного размера; orientation — EXIF-поворот (6 = снято вертикально)
    nonisolated static func makeJPEG(width: Int, height: Int, orientation: Int = 1) -> Data {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.7, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(CGColor(red: 0.9, green: 0.5, blue: 0.1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 3))
        let img = ctx.makeImage()!
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, img, [kCGImagePropertyOrientation: orientation, kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        CGImageDestinationFinalize(dest)
        return out as Data
    }
    /// Пять «больших фото» ≈48 Мп (8064×6048), как у iPhone 14 Pro и новее; создаются один раз
    nonisolated static let big: [Data] = (1...5).map { i in makeJPEG(width: 8064 - i * 8, height: 6048 - i * 8) }

    private func pixels(_ img: UIImage) -> CGSize { CGSize(width: img.size.width * img.scale, height: img.size.height * img.scale) }
    private func pixels(_ jpg: Data) -> CGSize { pixels(UIImage(data: jpg)!) }
    private func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) } }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }

    /// Отправка — прежние размер и качество: до 1600 px по длинной стороне, JPEG
    func test01_UploadKeepsSizeAndQuality() {
        let jpg = Support.jpeg(data: Self.big[0])!
        XCTAssertEqual(max(pixels(jpg).width, pixels(jpg).height), 1600)
        XCTAssertEqual(pixels(jpg).width / pixels(jpg).height, 8056.0 / 6040.0, accuracy: 0.01)
        // тот же результат, что у прежнего способа (UIImage → рисование 1600 px → JPEG 0,85)
        let old = Support.jpeg(UIImage(data: Self.makeJPEG(width: 4000, height: 3000))!)!
        let new = Support.jpeg(data: Self.makeJPEG(width: 4000, height: 3000))!
        XCTAssertEqual(pixels(old), pixels(new))
    }

    /// Поворот из EXIF учитывается, как раньше; маленькое фото не увеличивается
    func test02_OrientationAndNoUpscale() {
        let portrait = Support.jpeg(data: Self.makeJPEG(width: 4000, height: 3000, orientation: 6))!
        XCTAssertEqual(pixels(portrait), CGSize(width: 1200, height: 1600))
        let old = Support.jpeg(UIImage(data: Self.makeJPEG(width: 4000, height: 3000, orientation: 6))!)!
        XCTAssertEqual(pixels(old), pixels(portrait), "Поворот не совпадает с прежним способом")
        let small = Support.jpeg(data: Self.makeJPEG(width: 800, height: 600))!
        XCTAssertEqual(pixels(small), CGSize(width: 800, height: 600))
        XCTAssertNil(Support.jpeg(data: Data("не фото".utf8)))
    }

    /// Пять больших фото: в памяти только миниатюры, на сервер уходит JPEG 1600 px; после «Убрать» и закрытия — память освобождена
    func test03_FiveLargePhotosKeepOnlyThumbnails() async {
        var uploaded: [CGSize] = []
        _ = Self.big.count            // тестовые фото создаются заранее — их создание не входит в замер
        let start = footprintMB()
        var att: SupportAttachments? = SupportAttachments(uploadPath: "support/upload") { jpg in
            uploaded.append(UIImage(data: jpg).map { CGSize(width: $0.size.width * $0.scale, height: $0.size.height * $0.scale) } ?? .zero)
            return "f\(uploaded.count).jpg"
        }
        for d in Self.big { await att!.add(d) }
        let loaded = footprintMB()
        XCTAssertEqual(att!.items.count, 5)
        XCTAssertEqual(att!.names.count, 5)
        XCTAssertEqual(att!.left, 0)
        for it in att!.items {
            XCTAssertLessThanOrEqual(max(pixels(it.image).width, pixels(it.image).height), Support.thumbPixels, "В памяти не миниатюра")
        }
        XCTAssertEqual(uploaded.count, 5)
        for s in uploaded { XCTAssertEqual(max(s.width, s.height), 1600) }
        // миниатюры занимают ~1,4 МБ; раньше держались 5 исходников (в раскодированном виде ≈190 МБ каждый)
        print("STAGEA memory MB: start \(Int(start)), with 5 photos \(Int(loaded)), growth \(Int(loaded - start))")
        XCTAssertLessThan(loaded - start, 150, "Память выросла слишком сильно")

        weak var firstThumb: UIImage?
        autoreleasepool { firstThumb = att!.items.first?.image }
        XCTAssertNotNil(firstThumb)
        let ids = att!.items.map(\.id)
        for id in ids { att!.remove(id) }
        XCTAssertTrue(att!.items.isEmpty)
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertNil(firstThumb, "Миниатюра осталась в памяти после «Убрать фото»")

        await att!.add(Self.big[1])
        weak var closed: SupportAttachments?
        weak var closedThumb: UIImage?
        autoreleasepool { closed = att; closedThumb = att!.items.first?.image }
        att = nil                                     // окно обращения закрыли
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertNil(closed, "Фото обращения остались в памяти после закрытия окна")
        XCTAssertNil(closedThumb)
    }

    /// Ошибка отправки — фото убирается из полоски, как и раньше
    func test04_UploadErrorRemovesPhoto() async {
        struct Fail: Error {}
        let att = SupportAttachments(uploadPath: "support/upload") { _ in throw Fail() }
        await att.add(Self.makeJPEG(width: 2000, height: 1500))
        XCTAssertTrue(att.items.isEmpty)
    }
}
