import XCTest
@testable import Albakov

/// Этап L.8.5 (L8-08): ключи гостевых заказов — не больше 50 последних, без дублей, в порядке сохранения; прежний
/// словарь без порядка переписывается один раз, порядок — по времени создания из номера заказа. Ключи и номера —
/// синтетические, вида настоящих: номер "o" + время в base36 + 8 hex, ключ — 32 hex. Запись на телефоне возвращается
/// после каждого теста

/// Номер заказа, созданного в момент ms (как server.js uid('o')); n — «случайная» часть
private func oid(_ ms: Int, _ n: Int = 0) -> String { "o" + String(ms, radix: 36) + String(format: "%08x", n) }
private func key(_ n: Int) -> String { String(repeating: "0", count: 24) + String(format: "%08x", n) }
/// Номера в том порядке, в каком они лежат на телефоне (от старого к новому)
private func storedIds() -> [String] { (UserDefaults.standard.array(forKey: OrderTokens.storeKey) as? [[String]] ?? []).map { $0[0] } }
private let t0 = 1_795_000_000_000   // ноябрь 2026, мс

final class OrderTokensTests: XCTestCase {
    private var saved: Any?
    override func setUp() { super.setUp(); saved = UserDefaults.standard.object(forKey: OrderTokens.storeKey); OrderTokens.clear() }
    override func tearDown() { UserDefaults.standard.set(saved, forKey: OrderTokens.storeKey); super.tearDown() }

    func test01_SaveOne() {
        OrderTokens.save(oid(t0), key(1))
        XCTAssertEqual(OrderTokens.all, [oid(t0): key(1)])
        XCTAssertEqual(storedIds(), [oid(t0)])
    }

    /// 50 ключей хранятся все; 51-й вытесняет сохранённый раньше всех, остальные и их порядок — на месте
    func test02_FiftyKeptAndFiftyFirstEvictsOldest() {
        let ids = (0..<51).map { oid(t0 + $0 * 1000, $0) }
        for (i, id) in ids.prefix(50).enumerated() { OrderTokens.save(id, key(i)) }
        XCTAssertEqual(OrderTokens.all.count, 50)
        XCTAssertEqual(storedIds(), Array(ids.prefix(50)))
        OrderTokens.save(ids[50], key(50))
        XCTAssertEqual(OrderTokens.all.count, 50)
        XCTAssertNil(OrderTokens.all[ids[0]], "Самый старый ключ не вытеснен")
        XCTAssertEqual(OrderTokens.all[ids[50]], key(50))
        XCTAssertEqual(storedIds(), Array(ids.suffix(50)))
    }

    /// Тот же заказ ещё раз (ссылка из письма): без дубля, становится последним, ключ — новый. Вытесняется следующий
    /// по старшинству, а не он
    func test03_ResaveMovesToEndWithoutDuplicate() {
        let a = oid(t0, 1), b = oid(t0 + 1, 2), c = oid(t0 + 2, 3)
        OrderTokens.save(a, key(1)); OrderTokens.save(b, key(2)); OrderTokens.save(c, key(3))
        OrderTokens.save(a, key(9))
        XCTAssertEqual(storedIds(), [b, c, a])
        XCTAssertEqual(OrderTokens.all[a], key(9))
        for i in 0..<48 { OrderTokens.save(oid(t0 + 100 + i, 100 + i), key(100 + i)) }
        XCTAssertNil(OrderTokens.all[b], "Вытеснен не самый старый")
        XCTAssertEqual(OrderTokens.all[a], key(9), "Сохранённый снова заказ вытеснен как старый")
        XCTAssertEqual(OrderTokens.all.count, 50)
    }

