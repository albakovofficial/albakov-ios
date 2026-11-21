import XCTest
@testable import Albakov

/// Этап L.2.14: FinanceCosts.value и FinanceSettings.settingsValue — чистые расчёты, больше не на главном акторе
/// (изоляцию им давало только объявление внутри View). Вызов без await из задач ниже — сам по себе проверка компилятором:
/// вернись функции на главный актор, тест не соберётся. Здесь — что вне главного актора и параллельно они дают
/// те же значения, что проверяет FinanceValuesTests (там тесты синхронные и идут на главном потоке, как у экрана)
final class FinanceValuesIsolationTests: XCTestCase {
    private static func form() -> [String: Any] {
        ["taxRate": NSNumber(value: 6), "sbpYk": NSNumber(value: 0.4), "sbpPartner": NSNumber(value: 1.5),
         "otherYk": NSNumber(value: 2.8), "otherPartner": NSNumber(value: 1), "partnerMin": NSNumber(value: 0.65), "codFee": NSNumber(value: 3)]
    }
    private static func parsed(_ d: Data?) -> NSDictionary? { d.flatMap { try? JSONSerialization.jsonObject(with: $0) as? NSDictionary } }

    /// Те же случаи, что в FinanceValuesTests test01–test04. Возвращает первый несовпавший случай, nil — все совпали
    private static func mismatch() -> String? {
        let expected = #"{"categories":[{"id":"c1","kind":"fixed","name":"Реклама"}],"codFee":3,"costs":{"p1":450},"partnerMin":0.65,"rates":{"other":{"partner":1,"yk":2.8},"sbp":{"partner":1.5,"yk":0.4}},"taxRate":6}"#
        guard let v = FinanceSettings.settingsValue(JSON(form()), categories: [["id": "c1", "name": "Реклама", "kind": "fixed"]], costs: ["p1": 450]),
              let got = parsed(try? JSONSerialization.checkedData(v)), got == parsed(Data(expected.utf8)) else { return "обычные ставки" }
        for k in form().keys {
            var f = form(); f.removeValue(forKey: k)
            if FinanceSettings.settingsValue(JSON(f), categories: [], costs: [String: Any]()) != nil { return "без «\(k)»" }
        }
        for bad: Any in ["2,8", NSNumber(value: Double.nan), NSNumber(value: Double.infinity), NSNull()] {
            var f = form(); f["otherYk"] = bad
            if FinanceSettings.settingsValue(JSON(f), categories: [], costs: [String: Any]()) != nil { return "ставка \(bad)" }
        }
        let costs: [(String, Double?)] = [("450", 450), ("450,50", 450.5), ("12345.67", 12345.67)]
        for (t, n) in costs where FinanceCosts.value(t) as? Double != n { return "себестоимость «\(t)»" }
        if FinanceCosts.value("") as? String != "" { return "пустая себестоимость" }
        for bad in ["1.200,50", "1,2,3", ",", "."] where FinanceCosts.value(bad) != nil { return "себестоимость «\(bad)»" }
        return nil
    }

    /// Неизолированный async-тест и 32 параллельные задачи: результат тот же, общего состояния у расчётов нет
    func test01_OffMainActorSameValues() async {
        XCTAssertNil(Self.mismatch(), "Вне главного актора расчёт дал другое значение")
        let failed = await withTaskGroup(of: String?.self) { g in
            for _ in 0..<32 { g.addTask { FinanceValuesIsolationTests.mismatch() } }
            var out: [String] = []
            for await r in g { if let r { out.append(r) } }
            return out
        }
        XCTAssertEqual(failed, [], "Параллельный расчёт дал другие значения")
    }
}
