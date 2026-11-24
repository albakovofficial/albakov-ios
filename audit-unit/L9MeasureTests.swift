import XCTest
import SwiftUI
@testable import Albakov

// Этап L.9 — замеры, только для диагностической ветки measure/audit-stage-l9 (в приложение не входит, в main не идёт).

/// Счётчик вычислений body: стоит фоном у экрана и наблюдает Admin.shared — растёт, когда SwiftUI применил изменение
/// данных панели. Замер обновления ждёт его роста, иначе измерялся бы не пересчёт экрана, а пустое место
private struct L9Probe: View {
    @MainActor static var count = 0
    @ObservedObject var admin = Admin.shared
    var body: some View {
        let _ = { L9Probe.count += 1 }()
        Color.clear.frame(width: 1, height: 1)
    }
}

/// K-L12: сколько стоит Admin.orders — разбор и сортировка всего списка заказов при каждом обращении — в зависимости от
/// числа заказов, и сколько стоят экраны, которые к нему обращаются. Заказы синтетические (имена и телефоны выдуманные),
/// по устройству — как в ответе магазина: объекты Foundation из JSONSerialization (как API.json), даты с миллисекундами,
/// история заказа, статусы и способы оплаты приложения, от старых к новым. Без картинок: экраны рисуют заглушки, сеть не
/// нужна. Экраны — только те, что при наличии данных панели в сеть не ходят (AdminOverview, AdminOrdersView); главная
/// панели (загрузка без условия) не показывается. Данные панели приложения-хоста возвращаются после теста.
/// Итоги — строки «DEF1 L9ORDERS …»: префикс DEF1 ios.yml выводит в журнал прогона (этап J), артефакт отсюда недоступен.
/// Сборка Debug и симулятор: смысл имеет рост с числом заказов, а не миллисекунды. Чтобы уложиться в лимит шага (30 мин,
/// первый прогон 45472002218 его превысил), объём дальше не растёт, если медиана одного Admin.orders больше 1 с, а замер
/// экранов останавливается после 8 мин — пропуск печатается
@MainActor
final class L9OrdersMeasureTests: XCTestCase {
    private let sizes = [10, 100, 500, 1000, 2000, 5000]

    /// Ответ admin/data с n заказами за последний год — байты JSON, как пришли бы с сервера
    private func synthData(_ n: Int) throws -> Data {
        let now = Date().timeIntervalSince1970, iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func at(_ t: Double) -> String { iso.string(from: Date(timeIntervalSince1970: t)) }
        let statuses = ["new", "processing", "shipped", "done", "canceled", "returned"]
        let methods = ["online", "cod", "gift", "bonus"], pays = ["paid", "pending", "refunded"]
        let orders: [[String: Any]] = (0..<n).map { i in
            let t = now - Double(n - i) * 365 * 86_400 / Double(max(n, 1))
            let items: [[String: Any]] = (0..<(1 + i % 3)).map { k in
                ["productId": "p\(k)", "slug": "item-\(k)", "name": "Синтетический товар \(k)", "colorId": "c\(k)", "color": "Чёрный",
                 "size": "M", "qty": 1 + k % 2, "price": 4900 + k * 1000, "image": "", "sku": "ALB-\(1000 + k)"]
            }
            let history: [[String: Any]] = (0..<(2 + i % 3)).map { h in ["at": at(t + Double(h) * 3600), "text": "Синтетическое событие \(h)"] }
            return ["id": "o" + String(Int(t * 1000), radix: 36) + String(format: "%08lx", i), "number": "\(i + 1)",
                    "createdAt": at(t), "status": statuses[i % statuses.count], "items": items, "history": history,
                    "subtotal": 9800, "total": 9800, "payBy": at(t + 3600),
                    "payment": ["method": methods[i % methods.count], "status": pays[i % pays.count]],
                    "delivery": ["method": "cdek", "price": 0, "address": "Тестовая ул., 1"],
                    "customer": ["firstName": "Тест", "lastName": "Покупатель\(i)", "phone": "7999000" + String(format: "%04ld", i % 10000)]]
        }
        return try JSONSerialization.data(withJSONObject: ["orders": orders, "products": [] as [Any]])
    }
    /// Новые объекты с тем же содержимым — как после повторной загрузки admin/data без изменений
    private func parse(_ d: Data) throws -> JSON { JSON(try JSONSerialization.jsonObject(with: d)) }
    private func ms(_ body: () -> Void) -> Double {
        let d = ContinuousClock().measure(body)
        return Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
    }
    private func stats(_ v: [Double]) -> String {
        let s = v.sorted()
        return String(format: "median_ms=%.3f min_ms=%.3f max_ms=%.3f reps=%ld", s[s.count / 2], s.first ?? 0, s.last ?? 0, s.count)
    }
    private func log(_ s: String) { print("DEF1 L9ORDERS " + s) }

