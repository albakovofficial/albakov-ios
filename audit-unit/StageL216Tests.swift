import XCTest
import os
@testable import Albakov

/// Этап L.2.16: придержанный ответ NetStub ждёт сигнала теста в потоке клиента (таймер в его цикле событий),
/// а не в фоновой очереди. Поведение прежнее: до сигнала ответа нет, каждый сигнал отпускает ровно один ответ
@MainActor
final class NetStubHoldTests: XCTestCase {
    private let api = NetStub.api()

    func test01_HeldReplyWaitsForSignalOneEach() async throws {
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal(); gate.signal() }   // если тест упадёт посередине — не оставить запросы ждать
        NetStub.reset { _, p in p.hasPrefix("l216-") ? NetStub.Reply.json(["ok": true]).held(gate) : .json(["ok": true]) }
        let done = OSAllocatedUnfairLock(initialState: 0), failed = OSAllocatedUnfairLock(initialState: 0)
        let api = self.api
        for p in ["l216-a", "l216-b"] {
            Task {
                do { _ = try await api.json("GET", p); done.withLock { $0 += 1 } } catch { failed.withLock { $0 += 1 } }
            }
        }
        let sent = try await until { Set(NetStub.paths()).isSuperset(of: ["l216-a", "l216-b"]) }
        XCTAssertTrue(sent, "Запросы не дошли до NetStub: \(NetStub.paths())")
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(done.withLock { $0 }, 0, "Придержанный ответ пришёл до сигнала теста")

        gate.signal()
        let first = try await until { done.withLock { $0 } == 1 }
        XCTAssertTrue(first, "После сигнала ответ не пришёл")
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(done.withLock { $0 }, 1, "Один сигнал отпустил больше одного ответа")

        gate.signal()
        let second = try await until { done.withLock { $0 } == 2 }
        XCTAssertTrue(second, "После второго сигнала второй ответ не пришёл")
        XCTAssertEqual(failed.withLock { $0 }, 0, "Придержанный запрос завершился ошибкой")
    }
}
