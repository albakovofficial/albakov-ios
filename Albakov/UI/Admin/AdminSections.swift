import SwiftUI

// Разделы панели как на сайте (SECTIONS в public/js/admin.js): ключ раздела → экран.
// Права: SECTION_PERMS — раздел виден, если у роли есть хотя бы одно из прав.
@MainActor
enum AdminSections {
    static let list: [(key: String, title: String, icon: String)] = [
        ("overview", "Обзор", "chart.bar"), ("orders", "Заказы", "shippingbox"), ("support", "Поддержка", "bubble.left.and.text.bubble.right"),
        ("products", "Товары", "tshirt"), ("categories", "Категории", "square.grid.2x2"),
        ("promotions", "Акции", "tag"), ("promocodes", "Промокоды", "ticket"), ("bonus", "Бонусы", "sparkles"),
        ("exchange", "Обмен и возвраты", "arrow.left.arrow.right"), ("customers", "Покупатели", "person.2"), ("mail", "Почта", "envelope"),
        ("analytics", "Аналитика", "chart.line.uptrend.xyaxis"), ("finance", "Финансы", "rublesign.circle"), ("gifts", "Подарочные сертификаты", "gift"),
        ("sections", "Разделы", "person.2.wave.2"), ("brand", "Логотип и название", "a.square"), ("slider", "Слайдер на главной", "rectangle.on.rectangle"),
        ("home", "Главная страница", "house"), ("pages", "Страницы", "doc.text"), ("menu", "Меню, контакты, соцсети", "line.3.horizontal"),
        ("payment", "Оплата и доставка", "creditcard"), ("push", "Push-уведомления", "bell.badge"), ("staff", "Сотрудники", "person.badge.key"),
        ("audit", "Журнал действий", "list.bullet.rectangle"), ("settings", "Настройки", "gearshape")
    ]
    /// Группы разделов на рабочем столе: продажи, каталог, маркетинг, цифры, витрина, управление (как GROUPS на сайте)
    static let groups: [[String]] = [["orders", "support", "exchange", "customers"], ["products", "categories", "sections"],
        ["promotions", "promocodes", "bonus", "gifts", "mail", "push"], ["overview", "analytics", "finance"],
        ["home", "slider", "brand", "menu", "pages"], ["payment", "staff", "audit", "settings"]]
    static func group(_ k: String) -> Int { groups.firstIndex { $0.contains(k) } ?? 5 }
    /// Короткое название для значка
    static func short(_ k: String, _ title: String) -> String {
        ["exchange": "Обмен и возврат", "gifts": "Сертификаты", "brand": "Логотип", "slider": "Слайдер", "home": "Главная", "menu": "Меню и контакты", "push": "Push", "audit": "Журнал"][k] ?? title
    }
    static let perms: [String: [String]] = [
        "overview": [], "orders": ["orders"], "support": ["orders"], "exchange": ["orders"], "customers": ["orders", "marketing"], "gifts": ["orders", "marketing"],
        "products": ["content"], "categories": ["content"], "promotions": ["content", "marketing"], "promocodes": ["content", "marketing"],
        "sections": ["content"], "brand": ["content"], "slider": ["content"], "home": ["content"], "pages": ["content"], "menu": ["content"],
        "bonus": ["marketing"], "mail": ["mail"], "analytics": ["finance", "marketing"], "finance": ["finance"],
        "payment": ["payment"], "push": [], "staff": ["staff"], "audit": ["staff"], "settings": ["settings"]
    ]
    @MainActor static func can(_ key: String) -> Bool {
        guard let need = perms[key] else { return false }
        return need.isEmpty || need.contains { Admin.shared.can($0) }
    }

    nonisolated static let collectionKeys: Set<String> = ["categories", "promotions", "promocodes", "pages", "products"]
    static var collections: [String: CollectionCfg] {
        ["categories": categories, "promotions": promotions, "promocodes": promocodes, "pages": pages, "products": AdminProduct.cfg]
    }

