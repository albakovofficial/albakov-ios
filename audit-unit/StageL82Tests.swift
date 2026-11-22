import XCTest
@testable import Albakov

/// Этап L.8.2 (L8-01): проверка акции в панели перед сохранением — настоящая validate из AdminSections.promotions,
/// та, что вызывает форма (CollectionEdit.save). Размер скидки задаётся через Doc.number, как его вводит сотрудник
/// (целое хранится целым, дробное — дробным, «nan» и «inf» — нечислом). Цены — данные панели (Admin.shared.data):
/// фиксированная сумма не меньше цены хотя бы одного товара акции дала бы цену 0 ₽, такую акцию сохранить нельзя.
/// Данные панели хоста подменяются перед каждой проверкой и возвращаются после теста
@MainActor
final class PromotionValidationTests: XCTestCase {
    private var saved = JSON(nil)
    override func setUp() async throws { saved = Admin.shared.data }
    override func tearDown() async throws { Admin.shared.data = saved }

    /// Каталог: две вещи в категории c1 (3990 и 1500 ₽), одна в c2 (990 ₽)
    private let catalog: [[String: Any]] = [
        ["id": "p1", "name": "Худи", "categoryId": "c1", "price": 3990],
        ["id": "p2", "name": "Футболка", "categoryId": "c1", "price": 1500],
        ["id": "p3", "name": "Носки", "categoryId": "c2", "price": 990],
    ]

    /// Ответ проверки формы: "" — можно сохранить, иначе текст ошибки
    private func check(_ type: String, _ value: String, scope: String = "products", ids: [String] = ["p1"],
                       products: [[String: Any]]? = nil) -> String {
        Admin.shared.data = JSON(["products": products ?? catalog])
        let doc = Doc(AdminSections.promotions.blank())
        doc.v["title"] = "Акция"; doc.v["type"] = type; doc.v["scope"] = scope
        doc.v[scope == "categories" ? "categoryIds" : "productIds"] = ids
        doc.number("value").wrappedValue = value
        guard let validate = AdminSections.promotions.validate else { XCTFail("У акций нет проверки"); return "" }
        return validate(doc.v, [])
    }
    private func allowed(_ r: String, _ why: String) { XCTAssertEqual(r, "", "Отклонено, а должно сохраняться: \(why)") }
    private func rejected(_ r: String, _ why: String) { XCTAssertFalse(r.isEmpty, "Сохранилось, а должно быть отклонено: \(why)") }

    // MARK: Фиксированная сумма

