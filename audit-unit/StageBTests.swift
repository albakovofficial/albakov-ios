import XCTest
@testable import Albakov

/// Юнит-тесты этапа B (Q-1): ключ повтора покупки подарочного сертификата.
/// Только проверка, в приложение не входят. Собираются целью AlbakovUnit (audit.yml).
final class GiftNonceTests: XCTestCase {
    private var d: UserDefaults!
    private var suite = ""
    /// Тело запроса POST /gifts — как в GiftView.buy()
    private func gift(_ amount: Int) -> [String: Any] {
        ["amount": amount, "toName": "Анна", "toEmail": "anna@example.com", "message": "", "fromName": "Пётр", "sendAt": "",
         "customer": ["firstName": "Пётр", "lastName": "Тестов", "phone": "79070000001", "email": "t@example.com"], "consent": true]
    }
    private func idem(_ b: [String: Any], _ defaults: UserDefaults) throws -> String {
        try CheckoutNonce.idem(CheckoutNonce.loadOrCreate(defaults, key: CheckoutNonce.giftKey), b)
    }

    override func setUp() {
        suite = "stage-b-gift-" + UUID().uuidString
        d = UserDefaults(suiteName: suite)
    }
    override func tearDown() { d.removePersistentDomain(forName: suite) }

    /// Первая отправка: ключ сохранён в памяти до ответа сервера; idem подходит серверу (^[a-z0-9]{16,64}$)
    func test01_KeySavedBeforeSending() throws {
        XCTAssertNil(d.string(forKey: CheckoutNonce.giftKey))
        let sent = try idem(gift(5000), d)
        XCTAssertNotNil(d.string(forKey: CheckoutNonce.giftKey), "Ключ покупки не сохранён до отправки")
        XCTAssertNotNil(sent.range(of: "^[a-z0-9]{16,64}$", options: .regularExpression), "Сервер не примет такой ключ: \(sent)")
    }

    /// Ответ потерян → экран открыли заново (и приложение перезапустили) → повтор с теми же данными даёт тот же idem:
    /// сервер вернёт уже созданный сертификат, а не создаст второй
    func test02_LostResponseReopenSameIdem() throws {
        let sent = try idem(gift(5000), d)
        // ответа нет — renew() не вызывается; новый экран и «перезапуск» читают ключ из памяти заново
        let again = UserDefaults(suiteName: suite)!
        XCTAssertEqual(try idem(gift(5000), again), sent, "Повтор после потери ответа ушёл с другим ключом — будет вторая покупка")
    }

    /// Повтор с другой суммой — это другая покупка: другой idem (сервер не вернёт прежний сертификат не на ту сумму)
    func test03_ChangedDataOtherIdem() throws {
        XCTAssertNotEqual(try idem(gift(5000), d), try idem(gift(10000), d))
    }

    /// Успешная покупка: ключ меняется — следующая покупка с теми же данными новая
    func test04_SuccessRenewsKey() throws {
        let first = try idem(gift(5000), d)
        CheckoutNonce.renew(d, key: CheckoutNonce.giftKey)
        XCTAssertNotEqual(try idem(gift(5000), d), first)
    }

    /// Ключи заказа и сертификата независимы: покупка сертификата не меняет ключ незавершённого заказа и наоборот
    func test05_GiftAndOrderKeysIndependent() {
        let order = CheckoutNonce.loadOrCreate(d)
        let giftKey = CheckoutNonce.loadOrCreate(d, key: CheckoutNonce.giftKey)
        XCTAssertNotEqual(order, giftKey)
        let giftAfter = CheckoutNonce.renew(d, key: CheckoutNonce.giftKey)
        XCTAssertNotEqual(giftAfter, giftKey)
        XCTAssertEqual(CheckoutNonce.loadOrCreate(d), order, "Покупка сертификата сменила ключ заказа")
        CheckoutNonce.renew(d)
        XCTAssertEqual(CheckoutNonce.loadOrCreate(d, key: CheckoutNonce.giftKey), giftAfter, "Оформление заказа сменило ключ сертификата")
    }
}
