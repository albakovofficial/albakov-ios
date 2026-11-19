import XCTest
@testable import Albakov

/// Этап K.1, K-M1: «Добавить образ в корзину» — всё или ничего. Раньше вещи до первой вещи без размера уже лежали
/// в корзине, а повторное нажатие клало их второй раз
@MainActor
final class LookAddTests: XCTestCase {
    private var shop: Shop { Shop.shared }
    /// Корзина хоста на время теста пустая и потом возвращается (гость: на сервер ничего не уходит)
    private func clean(_ body: () -> Void) { let was = shop.cart; shop.cart = []; defer { shop.cart = was }; body() }

    private func item(_ id: String, sizes: [String]) -> Product {
        Product(JSON(["id": id, "name": "Вещь \(id)", "price": 1000,
                      "colors": [["id": "c-\(id)", "name": "Чёрный", "sizes": sizes.map { ["size": $0, "stock": 3] }]]]))
    }
    /// Эта вещь (размер — из карточки) и три вещи образа: p1 и p3 с выбором размера, у p2 в наличии один размер — он берётся сам
    private lazy var all = [item("p0", sizes: ["M", "L"]), item("p1", sizes: ["S", "M"]), item("p2", sizes: ["XL"]), item("p3", sizes: ["M", "L"])]
    private func add(main: String? = "M", sizes: [String: String], off: Set<String> = []) -> (missing: Product?, added: Int) {
        LookSection.add(all, off: off, sizes: sizes, mainColor: all[0].colors[0], mainSize: main, to: shop)
    }
    private var cart: [String] { shop.cart.map { "\($0.productId) \($0.colorId) \($0.size) ×\($0.qty)" } }
    private let full = ["p0 c-p0 M ×1", "p1 c-p1 S ×1", "p2 c-p2 XL ×1", "p3 c-p3 L ×1"]

    func test01_AllSizesChosen() {
        clean {
            let r = add(sizes: ["p1": "S", "p3": "L"])
            XCTAssertNil(r.missing); XCTAssertEqual(r.added, 4)
            XCTAssertEqual(cart, full)
        }
    }

    func test02_FirstWithoutSize() {
        clean {
            let r = add(main: nil, sizes: ["p1": "S", "p3": "L"])
            XCTAssertEqual(r.missing?.id, "p0"); XCTAssertEqual(r.added, 0)
            XCTAssertEqual(cart, [], "Без размера этой вещи в корзину не должно попасть ничего")
        }
    }

    func test03_LastWithoutSize() {
        clean {
            let r = add(sizes: ["p1": "S"])
            XCTAssertEqual(r.missing?.id, "p3"); XCTAssertEqual(r.added, 0)
            XCTAssertEqual(cart, [], "Вещи до последней попали в корзину частично")
        }
    }

    func test04_MiddleWithoutSize() {
        clean {
            let r = add(sizes: ["p3": "L"])
            XCTAssertEqual(r.missing?.id, "p1"); XCTAssertEqual(r.added, 0)
            XCTAssertEqual(cart, [], "Эта вещь попала в корзину раньше вещи без размера")
        }
    }

    /// Нажали без размера, ещё раз без размера, выбрали размер, нажали — в корзине каждая вещь по одной
    func test05_RepeatAfterFailure() {
        clean {
            XCTAssertEqual(add(sizes: ["p1": "S"]).missing?.id, "p3")
            XCTAssertEqual(add(sizes: ["p1": "S"]).missing?.id, "p3")
            XCTAssertEqual(cart, [])
            XCTAssertNil(add(sizes: ["p1": "S", "p3": "L"]).missing)
            XCTAssertEqual(cart, full, "После неудачных нажатий вещи задвоились")
        }
    }

    /// Убранная из образа вещь не мешает: размер у неё не нужен, в корзину она не идёт
    func test06_RemovedItemNeedsNoSize() {
        clean {
            let r = add(sizes: ["p1": "S"], off: ["p3"])
            XCTAssertNil(r.missing); XCTAssertEqual(r.added, 3)
            XCTAssertEqual(cart, ["p0 c-p0 M ×1", "p1 c-p1 S ×1", "p2 c-p2 XL ×1"])
        }
    }
}
