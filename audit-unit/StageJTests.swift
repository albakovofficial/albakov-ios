import XCTest
import UIKit
import ImageIO
@testable import Albakov

/// Этап J, DEF-1: замеры ImageKit.jpeg (фото товаров и картинок панели). Только измерения — поведение не меняется.
/// Строки «DEF1 …» попадают в журнал прогона. Проверяется лишь то, что верно и сейчас: результат — JPEG
/// с теми же пропорциями. Размеры, байты, время и память — для решения владельца (STAGE_J_CODE_QUALITY_REPORT.md)
final class ImageKitMeasureTests: XCTestCase {
    private enum Texture: String { case smooth = "гладкое", grain = "с зерном", noise = "шум" }

    /// Исходник: JPEG качества 0,9. Гладкое — градиент (сжимается сильнее любого снимка); с зерном — градиент
    /// и полупрозрачный шум (ближе к снимку камеры); шум — случайные пиксели (худший случай для размера файла)
    private func source(_ w: Int, _ h: Int, _ t: Texture) -> Data? {
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
        guard let img = ctx.makeImage() else { return nil }
        return UIImage(cgImage: img).jpegData(compressionQuality: 0.9)
    }
    private func bitmap(_ w: Int, _ h: Int) -> CGContext? {
        CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    }
    /// Пик памяти: опрос в фоне, пока замеряемое работает на главном потоке
    private final class Peak { let lock = NSLock(); var value: Int64 = 0; var running = true }

    private func pixels(_ d: Data) -> (w: Int, h: Int) {
        guard let s = CGImageSourceCreateWithData(d as CFData, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as? [CFString: Any] else { return (0, 0) }
        return ((p[kCGImagePropertyPixelWidth] as? Int) ?? 0, (p[kCGImagePropertyPixelHeight] as? Int) ?? 0)
    }

    /// Память процесса (phys_footprint), байты
    private func footprint() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        return kr == KERN_SUCCESS ? Int64(info.phys_footprint) : 0
    }

    @MainActor
    func test01_MeasureJpeg() {
        let scale = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.scale ?? 0
        let mb = { (b: Int64) in String(format: "%.1f", Double(b) / 1_048_576) }
        for (w, h) in [(4032, 3024), (8064, 6048)] {
            for t in [Texture.smooth, .grain, .noise] {
                guard let src = autoreleasepool(invoking: { source(w, h, t) }) else { XCTFail("Не получилось создать исходник \(w)×\(h)"); continue }
                // пик памяти — опрос раз в 2 мс в фоне, пока ImageKit.jpeg работает на главном потоке (как в панели)
                let peak = Peak(), base = footprint()
                let sampler = Thread { [self] in
                    while peak.lock.withLock({ peak.running }) { let f = footprint(); peak.lock.withLock { peak.value = max(peak.value, f) }; usleep(2000) }
                }
                sampler.start()
                let t0 = Date()
                let out = autoreleasepool { ImageKit.jpeg(src) }
                let ms = Int(Date().timeIntervalSince(t0) * 1000)
                peak.lock.withLock { peak.running = false }
                let grow = peak.lock.withLock { peak.value } - base
                let (ow, oh) = pixels(out)
                let line = "DEF1 \(w)×\(h) \(t.rawValue): исходник \(mb(Int64(src.count))) МБ → \(ow)×\(oh) px, \(mb(Int64(out.count))) МБ, "
                    + "в base64 \(mb(Int64(out.count) * 4 / 3)) МБ; \(ms) мс на главном потоке; пик памяти +\(mb(max(0, grow))) МБ; масштаб экрана \(scale)"
                print(line)
                XCTContext.runActivity(named: line) { _ in }
                XCTAssertGreaterThan(ow, 0, "Результат — не JPEG")
                XCTAssertEqual(Double(ow) / Double(max(oh, 1)), Double(w) / Double(h), accuracy: 0.01, "Пропорции изменились")
            }
        }
    }
}