    func test01_FixedBelowPriceAllowed() {
        allowed(check("fixed", "3989"), "3989 ₽ при цене 3990 ₽")
        allowed(check("fixed", "500"), "500 ₽ при цене 3990 ₽")
        allowed(check("fixed", "3988,5"), "дробная сумма: цена со скидкой 1,5 ₽")
        allowed(check("fixed", "3989", products: [["id": "p1", "name": "Худи", "price": "3990"]]), "цена строкой «3990», как на сервере Number()")
    }
    func test02_FixedEqualToPriceRejected() {
        let r = check("fixed", "3990")
        rejected(r, "3990 ₽ при цене 3990 ₽ — цена 0 ₽")
        XCTAssertTrue(r.contains("Худи"), "В ошибке нет товара, из-за которого нельзя сохранить: \(r)")
    }
    func test03_FixedAbovePriceRejected() {
        rejected(check("fixed", "5000"), "5000 ₽ при цене 3990 ₽")
        rejected(check("fixed", "3990,01"), "чуть больше цены")
        // дробный остаток меньше рубля сайт показывает как 0 ₽ (3990 − 3989,6 = 0,4)
        rejected(check("fixed", "3989,5"), "цена со скидкой 0,5 ₽")
        rejected(check("fixed", "3989,6"), "цена со скидкой 0,4 ₽")
    }
    func test04_FixedNegativeRejected() {
        rejected(check("fixed", "-500"), "−500 ₽")
    }
    func test05_FixedZeroRejected() {
        rejected(check("fixed", "0"), "0 ₽")
        rejected(check("fixed", ""), "пустое поле")
    }
    func test06_FixedCheckedAgainstEveryProductInScope() {
        // категория c1: 3990 и 1500 — сумма должна быть меньше 1500
        allowed(check("fixed", "1499", scope: "categories", ids: ["c1"]), "1499 ₽ — меньше обеих цен категории")
        let r = check("fixed", "1500", scope: "categories", ids: ["c1"])
        rejected(r, "1500 ₽ — равна цене футболки")
        XCTAssertTrue(r.contains("Футболка"), "В ошибке не тот товар: \(r)")
        rejected(check("fixed", "2000", scope: "categories", ids: ["c1"]), "меньше цены худи, но больше цены футболки")
        // весь каталог: самый дешёвый — носки 990 ₽
        rejected(check("fixed", "1000", scope: "all"), "весь каталог: больше цены носков")
        allowed(check("fixed", "989", scope: "all"), "весь каталог: меньше всех цен")
        // выбранные товары: только они, остальные не мешают
        allowed(check("fixed", "1499", ids: ["p1", "p2"]), "выбраны худи и футболка, носки не в акции")
        rejected(check("fixed", "1000", ids: ["p1", "p3"]), "выбраны худи и носки")
        // товары другой категории не мешают: носки (990 ₽) в c2, акция — на c1
        allowed(check("fixed", "1000", scope: "categories", ids: ["c1"]), "носки в другой категории")
    }
    func test07_FixedWithMissingOrBadPriceRejected() {
        var noPrice = catalog; noPrice.append(["id": "p4", "name": "Кепка", "categoryId": "c1"])
        let r = check("fixed", "100", scope: "categories", ids: ["c1"], products: noPrice)
        rejected(r, "у товара акции нет цены")
        XCTAssertTrue(r.contains("Кепка"), "В ошибке не тот товар: \(r)")
        var badPrice = catalog; badPrice.append(["id": "p4", "name": "Кепка", "categoryId": "c1", "price": "бесплатно"])
        rejected(check("fixed", "100", scope: "categories", ids: ["c1"], products: badPrice), "цена — не число")
        var zeroPrice = catalog; zeroPrice.append(["id": "p4", "name": "Кепка", "categoryId": "c1", "price": 0])
        rejected(check("fixed", "100", scope: "categories", ids: ["c1"], products: zeroPrice), "цена 0 ₽")
        var minusPrice = catalog; minusPrice.append(["id": "p4", "name": "Кепка", "categoryId": "c1", "price": -100])
        rejected(check("fixed", "100", scope: "categories", ids: ["c1"], products: minusPrice), "отрицательная цена")
        // товар без цены вне акции проверке не мешает
        allowed(check("fixed", "100", scope: "categories", ids: ["c2"], products: noPrice), "товар без цены в другой категории")
        // данных панели нет (не загрузились) — проверить нельзя
        Admin.shared.data = JSON(nil)
        let doc = Doc(AdminSections.promotions.blank())
        doc.v["title"] = "Акция"; doc.v["type"] = "fixed"; doc.v["scope"] = "all"; doc.number("value").wrappedValue = "100"
        rejected(AdminSections.promotions.validate?(doc.v, []) ?? "", "данные панели не загружены")
        // товары пришли не списком — тоже нельзя
        Admin.shared.data = JSON(["products": ["p1": catalog[0]]])
        rejected(AdminSections.promotions.validate?(doc.v, []) ?? "", "товары не списком")
    }
    func test08_NotANumberRejected() {
        rejected(check("fixed", "nan"), "фиксированная: не число")
        rejected(check("fixed", "inf"), "фиксированная: бесконечность")
        rejected(check("percent", "nan"), "процент: не число")
        rejected(check("percent", "-inf"), "процент: минус бесконечность")
    }

    // MARK: Процент

    func test09_Percent99Allowed() {
        allowed(check("percent", "99"), "99%")
        allowed(check("percent", "10", scope: "all"), "10% на весь каталог — обычная акция")
        allowed(check("percent", "99,5"), "99,5%")
    }
    func test10_Percent100Rejected() {
        rejected(check("percent", "100"), "100%")
    }
    func test11_PercentAbove100Rejected() {
        rejected(check("percent", "150"), "150%")
        // сервер считает процентом всё, что не "fixed"
        rejected(check("", "150"), "тип не указан — процент, 150%")
    }
    func test12_PercentNegativeRejected() {
        rejected(check("percent", "-10"), "−10%")
    }
    func test13_PercentZeroRejected() {
        rejected(check("percent", "0"), "0%")
    }
    /// Процент не зависит от цен: проверяется и без данных панели, как раньше
    func test14_PercentDoesNotNeedPrices() {
        allowed(check("percent", "20", products: [["id": "p1", "name": "Худи"]]), "товар без цены, скидка в процентах")
        Admin.shared.data = JSON(nil)
        let doc = Doc(AdminSections.promotions.blank())
        doc.v["title"] = "Акция"
        allowed(AdminSections.promotions.validate?(doc.v, []) ?? "?", "данные панели не загружены, 10% по умолчанию")
    }
}
