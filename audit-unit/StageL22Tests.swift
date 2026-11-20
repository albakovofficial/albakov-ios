import XCTest
import SwiftUI
@testable import Albakov

/// Этап L.2.2: Router и Toast принадлежат главному актору. Тесты — о поведении, которое должно остаться прежним:
/// стеки переходов по вкладкам и показ сообщений (переход по ссылкам проверяют RouterLinkTests и RouterEmptyIdTests)
@MainActor
final class RouterStackTests: XCTestCase {
    /// push, pop и reset меняют только свою вкладку; push без вкладки — в текущую
    func test01_PushPopResetKeepTabsSeparate() {
        let r = Router()
        r.push(.product("p1"))
        r.push(.orders, on: .account); r.push(.order("o1"), on: .account)
        XCTAssertEqual(r.tab, .account)
        XCTAssertEqual(r.home, [.product("p1")]); XCTAssertEqual(r.account, [.orders, .order("o1")])
        r.pop(on: .account)
        XCTAssertEqual(r.account, [.orders])
        r.pop(on: .cart)
        XCTAssertEqual(r.cart, [], "Пустой стек — без изменений и без падения")
        r.reset(.home, to: [.search])
        XCTAssertEqual(r.tab, .home); XCTAssertEqual(r.home, [.search]); XCTAssertEqual(r.account, [.orders])
    }

    /// Выход из кабинета закрывает оформление во всех вкладках, остальные экраны остаются
    func test02_CloseCheckoutCutsCheckoutOnly() {
        let r = Router()
        r.reset(.cart, to: [.checkout, .page("offer")])
        r.reset(.account, to: [.orders, .checkout])
        r.reset(.home, to: [.product("p1")])
        r.closeCheckout()
        XCTAssertEqual(r.cart, []); XCTAssertEqual(r.account, [.orders]); XCTAssertEqual(r.home, [.product("p1")])
    }

    /// Стек вкладки, который получает NavigationStack: чтение и запись идут в тот же Router
    func test03_TabBindingReadsAndWritesStack() {
        let r = Router()
        let b = r.binding(.catalog)
        b.wrappedValue = [.search]
        XCTAssertEqual(r.catalog, [.search])
        r.push(.product("p2"), on: .catalog)
        XCTAssertEqual(b.wrappedValue, [.search, .product("p2")])
        XCTAssertEqual(r.home, [], "Другие вкладки не меняются")
    }
}

@MainActor
final class ToastTests: XCTestCase {
    /// Сообщение появляется, новое заменяет прежнее, и прежнее не прячет новое раньше времени; затем сообщение уходит
    func test01_ShowReplaceAndHide() async throws {
        let toast = Toast()
        toast.show("Первое")
        let first = try await until { toast.text == "Первое" }
        XCTAssertTrue(first, "Сообщение не появилось")
        try await Task.sleep(nanoseconds: 1_500_000_000)
        toast.show("Второе")
        let second = try await until { toast.text == "Второе" }
        XCTAssertTrue(second, "Новое сообщение не заменило прежнее")
        // 2,7 с после первого — прежнее, будь оно не отменено, уже убрало бы текст (через 2,4 с)
        try await Task.sleep(nanoseconds: 1_200_000_000)
        XCTAssertEqual(toast.text, "Второе", "Прежнее сообщение спрятало новое раньше времени")
        let hidden = try await until(3) { toast.text == nil }
        XCTAssertTrue(hidden, "Сообщение не скрылось")
    }

    /// Текст ошибки (show(String?)): отменённый запрос (nil) и пустой текст не показываются
    func test02_EmptyAndCancelledNotShown() async throws {
        let toast = Toast()
        toast.show(nil as String?)
        toast.show("" as String?)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertNil(toast.text)
    }
}