    /// Прежний словарь (до L.8.5): 60 ключей и один номер не того вида. Остаются 50 заказов, созданных позже всех,
    /// от старого к новому; номер не того вида считается самым старым; ключи не меняются. Повторный запуск ничего не меняет,
    /// а маленький словарь переписывается целиком
    func test04_MigrationKeepsNewestFiftyAndIsIdempotent() {
        var old: [String: String] = ["42": key(999)]
        let ids = (0..<60).map { oid(t0 + $0 * 60_000, 60 - $0) }   // заказы раз в минуту, от старого к новому
        for (i, id) in ids.enumerated() { old[id] = key(i) }
        UserDefaults.standard.set(old, forKey: OrderTokens.storeKey)
        OrderTokens.migrate()
        XCTAssertEqual(storedIds(), Array(ids.suffix(50)))
        let after = OrderTokens.all
        for (i, id) in ids.enumerated().dropFirst(10) { XCTAssertEqual(after[id], key(i), "Ключ изменился") }
        XCTAssertNil(OrderTokens.all["42"])
        let once = UserDefaults.standard.array(forKey: OrderTokens.storeKey) as? [[String]]
        OrderTokens.migrate()
        XCTAssertEqual(UserDefaults.standard.array(forKey: OrderTokens.storeKey) as? [[String]], once, "Повторный запуск изменил список")

        UserDefaults.standard.set([ids[2]: key(2), "42": key(999), ids[0]: key(0)], forKey: OrderTokens.storeKey)
        XCTAssertEqual(OrderTokens.all, [ids[2]: key(2), "42": key(999), ids[0]: key(0)], "Чтение потеряло ключи прежнего формата")
        XCTAssertEqual(storedIds(), ["42", ids[0], ids[2]])
    }

    /// Записи нет или она повреждена — пусто, без падения; следующее сохранение пишет список заново
    func test05_EmptyAndBrokenStorage() {
        XCTAssertTrue(OrderTokens.all.isEmpty)
        OrderTokens.migrate()
        XCTAssertNil(UserDefaults.standard.object(forKey: OrderTokens.storeKey), "Пустая запись появилась без ключей")
        let broken: [Any] = ["строка", 42, [1, 2], ["o1": 5], [["o1"]], [["", key(1)]]]
        for b in broken {
            UserDefaults.standard.set(b, forKey: OrderTokens.storeKey)
            XCTAssertTrue(OrderTokens.all.isEmpty, "Повреждённая запись \(b) прочитана как ключи")
            OrderTokens.save(oid(t0), key(1))
            XCTAssertEqual(OrderTokens.all, [oid(t0): key(1)], "После повреждённой записи \(b) ключ не сохранился")
            OrderTokens.clear()
        }
    }

    /// Одновременные сохранения: сначала 40 (все остаются), затем ещё 200 — ровно 50 без повторов
    func test06_ConcurrentSavesKeepEveryKey() async {
        await withTaskGroup(of: Void.self) { g in
            for i in 0..<40 { g.addTask { OrderTokens.save(oid(t0 + i, i), key(i)) } }
        }
        XCTAssertEqual(OrderTokens.all.count, 40, "Часть ключей потеряна при одновременной записи")
        await withTaskGroup(of: Void.self) { g in
            for i in 100..<300 { g.addTask { OrderTokens.save(oid(t0 + i, i), key(i)) } }
        }
        let ids = storedIds()
        XCTAssertEqual(ids.count, 50); XCTAssertEqual(Set(ids).count, 50, "В списке повторы")
    }
}

@MainActor   // Router — на главном акторе
final class OrderTokensLinkTests: XCTestCase {
    /// Ссылка из письма (/order/<номер>?t=<ключ>) — тот же формат, что раньше: ключ сохраняется и открывает заказ. Старый
    /// заказ по ссылке при полном списке не вытесняется сразу же — он становится последним
    func test01_EmailLinkStillWorksWhenFull() {
        let saved = UserDefaults.standard.object(forKey: OrderTokens.storeKey)
        defer { UserDefaults.standard.set(saved, forKey: OrderTokens.storeKey) }
        OrderTokens.clear()
        for i in 0..<50 { OrderTokens.save(oid(t0 + 1000 + i, i), key(i)) }
        let oldOrder = oid(t0 - 86_400_000 * 300, 7), k = key(777)
        let r = Router()
        r.open(path: "/order/\(oldOrder)?t=\(k)")
        XCTAssertEqual(r.account, [.orders, .order(oldOrder)])
        XCTAssertEqual(OrderTokens.all[oldOrder], k, "Ключ из ссылки на старый заказ не сохранён")
        XCTAssertEqual(storedIds().last, oldOrder)
        XCTAssertEqual(OrderTokens.all.count, 50)
    }

}

