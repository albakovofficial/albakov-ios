import XCTest
import os
@testable import Albakov

/// Этап L.2.18: замер пика памяти (MemoryPeak) и «ответ один раз» (Once) — под OSAllocatedUnfairLock вместо @unchecked
/// Sendable. Проверяются сами гарантии: пик, записанный фоновым опросом, виден тесту; после окончания замера опрос
/// останавливается; короткая операция не даёт нулевого роста; Once срабатывает ровно один раз при одновременных вызовах

/// Подставная «память» для MemoryPeak: значение задаёт тест, каждое чтение считается (значение и счёт — одним захватом)
private struct FakeMemory: Sendable {
    private struct State: Sendable { var value: Int64 = 100; var reads = 0 }
    private let s = OSAllocatedUnfairLock(initialState: State())
    func set(_ v: Int64) { s.withLock { $0.value = v } }
    var reads: Int { s.withLock { $0.reads } }
    func read() -> Int64 { s.withLock { $0.reads += 1; return $0.value } }
}

@MainActor
final class MemoryPeakTests: XCTestCase {
    /// Операция закончилась раньше, чем опрос что-то увидел: рост — по замеру сразу после неё, а не 0 «по умолчанию».
    /// Опрос раз в секунду: за время операции фоновый поток успевает прочесть память не больше одного раза
    func test01_ShortOperationNotZero() async {
        let mem = FakeMemory()
        let (value, grow) = await MemoryPeak.measure(read: { mem.read() }, every: 1_000_000) { () -> String in
            mem.set(130); return "готово"
        }
        XCTAssertEqual(value, "готово")
        XCTAssertEqual(grow, 30, "Рост памяти короткой операции потерян")
    }

    /// Кратковременный пик, который видел только фоновый опрос, доходит до результата. Ждём два чтения после подъёма:
    /// второе означает, что фоновый поток закончил предыдущий шаг — записал увиденный пик
    func test02_PeakFromBackgroundPollVisible() async throws {
        let mem = FakeMemory()
        let (seen, grow) = try await MemoryPeak.measure(read: { mem.read() }, every: 1000) { () async throws -> Bool in
            mem.set(500)
            let r0 = mem.reads
            let seen = try await until { mem.reads >= r0 + 2 }
            mem.set(100)
            return seen
        }
        XCTAssertTrue(seen, "Фоновый опрос не читал память")
        XCTAssertEqual(grow, 400, "Пик, записанный фоновым опросом, не виден в результате")
    }

    /// После замера опрос останавливается: не больше одного чтения, которое уже шло (без ожидания точного времени)
    func test03_PollingStopsAfterMeasure() async throws {
        let mem = FakeMemory()
        let (polled, _) = try await MemoryPeak.measure(read: { mem.read() }, every: 1000) { () async throws -> Bool in
            try await until { mem.reads >= 3 }
        }
        XCTAssertTrue(polled, "Фоновый опрос не работал")
        let after = mem.reads
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertLessThanOrEqual(mem.reads, after + 1, "Опрос продолжился после окончания замера")
    }
}

final class OnceTests: XCTestCase {
    /// 1000 одновременных вызовов на нескольких потоках — «да» ровно один раз; дальше только «нет», без зависания
    func test01_ConcurrentTakeExactlyOnce() {
        let once = Once(), won = OSAllocatedUnfairLock(initialState: 0)
        DispatchQueue.concurrentPerform(iterations: 1000) { _ in
            if once.take() { won.withLock { $0 += 1 } }
        }
        XCTAssertEqual(won.withLock { $0 }, 1, "Ответ «один раз» выдан не один раз")
        XCTAssertFalse(once.take())
    }

    /// Обработчик NetStub захватывает копию Once: копии делят одно состояние
    func test02_CopiesShareState() {
        let a = Once(), b = a
        XCTAssertTrue(b.take())
        XCTAssertFalse(a.take(), "Копия Once сработала второй раз")
    }
}
