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
        let created = CheckoutNonce.loadOrCreate(d)
        XCTAssertEqual(d.string(forKey: CheckoutNonce.key), created, "Ключ не сохранён при открытии оформления")
    }

    /// Повторное открытие экрана (и перезапуск приложения — новое чтение той же памяти) — ключ тот же
    func test02_ReopenKeepsSameKey() {
        let first = CheckoutNonce.loadOrCreate(d)
        XCTAssertEqual(CheckoutNonce.loadOrCreate(d), first)          // экран оформления открыли снова
        let again = UserDefaults(suiteName: suite)!                     // «перезапуск»: память читается заново
        XCTAssertEqual(CheckoutNonce.loadOrCreate(again), first)
    }

    /// Обрыв связи: заказ не подтверждён — ключ не меняется, повторная отправка того же заказа даёт тот же idem
    func test03_ConnectionDropRetrySameIdem() {
        let sent = CheckoutView.idem(CheckoutNonce.loadOrCreate(d), body)
        // ответ не пришёл — renew() не вызывается
        let retry = CheckoutView.idem(CheckoutNonce.loadOrCreate(d), body)
        XCTAssertEqual(sent, retry, "Повтор после обрыва ушёл с другим ключом — сервер создаст второй заказ")
        XCTAssertEqual(sent.count, 40)
    }

    /// Повторная отправка с другими данными — это уже другой заказ: другой idem
    func test04_ResendWithChangedOrderGetsOtherIdem() {
        var other = body; other["deliveryId"] = "door"
        let key = CheckoutNonce.loadOrCreate(d)
        XCTAssertNotEqual(CheckoutView.idem(key, body), CheckoutView.idem(key, other))
    }

    /// Успешное создание заказа: ключ меняется, следующий заказ с теми же данными — новый
    func test05_SuccessRenewsKey() {
        let before = CheckoutNonce.loadOrCreate(d)
        let after = CheckoutNonce.renew(d)
        XCTAssertNotEqual(before, after)
        XCTAssertEqual(CheckoutNonce.loadOrCreate(d), after, "Новый ключ не сохранён")
        XCTAssertNotEqual(CheckoutView.idem(after, body), CheckoutView.idem(before, body))
    }

    /// Обновление с прошлой версии: ключ, уже сохранённый у покупателя, не теряется
    func test06_ExistingKeyFromPreviousVersionKept() {
        d.set("ключ-из-1.0.3", forKey: "checkoutNonce")
        XCTAssertEqual(CheckoutNonce.loadOrCreate(d), "ключ-из-1.0.3")
    }
}

// MARK: - IOS-04, IOS-05: стабильные ключи строк

final class RowKeysTests: XCTestCase {
    private func rows(_ n: Int) -> [[String: Any]] { (0..<n).map { ["id": "r\($0)", "name": "строка \($0)"] } }
    private func names(_ r: [[String: Any]]) -> [String] { r.map { $0["name"] as? String ?? "" } }
    /// Ключи, подстроенные под список из n строк, — как после первого показа экрана
    private func matched(_ n: Int) -> RowKeys { var k = RowKeys(); k.match(count: n); return k }

    /// Удаление последней строки, пока её поле в фокусе: поле при потере фокуса пишет ещё раз — запись не выполняется, падения нет
    func test01_DeleteLastWhileEditingDropsLateWrite() {
        var r = rows(3); var k = matched(3); let ids = k.displayKeys(count: 3)
        k.remove(ids[2], from: &r)
        XCTAssertEqual(r.count, 2); XCTAssertEqual(k.displayKeys(count: 2), Array(ids.prefix(2)))
        XCTAssertFalse(k.update(ids[2], in: &r, { $0["name"] = "поздняя запись" }), "Запись в удалённую строку")
        XCTAssertNil(k.row(ids[2], in: r))
        XCTAssertEqual(names(r), ["строка 0", "строка 1"])
    }

    /// После удаления правка соседней строки попадает именно в неё
    func test02_EditNeighbourAfterDelete() {
        var r = rows(4); var k = matched(4); let ids = k.displayKeys(count: 4)
        k.remove(ids[1], from: &r)
        XCTAssertTrue(k.update(ids[2], in: &r, { $0["name"] = "правка" }))
        XCTAssertEqual(names(r), ["строка 0", "правка", "строка 3"])
        XCTAssertEqual(r[1]["id"] as? String, "r2")
    }

    /// Перестановка ↑ ↓: ключ едет вместе со строкой; за границу — ничего не меняется
    func test03_MoveKeepsKeyWithRow() {
        var r = rows(3); var k = matched(3); let ids = k.displayKeys(count: 3)
        k.move(ids[0], by: 1, in: &r)
        XCTAssertEqual(r[1]["id"] as? String, "r0")
        k.update(ids[0], in: &r, { $0["name"] = "после перестановки" })
        XCTAssertEqual(names(r), ["строка 1", "после перестановки", "строка 2"])
        k.move(ids[0], by: 5, in: &r)
        XCTAssertEqual(r[1]["id"] as? String, "r0")
    }

    /// «Добавить» и сразу удалить; повторное удаление того же ключа — без изменений
    func test04_AppendThenDeleteTwice() {
        var r = rows(2); var k = matched(2)
        k.append(["id": "new", "name": ""], to: &r)
        let added = k.displayKeys(count: 3)[2]
        XCTAssertEqual(r.count, 3)
        k.remove(added, from: &r); k.remove(added, from: &r)
        XCTAssertEqual(r.count, 2); XCTAssertEqual(k.displayKeys(count: 2).count, 2)
    }

