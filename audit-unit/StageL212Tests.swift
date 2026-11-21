import XCTest
@testable import Albakov
#if canImport(DeclaredAgeRange)
import DeclaredAgeRange
#endif

/// Этап L.2.12: проверка возраста перед заказом. Опрос сервиса Apple вынесен в неизолированную функцию — поведение прежнее:
/// взрослому (ответ запомнен) не спрашиваем; иначе решает Apple; ошибка или недоступность сервиса — «проверка не нужна»
final class AgeCheckTests: XCTestCase {
    private let adultKey = "ageCheck.adult"   // ключ, под которым запомнен ответ «18+»: сменить — значит переспросить взрослых
    private var saved: Any?
    override func setUp() { super.setUp(); saved = UserDefaults.standard.object(forKey: adultKey) }
    override func tearDown() { UserDefaults.standard.set(saved, forKey: adultKey); super.tearDown() }

    /// Ответ «18+» уже запомнен — проверка не нужна, окно больше не появляется
    func test01_RememberedAdultIsNotAskedAgain() async {
        UserDefaults.standard.set(true, forKey: adultKey)
        let needed = await AgeCheck.needed()
        XCTAssertFalse(needed)
    }

    /// Ответ не запомнен — решение Apple как есть (на iOS 26.2+), ошибка сервиса — «не нужна»; на iOS до 26.2 — «не нужна».
    /// Эталон — прямой опрос сервиса, как до этапа L.2.12. На симуляторе CI сервис отвечает «не нужна» или ошибкой, поэтому
    /// ветки «нужна» и разница между ними не покрыты: подменить системный сервис нельзя
    func test02_NeededFollowsAppleAndErrorsMeanNo() async {
        UserDefaults.standard.removeObject(forKey: adultKey)
        var expected = false
        #if canImport(DeclaredAgeRange)
        if #available(iOS 26.2, *) { expected = (try? await AgeRangeService.shared.isEligibleForAgeFeatures) ?? false }
        #endif
        let needed = await AgeCheck.needed()
        XCTAssertEqual(needed, expected)
    }
}
