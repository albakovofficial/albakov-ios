import XCTest
import UIKit
import ImageIO
import UniformTypeIdentifiers
@testable import Albakov

/// Этапы J и J.1, DEF-1: фото панели (ImageKit.jpeg). До J.1 снимок рисовался в масштабе экрана (4000–6000 px вместо 2000),
/// раскодировался целиком на главном потоке, детальные снимки превышали предел сервера 8 МБ.
/// Строки «DEF1 …» — замеры для отчёта (те же исходники, что в замере этапа J), остальное — проверки исправления
final class ImageKitMeasureTests: XCTestCase {
    private enum Texture: String { case smooth = "гладкое", grain = "с зерном", noise = "шум" }
    /// Предел сервера на файл (albakov-shop, lib/app/api-admin.js)
    private let serverLimit = 8 * 1024 * 1024

    // MARK: Исходники и замеры

    /// Исходник: JPEG качества 0,9. Гладкое — градиент (сжимается сильнее любого снимка); с зерном — градиент
    /// и полупрозрачный шум (ближе к снимку камеры); шум — случайные пиксели (худший случай для размера файла)
    private func source(_ w: Int, _ h: Int, _ t: Texture) -> Data? {
        picture(w, h, t).flatMap { encode($0, type: .jpeg) }
    }
    private func picture(_ w: Int, _ h: Int, _ t: Texture) -> CGImage? {
        guard let ctx = bitmap(w, h) else { return nil }
        if t == .noise, let raw = ctx.data { arc4random_buf(raw, w * h * 4) } else {
            let colors = [UIColor(red: 0.2, green: 0.5, blue: 0.6, alpha: 1).cgColor, UIColor(red: 0.9, green: 0.6, blue: 0.3, alpha: 1).cgColor]
            guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil) else { return nil }
            ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: w, y: h), options: [])
            if t == .grain, let tile = bitmap(256, 256), let raw = tile.data {
                arc4random_buf(raw, 256 * 256 * 4)
                if let n = tile.makeImage() { ctx.setAlpha(0.08); ctx.draw(n, in: CGRect(x: 0, y: 0, width: 256, height: 256), byTiling: true) }
            }
        }
        return ctx.makeImage()
    }
    private func bitmap(_ w: Int, _ h: Int) -> CGContext? {
        CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    }
    /// Файл картинки нужного формата; orientation — поворот EXIF (1–8)
    private func encode(_ img: CGImage, type: UTType, orientation: Int? = nil) -> Data? {
        let out = NSMutableData()
        guard let dst = CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil) else { return nil }
        var props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.9]
        if let orientation { props[kCGImagePropertyOrientation] = orientation }
        CGImageDestinationAddImage(dst, img, props as CFDictionary)
        return CGImageDestinationFinalize(dst) ? out as Data : nil
    }
    private func pixels(_ d: Data) -> (w: Int, h: Int, type: String) {
        guard let s = CGImageSourceCreateWithData(d as CFData, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as? [CFString: Any] else { return (0, 0, "") }
        return ((p[kCGImagePropertyPixelWidth] as? Int) ?? 0, (p[kCGImagePropertyPixelHeight] as? Int) ?? 0, (CGImageSourceGetType(s) as String?) ?? "")
    }
    /// Память процесса (phys_footprint), байты
    private static func footprint() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return kr == KERN_SUCCESS ? Int64(info.phys_footprint) : 0
    }
    /// Пик памяти: опрос в фоне раз в 2 мс, пока идёт замеряемое
    private final class Peak: @unchecked Sendable { let lock = NSLock(); var value: Int64 = 0; var running = true }
    /// Результат операции и пик памяти за время её выполнения. На главном акторе, как и вызывающие тесты (этап L.2.17):
    /// замыкание и раньше шло на главном акторе, а тяжёлая обработка — вне его, в самом ImageKit.jpeg (Task.detached).
    /// Память опрашивает свой фоновый поток; phys_footprint — память всего процесса, от потока замера не зависит
    @MainActor private func sampling<T>(_ body: () async throws -> T) async rethrows -> (value: T, peak: Int64) {
        let peak = Peak(), base = Self.footprint()
        Thread {
            while peak.lock.withLock({ peak.running }) { let f = Self.footprint(); peak.lock.withLock { peak.value = max(peak.value, f) }; usleep(2000) }
        }.start()
        defer { peak.lock.withLock { peak.running = false } }
        let value = try await body()
        return (value, max(0, peak.lock.withLock { peak.value } - base))
    }
    /// Пропорции те же: ориентация (стоя/лёжа) сохранена, короткая сторона — с точностью до пикселя (ImageIO округляет)
    private func sameShape(_ w: Int, _ h: Int, _ ow: Int, _ oh: Int) -> Bool {
        (ow >= oh) == (w >= h) && abs(min(ow, oh) - Int((Double(min(w, h)) * Double(max(ow, oh)) / Double(max(w, h))).rounded())) <= 1
    }
    private func mb(_ b: Int64) -> String { String(format: "%.1f", Double(b) / 1_048_576) }
    /// XCTContext.runActivity — на главном акторе; log вызывают только тесты на главном акторе (этап L.2.16)
    @MainActor private func log(_ line: String) { print(line); XCTContext.runActivity(named: line) { _ in } }

    /// Замер на тех же исходниках, что в этапе J (до исправления): размер, байты, время, пик памяти
    @MainActor
    func test01_MeasureJpeg() async throws {
        let scale = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.scale ?? 0
        for (w, h) in [(4032, 3024), (8064, 6048)] {
            for t in [Texture.smooth, .grain, .noise] {
                guard let src = autoreleasepool(invoking: { source(w, h, t) }) else { XCTFail("Не получилось создать исходник \(w)×\(h)"); continue }
                let t0 = Date()
                let (out, grow) = try await sampling { try await ImageKit.jpeg(src) }
                let ms = Int(Date().timeIntervalSince(t0) * 1000)
                let (ow, oh, _) = pixels(out)
                log("DEF1 \(w)×\(h) \(t.rawValue): исходник \(mb(Int64(src.count))) МБ → \(ow)×\(oh) px, \(mb(Int64(out.count))) МБ, "
                    + "в base64 \(mb(Int64(out.count) * 4 / 3)) МБ; \(ms) мс вне главного потока; пик памяти +\(mb(grow)) МБ; масштаб экрана \(scale)")
                XCTAssertEqual(max(ow, oh), 2000, "Длинная сторона не 2000 px: \(ow)×\(oh)")
                XCTAssertLessThanOrEqual(out.count, serverLimit, "Файл больше предела сервера 8 МБ")
                XCTAssertTrue(sameShape(w, h, ow, oh), "Пропорции изменились: \(ow)×\(oh)")
            }
        }
    }

    // MARK: Размер и пропорции

    /// Не крупнее 2000 px в пикселях, независимо от экрана; меньший снимок не увеличивается; пропорции те же
    func test02_SizeAndProportions() async throws {
        for (w, h) in [(4032, 3024), (3024, 4032), (6000, 1000), (1200, 900), (2000, 2000), (1, 1)] {
            guard let src = source(w, h, .grain) else { XCTFail("Нет исходника \(w)×\(h)"); continue }
            let out = try await ImageKit.jpeg(src)
            let (ow, oh, type) = pixels(out)
            XCTAssertEqual(type, UTType.jpeg.identifier, "\(w)×\(h): результат не JPEG")
            XCTAssertEqual(max(ow, oh), min(2000, max(w, h)), "\(w)×\(h) → \(ow)×\(oh)")
            XCTAssertTrue(sameShape(w, h, ow, oh), "\(w)×\(h) → \(ow)×\(oh): пропорции")
        }
    }

    /// Поворот из EXIF применён: снимок, записанный «лёжа» с отметкой «повернуть на 90°», приходит стоя,
    /// и красный угол оказывается там, где его видит пользователь
    func test03_ExifOrientation() async throws {
        guard let ctx = bitmap(300, 200) else { return XCTFail("Нет холста") }
        ctx.setFillColor(UIColor.blue.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: 300, height: 200))
        ctx.setFillColor(UIColor.red.cgColor); ctx.fill(CGRect(x: 0, y: 150, width: 50, height: 50))   // верхний левый угол файла
        guard let img = ctx.makeImage(), let src = encode(img, type: .jpeg, orientation: 6) else { return XCTFail("Нет исходника") }
        let out = try await ImageKit.jpeg(src)
        let (ow, oh, _) = pixels(out)
        XCTAssertEqual([ow, oh], [200, 300], "Поворот на 90° не применён: \(ow)×\(oh)")
        // ориентация 6: верх файла становится правым краем — красный угол справа сверху, синий — слева снизу
        guard let s = CGImageSourceCreateWithData(out as CFData, nil), let cg = CGImageSourceCreateImageAtIndex(s, 0, nil),
              let probe = bitmap(ow, oh), let raw = probe.data else { return XCTFail("Результат не читается") }
        probe.draw(cg, in: CGRect(x: 0, y: 0, width: ow, height: oh))
        let (corner, opposite) = withExtendedLifetime(probe) { () -> ([Int], [Int]) in   // буфер probe жив, пока читаем
            let px = raw.bindMemory(to: UInt8.self, capacity: ow * oh * 4)
            func rgb(_ x: Int, _ fromTop: Int) -> [Int] { let i = (fromTop * ow + x) * 4; return [Int(px[i]), Int(px[i + 1]), Int(px[i + 2])] }
            return (rgb(ow - 20, 20), rgb(20, oh - 20))
        }
        XCTAssertTrue(corner[0] > 180 && corner[2] < 80, "Справа сверху не красный: \(corner)")
        XCTAssertTrue(opposite[2] > 180 && opposite[0] < 80, "Слева снизу не синий: \(opposite)")
        let props = CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as? [CFString: Any]
        XCTAssertEqual((props?[kCGImagePropertyOrientation] as? Int) ?? 1, 1, "В результате осталась отметка поворота — снимок повернулся бы дважды")
    }

    // MARK: Главный поток и память

    /// Обработка идёт вне главного потока: пока большой снимок уменьшается, главный поток продолжает работать.
    /// До J.1 он стоял всё время обработки (до 1,4 с на снимок 48 Мп). Порог 0,5 с — с запасом на медленный симулятор CI
    /// и работу самого приложения (тесты идут внутри него)
    @MainActor
    func test04_MainThreadStaysResponsive() async throws {
        guard let src = autoreleasepool(invoking: { source(8064, 6048, .noise) }) else { return XCTFail("Нет исходника") }
        let ticker = Ticker()
        let t0 = Date()
        _ = try await ImageKit.jpeg(src)
        let total = Date().timeIntervalSince(t0)
        let (count, gap) = await ticker.stop()
        log("DEF1 главный поток: обработка 48 Мп \(Int(total * 1000)) мс, отметок главного потока \(count), самая долгая пауза \(Int(gap * 1000)) мс")
        XCTAssertGreaterThan(count, 3, "Главный поток не работал во время обработки")
        XCTAssertLessThan(gap, 0.5, "Главный поток стоял \(Int(gap * 1000)) мс из \(Int(total * 1000))")
    }
    /// Отметки главного потока раз в 10 мс: самая долгая пауза между ними — сколько главный поток был занят
    @MainActor private final class Ticker {
        private var stamps: [Date] = []
        private var task: Task<Void, Never>?
        init() { task = Task { @MainActor [weak self] in while let self, !Task.isCancelled { self.stamps.append(Date()); try? await Task.sleep(nanoseconds: 10_000_000) } } }
        func stop() async -> (count: Int, gap: TimeInterval) {
            stamps.append(Date())
            task?.cancel(); await task?.value
            return (stamps.count, zip(stamps, stamps.dropFirst()).map { $1.timeIntervalSince($0) }.max() ?? 0)
        }
    }

    /// Десять больших снимков подряд, как десять фото цвета: память не копится и не растёт до размеров целого снимка
    /// (раскодированный снимок 48 Мп — около 186 МБ; до J.1 пик был +140–185 МБ на каждый снимок)
    @MainActor
    func test05_TenPhotosMemory() async throws {
        guard let src = autoreleasepool(invoking: { source(8064, 6048, .grain) }) else { return XCTFail("Нет исходника") }
        let before = Self.footprint()
        let (sizes, grow) = try await sampling { () async throws -> [Int] in
            var acc: [Int] = []
            for _ in 0..<10 { acc.append(try await ImageKit.jpeg(src).count) }
            return acc
        }
        let left = max(0, Self.footprint() - before)
        log("DEF1 десять снимков 48 Мп: пик памяти +\(mb(grow)) МБ, после обработки +\(mb(left)) МБ, файлы \(sizes.map { mb(Int64($0)) }.joined(separator: ", ")) МБ")
        XCTAssertEqual(sizes.count, 10)
        XCTAssertLessThan(grow, 120 * 1_048_576, "Пик памяти при 10 снимках +\(mb(grow)) МБ")
        XCTAssertLessThan(left, 40 * 1_048_576, "После обработки память не вернулась: +\(mb(left)) МБ")
    }

    // MARK: Форматы и повреждённые файлы

    /// Форматы галереи (JPEG, HEIC, PNG) и файлов (GIF, TIFF) — в JPEG до 2000 px.
    /// HEIC — если симулятор умеет его записывать (список форматов — в журнале)
    @MainActor
    func test06_SupportedFormats() async throws {
        let writable = (CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? []
        // с зерном, а не однотонная: однотонный GIF 3000×2000 сжимается в 1:1000+, и ImageIO отвергает его как испорченный
        guard let img = picture(3000, 2000, .grain) else { return XCTFail("Нет картинки") }
        var checked: [String] = []
        for type in [UTType.jpeg, .heic, .png, .gif, .tiff] where writable.contains(type.identifier) {
            guard let src = encode(img, type: type) else {   // HEIC: на Intel-симуляторе без кодировщика HEVC тип заявлен, но не пишется
                if type == .heic { log("DEF1 форматы: HEIC в симуляторе не записывается — пропущен"); continue }
                XCTFail("\(type.identifier): не записывается"); continue
            }
            do {
                let (ow, oh, t) = pixels(try await ImageKit.jpeg(src))
                XCTAssertEqual(t, UTType.jpeg.identifier, "\(type.identifier): результат не JPEG")
                XCTAssertTrue(ow == 2000 && abs(oh - 1333) <= 1, "\(type.identifier) → \(ow)×\(oh)")   // 1333,3: ImageIO округляет
                checked.append(type.preferredFilenameExtension ?? type.identifier)
            } catch {
                // HEIC на Intel-симуляторе: файл записывается, но сама система его не раскодирует (нет декодера HEVC) — не ошибка ImageKit
                let decodes = CGImageSourceCreateWithData(src as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) } != nil
                log("DEF1 форматы: \(type.identifier) не открылся (\(error)); система раскодирует файл целиком: \(decodes ? "да" : "нет")")
                if type == .heic && !decodes { continue }
                XCTFail("\(type.identifier): \(error)")
            }
        }
        log("DEF1 форматы: " + checked.joined(separator: ", "))
        XCTAssertTrue(["jpeg", "png"].allSatisfy(checked.contains), "Не проверены основные форматы: \(checked)")
    }

    /// Не картинка или пустой файл — понятная ошибка «Не получилось открыть фото» (раньше исходные байты уходили
    /// на сервер как JPEG); обрезанный JPEG — либо та же ошибка, либо то, что ImageIO смог прочесть, не крупнее 2000 px
    func test07_BrokenFilesFailSafely() async throws {
        var random = Data(count: 4096)
        random.withUnsafeMutableBytes { if let p = $0.baseAddress { arc4random_buf(p, 4096) } }
        for (name, data) in [("пустой файл", Data()), ("случайные байты", random), ("текст", Data("<html>не фото</html>".utf8))] {
            do {
                let out = try await ImageKit.jpeg(data)
                XCTFail("\(name): принят как фото, \(out.count) Б")
            } catch {
                XCTAssertTrue(error is ImageKit.OpenFailed, "\(name): \(error)")
            }
        }
        guard let full = source(1600, 1200, .grain) else { return XCTFail("Нет исходника") }
        for cut in [full.prefix(full.count / 2), full.prefix(200)] {
            do {
                let (ow, oh, t) = pixels(try await ImageKit.jpeg(Data(cut)))
                XCTAssertTrue(t == UTType.jpeg.identifier && max(ow, oh) <= 2000, "Обрезанный файл: \(ow)×\(oh) \(t)")
            } catch {
                XCTAssertTrue(error is ImageKit.OpenFailed, "Обрезанный файл: \(error)")
            }
        }
    }
}