    @MainActor @ViewBuilder static func view(_ k: String) -> some View {
        if let c = collections[k] { CollectionList(cfg: c) }
        else {
            switch k {
            case "overview": AdminOverview()
            case "orders": AdminOrdersView()
            case "support": AdminSupportView()
            case "customers": AdminCustomersView()
            case "push": AdminPushView()
            case "audit": AdminAuditView()
            case "bonus": bonusForm
            case "home": homeForm
            case "sections": sectionsForm
            case "menu": menuForm
            case "settings": generalForm
            case "exchange": AdminExchange()
            case "gifts": AdminGifts()
            case "mail": AdminMail()
            case "analytics": AdminAnalytics()
            case "finance": AdminFinance()
            case "slider": AdminSlider()
            case "brand": AdminBrand()
            case "payment": AdminPayment()
            case "staff": AdminStaff()
            case "productsBulk": ProductsBulkView()
            default: EmptyState(icon: "questionmark", title: "Раздел не найден", text: "")
            }
        }
    }
    @MainActor @ViewBuilder static func item(_ k: String, _ id: String) -> some View {
        if let c = collections[k] { CollectionEdit(cfg: c, id: id) } else { EmptyState(icon: "questionmark", title: "Не найдено", text: "") }
    }

    // MARK: Общие варианты
    @MainActor static var catOpts: [(String, String)] { Admin.shared.data["categories"].array.map { ($0["id"].str, $0["name"].str) } }
    @MainActor static var prodOpts: [(String, String)] { Admin.shared.data["products"].array.map { ($0["id"].str, $0["name"].str) } }
    static let genderOpts = [("", "Определять по товарам"), ("women", "Женщинам"), ("men", "Мужчинам"), ("kids", "Детям"), ("unisex", "Женщинам и мужчинам")]
    static func today() -> String { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f.string(from: Date()) }

