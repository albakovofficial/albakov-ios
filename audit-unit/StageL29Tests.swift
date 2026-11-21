import XCTest
@testable import Albakov

/// Этап L.2.9: шаблоны слайдов (SlideKit.tpl) — типизированная неизменяемая конфигурация вместо кортежей со словарём
/// [String: Any]. Эталон — прежние шаблоны дословно: порядок, названия, подсказки и поля слайда
@MainActor
final class SlideTemplateTests: XCTestCase {
    private let legacy: [(key: String, name: String, hint: String, slide: [String: Any])] = [
        ("sale", "Акция", "Связан с акцией: сам покажет скидку и срок и скроется, когда акция закончится",
         ["layout": "full", "eyebrow": "Акция", "title": "Название\n*акции*", "text": "Коротко о том, на что скидка.", "image": "img/slide-sale.jpg", "btn1": ["label": "Смотреть товары", "link": "#/sale"], "btn2": ["label": "Все акции", "link": "#/sale"]]),
        ("welcome", "Скидка на первый заказ", "С промокодом, который покупатель копирует одним нажатием",
         ["layout": "split", "eyebrow": "Для новых покупателей", "title": "−10%\nна *первый заказ*", "text": "Зарегистрируйтесь и введите промокод при оформлении.", "image": "img/slide-welcome.jpg", "code": "WELCOME10", "btn1": ["label": "Зарегистрироваться", "link": "#/account?tab=register"], "btn2": ["label": "", "link": ""]]),
        ("news", "Новинки", "Новая коллекция или поступление",
         ["layout": "split", "eyebrow": "Новое поступление", "title": "Новая\n*коллекция*", "text": "Пара строк о коллекции.", "image": "img/slide-new.jpg", "btn1": ["label": "Смотреть новинки", "link": "#/catalog?tag=new"], "btn2": ["label": "Весь каталог", "link": "#/catalog"]]),
        ("blank", "Пустой слайд", "Свой текст, фото и кнопки",
         ["layout": "split", "eyebrow": "", "title": "Заголовок", "text": "", "image": "", "btn1": ["label": "Подробнее", "link": "#/catalog"], "btn2": ["label": "", "link": ""]])
    ]

    /// Тот же список «Какой слайд добавить?» и те же поля каждого шаблона — ключ в ключ, значение в значение
    func test01_TemplatesUnchanged() {
        XCTAssertEqual(SlideKit.tpl.map { $0.key }, legacy.map { $0.key })
        for (t, old) in zip(SlideKit.tpl, legacy) {
            XCTAssertEqual(t.name, old.name, t.key); XCTAssertEqual(t.hint, old.hint, t.key)
            XCTAssertEqual(NSDictionary(dictionary: t.fields), NSDictionary(dictionary: old.slide), "Поля шаблона «\(t.key)» изменились")
        }
    }

    /// Новый слайд из шаблона (данные панели пусты: ни акций, ни промокодов) — полный набор полей слайда, поверх — шаблон;
    /// неизвестный шаблон — пустой слайд. Промокод «Скидки на первый заказ» по-прежнему берётся из действующих промокодов
    func test02_BlankSlideFromTemplate() {
        let admin = Admin.shared, was = admin.data
        defer { admin.data = was }
        admin.data = JSON(["promotions": [Any](), "promocodes": [Any]()])
        let all: Set<String> = ["id", "active", "layout", "eyebrow", "title", "text", "image", "badge", "code", "promotionId", "btn1", "btn2", "gender", "startsAt", "endsAt"]
        for old in legacy {
            let s = SlideKit.blank(old.key)
            XCTAssertEqual(Set(s.keys), all, old.key)
            XCTAssertTrue((s["id"] as? String)?.hasPrefix("sl") == true, old.key)
            XCTAssertEqual(s["active"] as? Bool, true, old.key)
            for (k, v) in old.slide where !(old.key == "welcome" && k == "code") {
                XCTAssertEqual(NSDictionary(dictionary: [k: s[k] ?? NSNull()]), NSDictionary(dictionary: [k: v]), "\(old.key).\(k)")
            }
        }
        XCTAssertEqual(SlideKit.blank("welcome")["code"] as? String, "", "Без действующего промокода код пустой — как раньше")
        admin.data = JSON(["promotions": [Any](), "promocodes": [["code": "SPRING", "active": true]]])
        XCTAssertEqual(SlideKit.blank("welcome")["code"] as? String, "SPRING")
        XCTAssertEqual(NSDictionary(dictionary: SlideKit.blank("нет такого").filter { $0.key != "id" }),
                       NSDictionary(dictionary: SlideKit.blank("blank").filter { $0.key != "id" }))
    }
}
