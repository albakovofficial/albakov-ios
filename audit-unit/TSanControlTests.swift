import XCTest
@testable import Albakov

/// ПРОВЕРКА TSan (только ветка verify, не для слияния): намеренная гонка в юнит-тесте — отчёт обязан появиться
final class TSanControlTests: XCTestCase {
    final class Box { var n = 0 }
    func test01_DeliberateRace() {
        let b = Box()
        DispatchQueue.concurrentPerform(iterations: 8) { _ in for _ in 0..<1000 { b.n += 1 } }
        XCTAssertGreaterThan(b.n, 0)
    }
}