    // MARK: - Категории
    static var categories: CollectionCfg {
        CollectionCfg(key: "categories", prefix: "c", title: "Категории", newTitle: "Новая категория", addLabel: "Добавить категорию",
            sub: "Категории показываются на главной, в меню и фильтрах каталога в порядке номера.",
            itemTitle: { $0["name"].str },
            itemSub: { c in
                let n = Admin.shared.data["products"].array.filter { $0["categoryId"].str == c["id"].str }.count
                return ["women": "Женщинам", "men": "Мужчинам", "kids": "Детям", "unisex": "Женщинам и мужчинам"][c["gender"].str, default: "По товарам"] + " · порядок \(c["order"].int ?? 0) · товаров \(n)"
            },
            thumb: { c in AnyView(Group { if c["image"].str.isEmpty { ArtView(kind: c["art"]["kind"].string ?? "tee", tone: c["art"]["tone"].string ?? "#3b3b3f") } else { RemoteImage(path: c["image"].str) } }) },
            sort: { ($0["order"].int ?? 0) < ($1["order"].int ?? 0) },
            blank: { ["name": "", "slug": "", "image": "", "art": ["kind": "tee", "tone": "#3b3b3f"], "order": Admin.shared.data["categories"].array.count + 1] },
            fields: { [FDef(k: "name", label: "Название"),
                       FDef(k: "gender", label: "Раздел", kind: .select(genderOpts), hint: "В каком разделе показывать категорию в меню, подвале и каталоге. «По товарам» — по тому, для кого товары внутри"),
                       FDef(k: "order", label: "Порядок", kind: .number), FDef(k: "image", label: "Обложка", kind: .image, hint: "Вертикальное фото 3:4"),
                       FDef(k: "slug", label: "Адрес", hint: "Латиницей, заполнится сам")] },
            read: { c in c["slug"] = translit((c["slug"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (c["name"] as? String ?? "")) },
            validate: { c, all in
                if (c["name"] as? String ?? "").isEmpty { return "Укажите название" }
                if all.contains(where: { $0["id"].str != (c["id"] as? String ?? "") && $0["slug"].str == (c["slug"] as? String ?? "") }) { return "Такой адрес уже занят" }
                return ""
            },
            canDelete: { c in
                let n = Admin.shared.data["products"].array.filter { $0["categoryId"].str == c["id"].str }.count
                return n > 0 ? "В категории \(n) тов. — удалить можно пустую категорию. Сначала перенесите товары в другую." : nil
            })
    }

    // MARK: - Акции
    @MainActor static var promotions: CollectionCfg {
        CollectionCfg(key: "promotions", prefix: "a", title: "Акции", newTitle: "Новая акция", addLabel: "Создать акцию",
            sub: "Акция автоматически снижает цену на выбранные товары в указанные даты. Если на товар действует несколько акций, применяется самая выгодная.",
            itemTitle: { $0["title"].str },
            itemSub: { a in
                let v = a["type"].str == "percent" ? "\(a["value"].int ?? 0)%" : Fmt.rub(a["value"].int ?? 0)
                let scope = a["scope"].str == "all" ? "Весь каталог" : a["scope"].str == "categories" ? "\(a["categoryIds"].array.count) кат." : "\(a["productIds"].array.count) тов."
                let live = Promotion(a).inWindow(Date())
                return "\(v) · \(scope) · \(a["startsAt"].string.flatMap { $0.isEmpty ? nil : $0 } ?? "…") — \(a["endsAt"].string.flatMap { $0.isEmpty ? nil : $0 } ?? "…") · " + (live ? "действует" : "не действует")
            },
            blank: { ["title": "", "description": "", "type": "percent", "value": 10, "scope": "all", "categoryIds": [String](), "productIds": [String](), "startsAt": today(), "endsAt": "", "active": true] },
            fields: { [FDef(k: "title", label: "Название"), FDef(k: "description", label: "Описание для покупателей", kind: .area(2)),
                       FDef(k: "type", label: "Тип скидки", kind: .select([("percent", "Процент от цены"), ("fixed", "Фиксированная сумма, ₽")])),
                       FDef(k: "value", label: "Размер скидки", kind: .number),
                       FDef(k: "scope", label: "Применяется к", kind: .select([("all", "Всему каталогу"), ("categories", "Выбранным категориям"), ("products", "Выбранным товарам")])),
                       FDef(k: "categoryIds", label: "Категории", kind: .multi(catOpts), hint: "Только для «Выбранным категориям»"),
                       FDef(k: "productIds", label: "Товары", kind: .multi(prodOpts), hint: "Только для «Выбранным товарам»"),
                       FDef(k: "startsAt", label: "Начало", kind: .date), FDef(k: "endsAt", label: "Окончание", kind: .date, hint: "Пусто — без срока"),
                       FDef(k: "active", label: "Акция включена", kind: .bool)] },
            validate: { a, _ in
                let v = (a["value"] as? NSNumber)?.doubleValue ?? 0
                if (a["title"] as? String ?? "").isEmpty { return "Укажите название" }
                if v == 0 { return "Укажите размер скидки" }
                if a["type"] as? String == "percent" && v >= 100 { return "Процент должен быть меньше 100" }
                return ""
            })
    }

    // MARK: - Промокоды
    static var promocodes: CollectionCfg {
        CollectionCfg(key: "promocodes", prefix: "pc", title: "Промокоды", newTitle: "Новый промокод", addLabel: "Создать промокод",
            sub: "Покупатель вводит промокод при оформлении заказа. Скидка по промокоду считается от суммы после акций.",
            itemTitle: { $0["code"].str },
            itemSub: { c in
                let v = c["type"].str == "percent" ? "\(c["value"].int ?? 0)%" : c["type"].str == "fixed" ? Fmt.rub(c["value"].int ?? 0) : "Бесплатная доставка"
                return [v, (c["minTotal"].int ?? 0) > 0 ? "от " + Fmt.rub(c["minTotal"].int ?? 0) : "", "использован \(c["used"].int ?? 0)" + ((c["limit"].int ?? 0) > 0 ? " / \(c["limit"].int ?? 0)" : ""),
                        c["endsAt"].str.isEmpty ? "без срока" : "до " + c["endsAt"].str, c["active"].bool ? "активен" : "выключен"].filter { !$0.isEmpty }.joined(separator: " · ")
            },
            blank: { ["code": "", "type": "percent", "value": 10, "minTotal": 0, "startsAt": "", "endsAt": "", "limit": 0, "used": 0, "onePerCustomer": false, "onlyRegistered": false, "firstOrderOnly": false, "excludeSale": false, "active": true, "note": ""] },
            fields: { [FDef(k: "code", label: "Код", hint: "Латиница и цифры, регистр не важен"), FDef(k: "note", label: "Заметка (видно только вам)"),
                       FDef(k: "type", label: "Что даёт", kind: .select([("percent", "Скидку в процентах"), ("fixed", "Скидку в рублях"), ("shipping", "Бесплатную доставку")])),
                       FDef(k: "value", label: "Размер скидки", kind: .number, hint: "Для бесплатной доставки не нужен"),
                       FDef(k: "minTotal", label: "Минимальная сумма заказа, ₽", kind: .number),
                       FDef(k: "limit", label: "Лимит использований", kind: .number, hint: "0 — без ограничений"),
                       FDef(k: "startsAt", label: "Начало", kind: .date), FDef(k: "endsAt", label: "Окончание", kind: .date),
                       FDef(k: "used", label: "Уже использован, раз", kind: .number),
                       FDef(k: "onePerCustomer", label: "Один раз на покупателя", kind: .bool),
                       FDef(k: "onlyRegistered", label: "Только для зарегистрированных покупателей", kind: .bool),
                       FDef(k: "firstOrderOnly", label: "Только на первый заказ покупателя", kind: .bool, hint: "Нужен вход в личный кабинет. Если у покупателя уже есть заказы, при оформлении он увидит плашку с объяснением."),
                       FDef(k: "excludeSale", label: "Не распространяется на товары со скидкой", kind: .bool),
                       FDef(k: "active", label: "Промокод активен", kind: .bool)] },
            read: { c in c["code"] = (c["code"] as? String ?? "").uppercased().replacingOccurrences(of: " ", with: "") },
            validate: { c, all in
                let code = c["code"] as? String ?? "", v = (c["value"] as? NSNumber)?.doubleValue ?? 0
                if code.range(of: #"^[A-Z0-9А-ЯЁ_-]{3,30}$"#, options: [.regularExpression, .caseInsensitive]) == nil { return "Код — от 3 до 30 символов: буквы, цифры, дефис" }
                if all.contains(where: { $0["id"].str != (c["id"] as? String ?? "") && $0["code"].str.uppercased() == code }) { return "Такой промокод уже есть" }
                if c["type"] as? String != "shipping" && v == 0 { return "Укажите размер скидки" }
                if c["type"] as? String == "percent" && v > 100 { return "Процент не может быть больше 100" }
                return ""
            },
            duplicate: { c in var x = c; x["id"] = uid("pc"); x["code"] = (c["code"] as? String ?? "") + String(Int.random(in: 10...99)); x["used"] = 0; return x })
    }

    // MARK: - Страницы
    static var pages: CollectionCfg {
        CollectionCfg(key: "pages", prefix: "pg", title: "Страницы", newTitle: "Новая страница", addLabel: "Создать страницу",
            sub: "Информационные страницы: доставка, возврат, о бренде, оферта. Ссылки на них появляются в подвале сайта и приложения.",
            itemTitle: { $0["title"].str },
            itemSub: { p in "/page/" + p["slug"].str + " · " + (p["inFooter"].bool ? (["help": "Покупателям", "brand": "Покупателям", "legal": "Нижняя строка"][p["group"].str] ?? "—") : "скрыта") },
            blank: { ["title": "", "slug": "", "body": "", "inFooter": true, "group": "help"] },
            fields: { [FDef(k: "title", label: "Заголовок"), FDef(k: "slug", label: "Адрес", hint: "Латиницей, заполнится сам"),
                       FDef(k: "group", label: "Где показать ссылку", kind: .select([("help", "Подвал: «Покупателям»"), ("brand", "Подвал: «Покупателям», в конце"), ("legal", "Нижняя строка подвала (юридическое)")])),
                       FDef(k: "inFooter", label: "Показывать ссылку в подвале", kind: .bool),
                       FDef(k: "body", label: "Текст", kind: .area(14), hint: "Пустая строка — новый абзац. ## Заголовок. - пункт списка. **жирный**. [текст ссылки](https://адрес). Подставляются сами: {продавец}, {адрес}, {почта}, {телефон}")] },
            read: { p in p["slug"] = translit((p["slug"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (p["title"] as? String ?? "")) },
            validate: { p, all in
                if (p["title"] as? String ?? "").isEmpty { return "Укажите заголовок" }
                if all.contains(where: { $0["id"].str != (p["id"] as? String ?? "") && $0["slug"].str == (p["slug"] as? String ?? "") }) { return "Такой адрес уже занят" }
                return ""
            })
    }

    // MARK: - Настройки на основе settings

    static var bonusForm: some View {
        SettingsForm(title: "Бонусы", sub: "1 бонус = 1 ₽. Бонусы получают зарегистрированные покупатели. Под каждым товаром видно, сколько бонусов придёт за покупку, а при оформлении бонусами можно оплатить весь заказ.",
            defs: [FDef(k: "enabled", label: "Бонусная программа включена", kind: .bool, hint: "Если выключить, бонусы перестанут начисляться и списываться, но останутся на счетах покупателей"),
                   FDef(k: "percent", label: "Сколько процентов от покупки начислять", kind: .number, hint: "Например, 5 — за товар за 1 500 ₽ придёт 75 бонусов"),
                   FDef(k: "onlineExtra", label: "Дополнительно за онлайн-оплату, %", kind: .number, hint: "Сверху к основному проценту, если покупатель платит онлайн. 0 — выключено"),
                   FDef(k: "creditOn", label: "Когда начислять", kind: .select([("paid", "После оплаты заказа"), ("done", "Когда заказ выполнен (получен покупателем)")]), hint: "При отмене заказа или возврате денег начисленные бонусы забираются, а потраченные возвращаются")],
            getObj: { s in (s["bonus"] as? [String: Any]) ?? ["enabled": true, "percent": 5, "creditOn": "paid"] },
            apply: { s, o in
                let p = (o["percent"] as? NSNumber)?.doubleValue ?? 0, e = (o["onlineExtra"] as? NSNumber)?.doubleValue ?? 0
                if !(p >= 0 && p <= 100) { return "Процент должен быть от 0 до 100" }
                if !(e >= 0 && e <= 50) { return "Бонус за онлайн-оплату — от 0 до 50%" }
                s["bonus"] = o; return nil
            }, extra: AnyView(BonusStats()))
    }

    static var homeForm: some View {
        let icons: [(String, String)] = [("auto", "Иконка: по тексту"), ("delivery", "Доставка — грузовик"), ("quality", "Качество — медаль"), ("fabric", "Ткани — стопка тканей"), ("fitting", "Примерка — футболка"), ("return", "Возврат — коробка"), ("payment", "Оплата — карты"), ("gift", "Подарок / бонусы"), ("cash", "Наличные"), ("pin", "Метка на карте"), ("style", "Стиль — вешалка"), ("gem", "Индивидуальность — камень"), ("spool", "Производство — катушка"), ("mail", "Почта — конверт"), ("chat", "Чат — облачка"), ("phone", "Телефон"), ("none", "Без иконки")]
        return SettingsForm(title: "Главная страница", sub: "Тексты, картинки и блоки главной. Выделить слово в заголовке: *слово*. Перенос строки — Enter.",
            defs: [.section("Первый экран — когда слайдер выключен"),
                   FDef(k: "heroEyebrow", label: "Надзаголовок"), FDef(k: "heroCta", label: "Текст кнопки"), FDef(k: "heroTitle", label: "Заголовок", kind: .area(2)),
                   FDef(k: "heroText", label: "Подзаголовок", kind: .area(2)), FDef(k: "heroLink", label: "Ссылка кнопки", hint: "Например, #/catalog или #/catalog?cat=outerwear"),
                   FDef(k: "heroImage", label: "Фото первого экрана", kind: .image),
                   .section("Блоки"),
                   FDef(k: "showCategories", label: "Показывать категории", kind: .bool), FDef(k: "showNew", label: "Показывать новинки", kind: .bool),
                   FDef(k: "showHits", label: "Показывать хиты продаж", kind: .bool, hint: "Товары с плашкой «Хит продаж» и самые продаваемые. Блок скрыт, пока хитов нет"),
                   FDef(k: "showSale", label: "Показывать текущую акцию", kind: .bool), FDef(k: "showEditorial", label: "Показывать блок о бренде", kind: .bool),
                   FDef(k: "showBenefits", label: "Показывать преимущества", kind: .bool), FDef(k: "showBonus", label: "Показывать блок «Бонусная программа»", kind: .bool),
                   .section("Хиты продаж"),
                   FDef(k: "hitsAuto", label: "Добавлять самые продаваемые автоматически", kind: .bool, hint: "По заказам за последние 90 дней — без отменённых и неоплаченных онлайн"),
                   .section("Блок «Бонусная программа»"),
                   FDef(k: "bonusEyebrow", label: "Надзаголовок"), FDef(k: "bonusTitle", label: "Заголовок", kind: .area(2), hint: "{n} — процент из раздела «Бонусы», *слово* — курсивом"), FDef(k: "bonusText", label: "Текст", kind: .area(3)),
                   .section("Блок «Преимущества»"),
                   FDef(k: "benefitsEyebrow", label: "Надзаголовок"), FDef(k: "benefitsTitle", label: "Заголовок", hint: "Пусто — только карточки"),
                   FDef(k: "benefits", label: "Преимущества", kind: .rows([FDef(k: "title", label: "Заголовок"), FDef(k: "text", label: "Описание", kind: .area(2)), FDef(k: "icon", label: "Иконка", kind: .select(icons)), FDef(k: "link", label: "Ссылка (необязательно)"), FDef(k: "linkText", label: "Текст ссылки")])),
                   .section("Блок о бренде"),
                   FDef(k: "editorialEyebrow", label: "Надзаголовок"), FDef(k: "editorialTitle", label: "Заголовок"), FDef(k: "editorialText", label: "Текст", kind: .area(4)), FDef(k: "editorialImage", label: "Фото", kind: .image)],
            getObj: { s in (s["home"] as? [String: Any]) ?? [:] },
            apply: { s, o in
                var h = (s["home"] as? [String: Any]) ?? [:]
                for (k, v) in o { h[k] = v }
                s["home"] = h; return nil
            })
    }

    /// Разделы «Женщинам», «Мужчинам», «Детям» (13.63): открыт ли раздел и страница «скоро появится» с фото
    static var sectionsForm: some View {
        var defs: [FDef] = []
        for x in Sections.all {
            defs.append(.section("Раздел «\(x.name)»"))
            defs.append(FDef(k: "open_" + x.key, label: "Раздел открыт", kind: .bool, hint: "Если выключить, его товары пропадут из каталога, а покупатель увидит страницу «скоро появится»"))
            defs.append(FDef(k: "title_" + x.key, label: "Заголовок страницы «скоро»", kind: .area(2), hint: "Enter — перенос строки, *слово* — курсивом"))
            defs.append(FDef(k: "text_" + x.key, label: "Текст страницы «скоро»", kind: .area(2)))
            defs.append(FDef(k: "image_" + x.key, label: "Фото страницы «скоро»", kind: .image, hint: "Вертикальное фото"))
        }
        return SettingsForm(title: "Разделы", sub: "Здесь можно закрыть раздел, пока в нём нет одежды. У каждого товара раздел задаётся полем «Для кого».",
            defs: defs,
            getObj: { s in
                var o: [String: Any] = [:]; let gs = JSON(s["genders"])
                for x in Sections.all {
                    let c = gs[x.key]
                    o["open_" + x.key] = !(c["open"].exists && !c["open"].bool); o["title_" + x.key] = c["title"].str; o["text_" + x.key] = c["text"].str; o["image_" + x.key] = c["image"].str
                }
                return o
            },
            apply: { s, o in
                if !Sections.all.contains(where: { o["open_" + $0.key] as? Bool ?? true }) { return "Оставьте открытым хотя бы один раздел" }
                var gs: [String: Any] = [:]
                for x in Sections.all { gs[x.key] = ["open": o["open_" + x.key] ?? true, "title": o["title_" + x.key] ?? "", "text": o["text_" + x.key] ?? "", "image": o["image_" + x.key] ?? ""] }
                s["genders"] = gs; return nil
            })
    }

    static var menuForm: some View {
        SettingsForm(title: "Меню, контакты, соцсети", sub: "Пункты меню, контакты в подвале и ссылки на социальные сети. Порядок меняется стрелками.",
            defs: [.section("Контакты"), FDef(k: "phone", label: "Телефон"), FDef(k: "email", label: "Электронная почта"), FDef(k: "address", label: "Адрес"), FDef(k: "hours", label: "Часы работы"),
                   FDef(k: "appStore", label: "Приложение в App Store", hint: "Ссылка вида https://apps.apple.com/ru/app/… — появится, когда Apple одобрит приложение"),
                   .section("Кнопка связи"),
                   FDef(k: "fab", label: "Показывать кнопку связи на всех страницах", kind: .bool, hint: "Круглая кнопка в правом нижнем углу"),
                   FDef(k: "whatsapp", label: "WhatsApp", hint: "Номер для кнопки связи, например +7 999 000-00-00. Пусто — WhatsApp не показывается"),
                   FDef(k: "_nav", label: "Меню", kind: .rows([FDef(k: "label", label: "Название"), FDef(k: "link", label: "Ссылка", hint: "#/catalog, #/catalog?cat=адрес, #/sale, #/sizes, #/page/адрес")])),
                   FDef(k: "_socials", label: "Социальные сети", kind: .rows([FDef(k: "name", label: "Название"), FDef(k: "url", label: "Ссылка", hint: "Например: https://t.me/ваш_канал")]))],
            getObj: { s in var o = (s["contacts"] as? [String: Any]) ?? [:]; o["_nav"] = s["nav"] ?? [Any](); o["_socials"] = s["socials"] ?? [Any](); return o },
            apply: { s, o in
                var c = o; s["nav"] = c.removeValue(forKey: "_nav") ?? [Any](); s["socials"] = c.removeValue(forKey: "_socials") ?? [Any](); s["contacts"] = c
                if let a = c["appStore"] as? String, !a.isEmpty, !a.hasPrefix("https://apps.apple.com/") { return "Ссылка на приложение должна начинаться с https://apps.apple.com/" }
                if let bad = (s["socials"] as? [[String: Any]] ?? []).first(where: { !(($0["url"] as? String ?? "").hasPrefix("http")) }) { return "Ссылка на «\(bad["name"] as? String ?? "")» должна начинаться с https://" }
                return nil
            })
    }

    static var generalForm: some View {
        SettingsForm(title: "Настройки", defs: [
                FDef(k: "storeName", label: "Название магазина", hint: "Логотип меняется в разделе «Логотип и название»"), FDef(k: "tagline", label: "Слоган"),
                FDef(k: "legal", label: "Реквизиты продавца", hint: "Например: ИП Фамилия Имя Отчество, ИНН 000000000000, ОГРНИП 000000000000000. Показываются в подвале и подставляются в оферту"),
                FDef(k: "footerNote", label: "Примечание о ценах"),
                .section("Плашки на карточках товаров"),
                FDef(k: "bt_new", label: "«Новинка» — текст"), FDef(k: "bc_new", label: "«Новинка» — цвет", kind: .color),
                FDef(k: "bt_sale", label: "«Скидка» — текст", hint: "{n} заменится на размер скидки: «Скидка {n}%» → «Скидка 15%»"), FDef(k: "bc_sale", label: "«Скидка» — цвет", kind: .color),
                FDef(k: "bt_hit", label: "«Хит продаж» — текст"), FDef(k: "bc_hit", label: "«Хит продаж» — цвет", kind: .color)],
            getObj: { s in
                var o = s; let b = JSON(s["badges"])
                for k in ["new", "sale", "hit"] { o["bt_" + k] = b[k]["text"].str; o["bc_" + k] = b[k]["color"].string ?? "#141414" }
                return o
            },
            apply: { s, o in
                if (o["storeName"] as? String ?? "").isEmpty { return "Укажите название магазина" }
                var next = o, b: [String: Any] = [:]
                let def = ["new": "Новинка", "sale": "Скидка {n}%", "hit": "Хит продаж"]
                for k in ["new", "sale", "hit"] {
                    let t = (o["bt_" + k] as? String) ?? ""
                    b[k] = ["text": t.isEmpty ? def[k]! : t, "color": o["bc_" + k] ?? "#141414"]
                    next.removeValue(forKey: "bt_" + k); next.removeValue(forKey: "bc_" + k)
                }
                next["badges"] = b; s = next; return nil
            }, extra: AnyView(StoreServiceCard()))
    }
}

/// Бонусы: на счетах, начислено, потрачено (под формой раздела «Бонусы»)
struct BonusStats: View {
    @ObservedObject private var admin = Admin.shared
    var body: some View {
        let users = admin.data["users"].array
        let held = users.reduce(0) { $0 + ($1["bonus"].int ?? 0) }
        var earned = 0, spent = 0
        for u in users { for e in u["bonusLog"].array {
            let t = e["type"].str, a = e["amount"].int ?? 0
            if ["earn", "revoke", "manual"].contains(t) { earned += a }
            if ["spend", "return"].contains(t) { spent -= a }
        } }
        return HStack(spacing: 8) { AdminStat(title: "На счетах", value: Fmt.num(held)); AdminStat(title: "Начислено", value: Fmt.num(earned)); AdminStat(title: "Потрачено", value: Fmt.num(spent)) }
    }
}

struct AdminStat: View {
    let title: String, value: String
    var sub = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Theme.font(11.5)).foregroundStyle(Theme.muted).lineLimit(2)
            Text(value).font(Theme.font(22, .light)).lineLimit(1).minimumScaleFactor(0.6)
            if !sub.isEmpty { Text(sub).font(Theme.font(11)).foregroundStyle(Theme.dim).lineLimit(1).minimumScaleFactor(0.8) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
    }
}

/// Нумерация заказов, состояние магазина, резервные копии и обновление (под «Настройками»)
struct StoreServiceCard: View {
    @State private var seq = ""
    @State private var health = JSON(nil)
    @ObservedObject private var admin = Admin.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Вход в панель").font(Theme.font(18, .light))
            Text("Отдельного пароля нет: панель открывается из личного кабинета аккаунтом владельца или сотрудника. Сотрудников и их роли — в разделе «Сотрудники».").font(Theme.font(13.5)).foregroundStyle(Theme.muted)
            Text("Нумерация заказов").font(Theme.font(18, .light))
            Text("Номер, который получит следующий заказ. Дальше номера идут по порядку: 1, 2, 3… Уже занятые номера пропускаются.").font(Theme.font(13.5)).foregroundStyle(Theme.muted)
            HStack { Field(label: "", text: $seq, placeholder: "…", keyboard: .numberPad); Button("Сохранить") { Task { await saveSeq() } }.font(Theme.font(14, .medium)).buttonStyle(.bordered).tint(Theme.ink) }
            Text("Состояние магазина").font(Theme.font(18, .light))
            if health.exists {
                let h = health, c = h["db"]["counts"]
                VStack(spacing: 0) {
                    li("База данных", h["db"]["integrity"].str == "ok" ? "в порядке · \(h["db"]["sizeMB"].double ?? 0) МБ" : "ошибка: " + h["db"]["integrity"].str, bad: h["db"]["integrity"].str != "ok")
                    li("Записей", "заказов \(c["orders"].int ?? 0) · покупателей \(c["users"].int ?? 0) · товаров \(c["products"].int ?? 0)")
                    if h["uploads"].exists { li("Фото", "\(h["uploads"]["files"].int ?? 0) шт. · \(h["uploads"]["sizeMB"].double ?? 0) МБ") }
                    if h["disk"].exists { li("Свободно на диске", "\(h["disk"]["freeGB"].double ?? 0) из \(h["disk"]["totalGB"].double ?? 0) ГБ", bad: (h["disk"]["freeGB"].double ?? 9) < 2) }
                    li("HTTPS", h["https"].bool ? "включён" : "ещё не включён", bad: !h["https"].bool)
                    li("Почта для писем", h["mail"].bool ? "подключена" : "не настроена", bad: !h["mail"].bool)
                    li("Онлайн-оплата", h["pay"].bool ? "подключена" : "не подключена")
                    li("Работает без перезапуска", "\(h["uptimeH"].double ?? 0) ч")
                }
            } else { ProgressView() }
            if admin.data["backup"].exists { li("Резервная копия", admin.data["backup"]["ok"].bool ? "последняя: " + Fmt.date(ISO.date(admin.data["backup"]["at"].str), time: true) : (admin.data["backup"]["error"].string ?? "не делалась"), bad: !admin.data["backup"]["ok"].bool) }
            if admin.data["update"].exists { li("Версия сайта", admin.data["update"]["version"].string ?? admin.data["update"]["sha"].str) }
        }
        .padding(16).softCard(20)
        .task {
            if let r = try? await API.shared.json("GET", "admin/order-seq") { seq = String(r["next"].int ?? 0) }
            if let r = try? await API.shared.json("GET", "admin/health") { health = r["health"] }
        }
    }
    private func saveSeq() async {
        do { let r = try await AdminAPI.post("order-seq", ["next": Int(seq) ?? 0]); seq = String(r["next"].int ?? Int(seq) ?? 0); Toast.shared.show("Следующий заказ получит № \(seq)") }
        catch { Toast.shared.show(error.localizedDescription) }
    }
    private func li(_ k: String, _ v: String, bad: Bool = false) -> some View {
        HStack(alignment: .top) { Text(k).font(Theme.font(13.5)).foregroundStyle(Theme.muted); Spacer(minLength: 10); Text(v).font(Theme.font(13.5)).foregroundStyle(bad ? Theme.danger : Theme.text).multilineTextAlignment(.trailing) }
            .padding(.vertical, 8).overlay(alignment: .bottom) { Divider1() }
    }
}
