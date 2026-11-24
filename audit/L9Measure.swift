import XCTest

// Этап L.9 — замеры, только для диагностической ветки measure/audit-stage-l9 (в приложение не входит, в main не идёт).

/// Отметки для замера памяти: audit.yml пишет RSS приложения раз в полсекунды (mem.log, этап A), по отметкам из журнала
/// тестов считается пик каждого теста — от первого запуска приложения в тесте («launched», до него в mem.log ещё может быть
/// приложение прошлого теста) до его конца. Формат — тот же, что у mark(): «MEMMARK <метка> <время, с>»
nonisolated func l9mark(_ testName: String, _ what: String) {
    let t = testName.split(separator: " ").last.map { String($0.dropLast()) } ?? testName   // «-[Класс test00_…]» → «test00_…»
    print("MEMMARK \(what)-\(t) \(Int(Date().timeIntervalSince1970))")
}

extension AuditUITests {
    /// L8-06: сколько раз переходы по панели загружают admin/data и сколько ждёт сотрудник. Только чтение, ничего не меняет.
    /// Число загрузок — счётчик посредника adminData (каждый GET /api/admin/data, до и после шага), время — от действия до
    /// появления экрана (XCUITest, с точностью его опроса). Строки «L9NAV …» в журнале тестов, со временем (мс) — для
    /// сопоставления со строками посредника «L9 admin/data». После шага пауза 3 с: досчитываются загрузки этого шага.
    /// Экран не появился — раунд прерывается: дальше нажимать вслепую нельзя
    func test90_L9AdminLoadMeasure() {
        signInOwner()
        func loads() -> Int { ctl("stats")["adminData"] as? Int ?? -1 }
        @discardableResult func step(_ name: String, _ target: () -> XCUIElement, _ action: () -> Void) -> Bool {
            let before = loads(), t0 = Date()
            action()
            let el = target(), ok = el.waitForExistence(timeout: 30)
            let ms = Int(Date().timeIntervalSince(t0) * 1000)
            sleep(3)
            let after = loads()
            let s = "L9NAV \(name) | at_ms=\(Int(t0.timeIntervalSince1970 * 1000)) loads_before=\(before) loads_after=\(after) loads=\(after - before) wait_ms=\(ms) shown=\(ok)"
            print(s); note(s)
            if !ok { shot("L9 \(name) — экран не появился") }
            return ok
        }
        func title(_ prefix: String) -> XCUIElement { app.navigationBars.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch }
        func card(_ prefix: String) -> XCUIElement { app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch }
        func orderRow() -> XCUIElement { app.buttons.matching(NSPredicate(format: "label BEGINSWITH '№ '")).firstMatch }
        func productRow() -> XCUIElement { app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'остаток '")).firstMatch }
        func back() { app.navigationBars.buttons.element(boundBy: 0).tap() }
        /// Холодный запуск на главную панели без паузы launch() (4 с): время до карточек — запуск и загрузка admin/data
        func coldLaunch() {
            app = XCUIApplication()
            app.launchArguments = ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_RU", "-screen", "/admin"]
            if let t = ProcessInfo.processInfo.environment["TSAN_OPTIONS"] { app.launchEnvironment["TSAN_OPTIONS"] = t }
            app.launch()
            l9mark(name, "launched")
        }

        guard step("01 холодный запуск: главная панели", { card("Товары") }, coldLaunch) else { return }
        for round in 1...2 {
            guard step("r\(round) 02 главная → Заказы", { orderRow() }, { card("Заказы").tap() }),
                  step("r\(round) 03 Заказы → заказ", { title("Заказ №") }, { orderRow().tap() }),
                  step("r\(round) 04 заказ → назад к Заказам", { orderRow() }, back),
                  step("r\(round) 05 Заказы → назад к главной", { card("Товары") }, back),
                  step("r\(round) 06 главная → Товары", { productRow() }, { card("Товары").tap() }),
                  step("r\(round) 07 Товары → Массовые изменения", { title("Массовые изменения") }, { button("Массовые изменения и остатки в Excel").tap() }),
                  step("r\(round) 08 Массовые → назад к Товарам", { productRow() }, back),
                  step("r\(round) 09 Товары → назад к главной", { card("Заказы") }, back)
            else { XCTFail("L9: раунд \(round) прерван — экран не появился"); break }
        }
        shot("L9 замер панели — конец")
    }
}
