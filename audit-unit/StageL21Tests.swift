import XCTest
import WebKit
import ObjectiveC
@testable import Albakov

/// Этап L.2.1: окно оплаты ЮKassa (PayWeb) решает, куда пускать страницу, в методе WKNavigationDelegate
/// webView(_:decidePolicyFor:decisionHandler:). WebKit вызывает его через Objective-C, только если объект отвечает
/// на селектор протокола. Иначе возврат на albakovofficial.ru не закроет окно, а ссылки банков и СБП не откроются.
@MainActor
final class PayWebDelegateTests: XCTestCase {
    /// Селектор необязательного метода протокола — тот, что объявлен в SDK: его наличие среди необязательных
    /// методов WKNavigationDelegate проверяется в Objective-C runtime, а не принимается на веру
    private static let decidePolicy = NSSelectorFromString("webView:decidePolicyForNavigationAction:decisionHandler:")

    /// Класс, который объявляет протокол, но метод не реализует — контроль, что проверка умеет падать
    private final class NoPolicy: NSObject, WKNavigationDelegate {}

    func test01_SelectorIsOptionalRequirementOfSDKProtocol() {
        let d = protocol_getMethodDescription(WKNavigationDelegate.self, Self.decidePolicy, false, true)
        XCTAssertNotNil(d.name, "В WKNavigationDelegate этого SDK нет необязательного метода с таким селектором")
        XCTAssertEqual(d.name, Self.decidePolicy)
    }

    func test02_PayWebDelegateRespondsToDecidePolicy() {
        XCTAssertFalse(NoPolicy().responds(to: Self.decidePolicy), "Контроль: объект без метода не должен отвечать на селектор")
        let delegate = PayWeb.C(done: { _ in })
        XCTAssertTrue(delegate.responds(to: Self.decidePolicy),
                      "PayWeb.C не отвечает на webView:decidePolicyForNavigationAction:decisionHandler: — WebKit не вызовет метод окна оплаты")
    }
}