    /// Одно обращение к Admin.orders и типичные обращения экранов: фильтр новых, поиск заказа по номеру (экран заказа)
    func test01_OrdersComputeTime() throws {
        let admin = Admin.shared, was = admin.data
        defer { admin.data = was }
        for n in sizes {
            admin.data = try parse(synthData(n))
            let warm = ms { _ = admin.orders }   // прогрев и проба
            if warm > 3000 { log("compute n=\(n) skipped: одно вычисление \(Int(warm)) мс"); break }
            var one: [Double] = [], newOnes: [Double] = [], find: [Double] = []
            let id = admin.orders[n / 2].id
            for _ in 0..<9 {
                one.append(ms { _ = admin.orders.count })
                newOnes.append(ms { _ = admin.orders.filter { $0.status == "new" }.count })
                find.append(ms { _ = admin.orders.first { $0.id == id } })
            }
            log("compute n=\(n) what=orders \(stats(one))")
            log("compute n=\(n) what=filter_new \(stats(newOnes))")
            log("compute n=\(n) what=find_by_id \(stats(find))")
            if one.sorted()[one.count / 2] > 1000 { log("compute: дальше n не растёт — медиана больше 1 с"); break }
        }
    }

    /// Экран на главном потоке: первый показ (создание и раскладка; прежний экран убран до замера) и обновление после новой
    /// копии тех же данных панели — до роста счётчика L9Probe (SwiftUI применил изменение) и раскладки. Без отрисовки
    /// CoreAnimation: абсолютные числа занижены, сравнивать — рост с n. caught — в скольких повторах обновление поймано
    func test02_ScreensRenderTime() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene, "Нет сцены приложения-хоста")
        let admin = Admin.shared, was = admin.data
        let w = UIWindow(windowScene: scene)
        w.frame = CGRect(x: 0, y: 0, width: 375, height: 667)
        defer {
            // экран убран, его отложенные задачи доработали, пока синтетические данные на месте (загрузки без данных нет)
            w.isHidden = true; w.rootViewController = nil
            RunLoop.main.run(until: Date().addingTimeInterval(1))
            admin.data = was
        }
        let screens: [(String, () -> AnyView)] = [
            ("overview", { AnyView(NavigationStack { AdminOverview().background(L9Probe()) }.environmentObject(Router())) }),
            ("orders_list", { AnyView(NavigationStack { AdminOrdersView().background(L9Probe()) }.environmentObject(Router())) }),
        ]
        let start = Date()
        sizes: for n in sizes {
            let raw = try synthData(n)
            admin.data = try parse(raw)
            let probe = ms { _ = admin.orders }
            if probe > 1000 { log("render n=\(n) skipped: одно Admin.orders \(Int(probe)) мс"); break }
            for (name, make) in screens {
                if Date().timeIntervalSince(start) > 480 { log("render n=\(n) screen=\(name) skipped: замер экранов дольше 8 мин"); break sizes }
                var first: [Double] = [], update: [Double] = [], caught = 0
                for _ in 0..<3 {
                    w.rootViewController = nil; w.isHidden = true
                    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
                    first.append(ms {
                        w.rootViewController = UIHostingController(rootView: make())
                        w.isHidden = false; w.layoutIfNeeded()
                    })
                    RunLoop.main.run(until: Date().addingTimeInterval(0.2))   // первый показ доработал
                    let next = try parse(raw), c0 = L9Probe.count
                    update.append(ms {
                        admin.data = next
                        var spins = 0
                        while L9Probe.count == c0 && spins < 200 { RunLoop.main.run(until: Date().addingTimeInterval(0.001)); spins += 1 }
                        w.layoutIfNeeded()
                    })
                    if L9Probe.count != c0 { caught += 1 }
                }
                log("render n=\(n) screen=\(name) phase=first \(stats(first))")
                log("render n=\(n) screen=\(name) phase=update \(stats(update)) caught=\(caught)/3")
            }
        }
    }
}
