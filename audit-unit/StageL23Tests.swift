import XCTest
import SwiftUI
@testable import Albakov

/// Этап L.2.3: Palette и цвета раздела в Theme — на главном акторе. Цвета каждого раздела должны остаться прежними
/// (значения — как на сайте, 13.63): тест сторожит, что изоляция не изменила ни выбор цвета, ни сами цвета
@MainActor
final class PaletteTests: XCTestCase {
    func test01_SectionColorsUnchanged() {
        let saved = Palette.section
        defer { Palette.section = saved }   // раздел — общее состояние приложения-хоста тестов
        let black = ["#4a4d53", "#25272b", "#0e0f11"]
        let cases: [(section: String?, colors: [String], tint: String)] = [
            ("women", ["#a8384b", "#821f35", "#5f1424"], "#f8ecee"),
            ("kids", ["#7cbdf0", "#2f78c4", "#2f72b8"], "#e9f3fc"),
            ("men", black, "#eff0f2"),
            (nil, black, "#eff0f2"),
        ]
        for c in cases {
            Palette.section = c.section
            let name = c.section ?? "без раздела"
            XCTAssertEqual(Palette.colors, c.colors.map { Color(hex: $0) }, "Цвета раздела «\(name)» изменились")
            XCTAssertEqual(Theme.accentSoft, Color(hex: c.colors[0]), name)
            XCTAssertEqual(Theme.accent, Color(hex: c.colors[1]), name)
            XCTAssertEqual(Theme.dark, Color(hex: c.colors[1]), name)
            XCTAssertEqual(Theme.tint, Color(hex: c.tint), name)
        }
    }
}
