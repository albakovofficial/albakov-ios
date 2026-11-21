import XCTest
import UIKit
import ImageIO
import UniformTypeIdentifiers
@testable import Albakov

/// Этап L.2.25: обработка логотипа (LogoKit.process) — вне главного актора. Алгоритм не менялся: здесь его результат
/// на картинках без потерь (PNG) с известной геометрией — фон, перекраска, обрезка, прозрачность, размеры, формат,
/// ошибки, — и что главный актор не стоит, пока обрабатывается большой снимок (раньше стоял всё время обработки)
@MainActor
final class LogoKitTests: XCTestCase {
    /// PNG w×h: фон цвета bg, на нём чёрные прямоугольники (координаты — от верхнего края)
    private func png(_ w: Int, _ h: Int, bg: CGFloat = 1, rects: [CGRect] = []) -> Data? {
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(red: bg, green: bg, blue: bg, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        for r in rects { ctx.fill(CGRect(x: r.minX, y: CGFloat(h) - r.maxY, width: r.width, height: r.height)) }   // у CGContext начало внизу
        guard let img = ctx.makeImage() else { return nil }
        let out = NSMutableData()
        guard let dst = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dst, img, nil)
        return CGImageDestinationFinalize(dst) ? out as Data : nil
    }
    private struct Pixels { let type: String, w: Int, h: Int, px: [UInt8] }
    /// Результат обработки: формат, размер и пиксели RGBA (строки — сверху вниз)
    private func decode(_ d: Data) -> Pixels? {
        guard let s = CGImageSourceCreateWithData(d as CFData, nil), let cg = CGImageSourceCreateImageAtIndex(s, 0, nil) else { return nil }
        let w = cg.width, h = cg.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let ok = buf.withUnsafeMutableBytes { p -> Bool in
            guard let ctx = CGContext(data: p.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h)); return true
        }
        return ok ? Pixels(type: (CGImageSourceGetType(s) as String?) ?? "", w: w, h: h, px: buf) : nil
    }
    private func rgba(_ p: Pixels, _ x: Int, _ fromTop: Int) -> [Int] { let i = (fromTop * p.w + x) * 4; return (0..<4).map { Int(p.px[i + $0]) } }
    /// Цвет совпадает (±2 на канал: рисование логотипа может идти в другом цветовом пространстве), прозрачность — точно
    private func assertColor(_ got: [Int], _ rgb: [Int], alpha: Int, _ what: String, line: UInt = #line) {
        XCTAssertEqual(got[3], alpha, "\(what): прозрачность \(got)", line: line)
        if alpha > 0 { XCTAssertTrue(zip(got.prefix(3), rgb).allSatisfy { abs($0 - $1) <= 2 }, "\(what): цвет \(got), ожидался \(rgb)", line: line) }
    }
    /// Размер после обрезки — ±1 px: уменьшение ImageIO (1:1) может дать полупрозрачный край
    private func assertCropped(_ got: [Int], _ expected: [Int], _ what: String, line: UInt = #line) {
        XCTAssertTrue(zip(got, expected).allSatisfy { abs($0 - $1) <= 1 }, "\(what): \(got), ожидалось \(expected)", line: line)
    }
    /// Два чёрных квадрата 50×50 на белом 400×200: между ними промежуток 100 px, вокруг — поля
    private var twoSquares: Data? { png(400, 200, rects: [CGRect(x: 100, y: 50, width: 50, height: 50), CGRect(x: 250, y: 50, width: 50, height: 50)]) }

    /// Однотонный фон убирается, поля обрезаются, промежуток внутри логотипа прозрачный, сам знак — без изменений
    func test01_RemoveBackgroundCropTransparency() async throws {
        let r = try await LogoKit.process(try XCTUnwrap(twoSquares), removeBg: true, recolor: false)
        XCTAssertEqual(r.note, "Фон убран")
        assertCropped([r.w, r.h], [200, 50], "Поля не обрезаны")
        let p = try XCTUnwrap(decode(r.png))
        XCTAssertEqual(p.type, UTType.png.identifier); XCTAssertEqual([p.w, p.h], [r.w, r.h], "Размер PNG не совпадает с отданным в загрузку")
        assertColor(rgba(p, 25, 25), [0, 0, 0], alpha: 255, "Левый квадрат")
        assertColor(rgba(p, 100, 25), [0, 0, 0], alpha: 0, "Промежуток (бывший фон)")
        assertColor(rgba(p, 175, 25), [0, 0, 0], alpha: 255, "Правый квадрат")
    }

    /// Перекраска: знак — светлый #ece6dc, фон остаётся прозрачным
    func test02_Recolor() async throws {
        let r = try await LogoKit.process(try XCTUnwrap(twoSquares), removeBg: true, recolor: true)
        let p = try XCTUnwrap(decode(r.png))
        assertCropped([r.w, r.h], [200, 50], "Размер после перекраски")
        assertColor(rgba(p, 25, 25), [0xec, 0xe6, 0xdc], alpha: 255, "Знак после перекраски")
        assertColor(rgba(p, 100, 25), [0, 0, 0], alpha: 0, "Фон после перекраски")
    }

    /// Большой файл: не крупнее 2400 px при обработке, затем вписывается в 1000×300 с теми же пропорциями
    func test03_SizeLimits() async throws {
        let r = try await LogoKit.process(try XCTUnwrap(png(3000, 600, bg: 0)), removeBg: false, recolor: false)
        XCTAssertNil(r.note)
        XCTAssertEqual([r.w, r.h], [1000, 200], "3000×600 → 2400×480 → вписано в 1000×300")
        let p = try XCTUnwrap(decode(r.png))
        XCTAssertEqual([p.w, p.h], [1000, 200]); XCTAssertEqual(p.type, UTType.png.identifier)
        assertColor(rgba(p, 500, 100), [0, 0, 0], alpha: 255, "Непрозрачная картинка осталась непрозрачной")
    }

    /// Неоднородный фон (углы разного цвета) не трогается — только подсказка; картинка целиком, непрозрачная
    func test04_NonUniformBackgroundKept() async throws {
        let src = try XCTUnwrap(png(200, 100, rects: [CGRect(x: 0, y: 0, width: 10, height: 10), CGRect(x: 80, y: 30, width: 40, height: 40)]))
        let r = try await LogoKit.process(src, removeBg: true, recolor: false)
        XCTAssertTrue(r.note?.hasPrefix("Фон неоднородный") == true, "\(r.note ?? "nil")")
        XCTAssertEqual([r.w, r.h], [200, 100])
        let p = try XCTUnwrap(decode(r.png))
        assertColor(rgba(p, 150, 50), [255, 255, 255], alpha: 255, "Белый фон остался")
        assertColor(rgba(p, 100, 50), [0, 0, 0], alpha: 255, "Знак")
    }

    /// Ошибки — те же сообщения: не картинка; после удаления фона ничего не осталось
    func test05_Errors() async throws {
        do { _ = try await LogoKit.process(Data("не картинка".utf8), removeBg: false, recolor: false); XCTFail("Не картинка принята") }
        catch { XCTAssertEqual((error as? LogoKit.Fail)?.errorDescription, "Файл не похож на изображение. Подойдут PNG, JPG или WebP.") }
        do { _ = try await LogoKit.process(try XCTUnwrap(png(100, 100)), removeBg: true, recolor: false); XCTFail("Пустой логотип принят") }
        catch { XCTAssertEqual((error as? LogoKit.Fail)?.errorDescription, "После удаления фона ничего не осталось. Попробуйте без «Убрать фон».") }
    }

    /// Пока обрабатывается снимок 12 Мп (уменьшение до 2400 px и проходы по пикселям), главный актор работает: раньше
    /// обработка шла на нём и он стоял всё время. Порог 0,5 с — с запасом на медленный симулятор CI
    func test06_MainActorNotBlocked() async throws {
        let src = try XCTUnwrap(noiseJPEG(4032, 3024))
        let ticker = Ticker(), t0 = Date()
        let r = try await LogoKit.process(src, removeBg: false, recolor: false)
        let total = Date().timeIntervalSince(t0)
        let (count, gap) = await ticker.stop()
        let line = "L225 логотип 4032×3024: обработка \(Int(total * 1000)) мс, отметок главного потока \(count), самая долгая пауза \(Int(gap * 1000)) мс"
        print(line); XCTContext.runActivity(named: line) { _ in }
        XCTAssertEqual([r.w, r.h], [400, 300], "4032×3024 → 2400×1800 → вписано в 1000×300")
        XCTAssertGreaterThan(count, 3, "Главный поток не работал во время обработки")
        XCTAssertLessThan(gap, 0.5, "Главный поток стоял \(Int(gap * 1000)) мс из \(Int(total * 1000))")
    }
    private func noiseJPEG(_ w: Int, _ h: Int) -> Data? {
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue), let raw = ctx.data else { return nil }
        arc4random_buf(raw, w * h * 4)
        guard let img = ctx.makeImage() else { return nil }
        let out = NSMutableData()
        guard let dst = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dst, img, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        return CGImageDestinationFinalize(dst) ? out as Data : nil
    }
}

/// Отметки главного потока раз в 10 мс: самая долгая пауза между ними — сколько главный поток был занят (как в StageJTests).
/// Первая отметка — в момент создания: пауза с самого начала обработки тоже учитывается
@MainActor private final class Ticker {
    private var stamps: [Date] = [Date()]
    private var task: Task<Void, Never>?
    init() { task = Task { @MainActor [weak self] in while let self, !Task.isCancelled { self.stamps.append(Date()); try? await Task.sleep(nanoseconds: 10_000_000) } } }
    func stop() async -> (count: Int, gap: TimeInterval) {
        stamps.append(Date())
        task?.cancel(); await task?.value
        return (stamps.count, zip(stamps, stamps.dropFirst()).map { $1.timeIntervalSince($0) }.max() ?? 0)
    }
}