    /// Список заменили целиком (загрузка с сервера): ключи подстраиваются под новое число строк, при том же — не меняются
    func test05_MatchAfterExternalReplace() {
        var k = matched(2); let old = k.displayKeys(count: 2)
        k.match(count: 2); XCTAssertEqual(k.displayKeys(count: 2), old, "При том же числе строк ключи не должны меняться")
        XCTAssertNotEqual(k.displayKeys(count: 3), k.displayKeys(count: 3), "До подстройки ключи временные")
        k.match(count: 5)
        let five = k.displayKeys(count: 5)
        XCTAssertEqual(five.count, 5); XCTAssertEqual(k.displayKeys(count: 5), five)
    }

    /// Упаковки СДЭК (IOS-05): удалить последнюю, пока её поле веса в фокусе; правка соседней — по ключу
    func test06_PacksDeleteLastWhileEditingWeight() {
        var packs: [[String: Any]] = [["id": "bag", "name": "Пакет", "weight": 20], ["id": "m", "name": "Коробка M", "weight": 150], ["id": "pk1", "name": "", "weight": 50]]
        var k = matched(packs.count); let ids = k.displayKeys(count: packs.count)
        k.update(ids[2], in: &packs, { $0["weight"] = 777 })
        k.remove(ids[2], from: &packs)
        XCTAssertFalse(k.update(ids[2], in: &packs, { $0["weight"] = 7777 }))
        XCTAssertTrue(k.update(ids[1], in: &packs, { $0["weight"] = 155; $0["name"] = "Коробка M 2" }))
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

    /// Прежний способ (до этапа A, 1.0.3): UIImage целиком → рисование 1600 px → JPEG 0,85. Только для сравнения
    private func referenceJPEG(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let k = min(1, 1600 / max(image.size.width, image.size.height))
        let size = CGSize(width: (image.size.width * k).rounded(), height: (image.size.height * k).rounded())
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: size, format: fmt).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }.jpegData(compressionQuality: 0.85)
    }

    /// Отправка — прежние размер и качество: до 1600 px по длинной стороне, JPEG; миниатюра — до 300 px
    func test01_UploadKeepsSizeAndQuality() {
        let p = Support.photo(Self.big[0])!
        XCTAssertEqual(max(pixels(p.jpeg).width, pixels(p.jpeg).height), 1600)
        XCTAssertEqual(pixels(p.jpeg).width / pixels(p.jpeg).height, 8056.0 / 6040.0, accuracy: 0.01)
        XCTAssertEqual(max(pixels(p.thumbnail).width, pixels(p.thumbnail).height), Support.thumbPixels)
        // тот же размер, что у прежнего способа
        let data = Self.makeJPEG(width: 4000, height: 3000)
        XCTAssertEqual(pixels(referenceJPEG(data)!), pixels(Support.photo(data)!.jpeg))
    }

    /// Поворот из EXIF учитывается, как раньше; маленькое фото не увеличивается; не фото — nil
    func test02_OrientationAndNoUpscale() {
        let rotated = Self.makeJPEG(width: 4000, height: 3000, orientation: 6)
        let portrait = Support.photo(rotated)!
        XCTAssertEqual(pixels(portrait.jpeg), CGSize(width: 1200, height: 1600))
        XCTAssertEqual(pixels(portrait.thumbnail), CGSize(width: 225, height: 300))
        XCTAssertEqual(pixels(referenceJPEG(rotated)!), pixels(portrait.jpeg), "Поворот не совпадает с прежним способом")
        let small = Support.photo(Self.makeJPEG(width: 800, height: 600))!
        XCTAssertEqual(pixels(small.jpeg), CGSize(width: 800, height: 600))
        XCTAssertNil(Support.photo(Data("не фото".utf8)))
    }

    /// Пять больших фото: в памяти только миниатюры, на сервер уходит JPEG 1600 px; после «Убрать» и закрытия — память освобождена
    func test03_FiveLargePhotosKeepOnlyThumbnails() async throws {
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
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertNil(firstThumb, "Миниатюра осталась в памяти после «Убрать фото»")

        await att!.add(Self.big[1])
        weak var closed: SupportAttachments?
        weak var closedThumb: UIImage?
        autoreleasepool { closed = att; closedThumb = att!.items.first?.image }
        att = nil                                     // окно обращения закрыли
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertNil(closed, "Фото обращения остались в памяти после закрытия окна")
        XCTAssertNil(closedThumb)
    }

    /// Экран ушёл, пока фото готовилось (задача отменена): фото не показывается и не отправляется
    func test05_CancelledWhileProcessingAddsNothing() async {
        var uploads = 0
        let att = SupportAttachments(uploadPath: "support/upload") { _ in uploads += 1; return "f.jpg" }
        let task = Task { await att.add(Self.big[0]) }
        task.cancel()          // задача ещё не началась: главный поток занят тестом
        await task.value
        XCTAssertTrue(att.items.isEmpty, "Фото добавлено после отмены")
        XCTAssertEqual(uploads, 0, "Фото отправлено после отмены")
    }

    /// Ошибка отправки — фото убирается из полоски, как и раньше
    func test04_UploadErrorRemovesPhoto() async {
        struct Fail: Error {}
        let att = SupportAttachments(uploadPath: "support/upload") { _ in throw Fail() }
        await att.add(Self.makeJPEG(width: 2000, height: 1500))
        XCTAssertTrue(att.items.isEmpty)
    }
}
