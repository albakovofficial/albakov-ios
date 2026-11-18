import XCTest
@testable import Albakov

/// Юнит-тесты этапа H (SEC-1). Только проверка, в приложение не входят. Собираются целью AlbakovUnit (audit.yml, ios.yml).
/// Данные панели (Admin) принадлежат одному сотруднику: смена покупателя, выход и потеря прав их стирают,
/// обновление того же сотрудника — нет (иначе панель мигала бы пустой при каждом обновлении витрины)
@MainActor
final class AdminOwnerTests: XCTestCase {
    private func user(_ id: String) -> User? { User(JSON(["id": id])) }
    private func fill(_ admin: Admin) { admin.data = JSON(["orders": [["id": "o1"]]]); admin.error = "старая ошибка" }
    private func empty(_ admin: Admin, _ why: String) {
        XCTAssertFalse(admin.data.exists, "Данные панели остались: \(why)")
        XCTAssertNil(admin.error, "Ошибка прежнего сотрудника осталась: \(why)")
    }

    func test01_DataClearedOnOwnerChange() async throws {
        let shop = Shop.shared, admin = Admin.shared
        // первая загрузка хоста не должна вмешаться посреди теста; корзина при смене покупателя уходит в NetStub,
        // а не в аккаунт копии магазина (ревью этапа H)
        let hostReady = try await until(30) { shop.loaded || shop.loadError != nil }
        XCTAssertTrue(hostReady)
        let was = (shop.user, shop.isStaff, shop.api)
        shop.api = NetStub.api()
        defer { shop.setUser(was.0, staff: was.1); shop.api = was.2 }

        shop.setUser(user("audit-staff-a"), staff: true)
        fill(admin)
        shop.setUser(user("audit-staff-a"), staff: true)   // обновление витрины с тем же сотрудником
        XCTAssertTrue(admin.data["orders"].array.count == 1, "Данные стёрлись при обновлении того же сотрудника")
        XCTAssertEqual(admin.error, "старая ошибка")

        shop.setUser(user("audit-staff-b"), staff: true)   // вошёл другой сотрудник
        empty(admin, "вошёл другой сотрудник")

        fill(admin)
        shop.setUser(user("audit-staff-b"), staff: false)  // тот же человек, доступ к панели отозван
        empty(admin, "доступ к панели отозван")

        shop.setUser(user("audit-staff-b"), staff: true)
        fill(admin)
        shop.setUser(nil, staff: false)                     // выход или истёкший сеанс
        empty(admin, "выход")
    }
}
