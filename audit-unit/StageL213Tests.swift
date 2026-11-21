import XCTest
@testable import Albakov

/// Этап L.2.13: состояние подставных серверов ImageStub и NetStub — под OSAllocatedUnfairLock. Проверяется поведение
/// заглушек, на которое опираются остальные тесты: счётчики, «битые» адреса, журнал, замена обработчика,
/// одновременные запросы без потерь и обработчик, который сам читает журнал
final class StubStateTests: XCTestCase {
    /// Журнал NetStub общий для процесса: тесты смотрят только свои пути — с этим префиксом
    private let pre = "l213-"
    private func mine() -> [NetStub.Seen] { NetStub.seen.filter { $0.path.hasPrefix(pre) } }
    private func url(_ name: String = UUID().uuidString) -> URL { URL(string: "http://stub.test/\(name).png")! }
    private func imageSession() -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [ImageStub.self]
        return URLSession(configuration: c)
    }

    /// Каждый запрос считается по своему адресу, в том числе одновременные — ни один не теряется
    func test01_ImageStubCountsEveryRequest() async throws {
        let session = imageSession(), a = url(), b = url()
        XCTAssertEqual(ImageStub.count(a), 0)
        _ = try await session.data(from: a)
        XCTAssertEqual(ImageStub.count(a), 1)
        try await withThrowingTaskGroup(of: Void.self) { g in
            for i in 0..<40 { g.addTask { _ = try await session.data(from: i % 2 == 0 ? a : b) } }
            try await g.waitForAll()
        }
        XCTAssertEqual(ImageStub.count(a), 21); XCTAssertEqual(ImageStub.count(b), 20)
    }

    /// «Битый» адрес отдаёт не картинку, пока не снят; другие адреса и счётчик не задевает
    func test02_ImageStubBroken() async throws {
        let session = imageSession(), u = url(), other = url()
        ImageStub.setBroken(u, true)
        let (bad, _) = try await session.data(from: u)
        let (fine, _) = try await session.data(from: other)
        ImageStub.setBroken(u, false)
        let (good, _) = try await session.data(from: u)
        XCTAssertEqual(bad, Data("не картинка".utf8))
        XCTAssertEqual(fine, ImageStub.png); XCTAssertEqual(good, ImageStub.png)
        XCTAssertEqual(ImageStub.count(u), 2)
    }

    /// Журнал: метод, путь, запрос и тело — в порядке прихода; reset — новый обработчик и чистый журнал;
    /// clearSeen — чистый журнал, обработчик прежний
    func test03_NetStubLogResetAndHandler() async throws {
        let api = NetStub.api()
        NetStub.reset { _, p in .json(["ok": true, "from": "first", "path": p]) }
        let r1 = try await api.json("GET", pre + "state", query: ["q": "1"])
        _ = try await api.json("POST", pre + "orders", body: ["a": 1])
        XCTAssertEqual(r1["from"].str, "first")
        XCTAssertEqual(mine().map(\.method), ["GET", "POST"])
        XCTAssertEqual(mine().map(\.path), [pre + "state", pre + "orders"])
        XCTAssertEqual(mine().first?.query, "q=1")
        XCTAssertNil(mine().first?.body)
        XCTAssertEqual(JSON(data: mine().last?.body ?? Data())["a"].int, 1)

        NetStub.clearSeen()
        XCTAssertTrue(mine().isEmpty)
        let r2 = try await api.json("GET", pre + "me")
        XCTAssertEqual(r2["from"].str, "first", "clearSeen сменил обработчик")
        XCTAssertEqual(mine().map(\.path), [pre + "me"])

        NetStub.reset { _, _ in .json(["ok": true, "from": "second"]) }
        XCTAssertTrue(mine().isEmpty, "reset не очистил журнал")
        let r3 = try await api.json("GET", pre + "me")
        XCTAssertEqual(r3["from"].str, "second", "reset не заменил обработчик")
    }

    /// Одновременные запросы: журнал не теряет записей, каждый ответ — от своего обработчика по своему пути
    func test04_NetStubConcurrentRequestsNotLost() async throws {
        let api = NetStub.api(), pre = self.pre
        NetStub.reset { _, p in .json(["ok": true, "path": p]) }
        let answers = try await withThrowingTaskGroup(of: (String, String).self) { g in
            for i in 0..<50 { g.addTask { let p = pre + "c\(i)"; return (p, try await api.json("GET", p)["path"].str) } }
            var r = [(String, String)](); for try await x in g { r.append(x) }
            return r
        }
        XCTAssertEqual(answers.count, 50)
        XCTAssertTrue(answers.allSatisfy { $0.0 == $0.1 }, "Ответ пришёл не на свой запрос")
        XCTAssertEqual(Set(mine().map(\.path)), Set((0..<50).map { pre + "c\($0)" }))
        XCTAssertEqual(mine().count, 50, "Журнал потерял записи")
    }

    /// Обработчик сам читает журнал (так устроен тест «опоздавшего ответа» этапа H) — вызов идёт вне замка,
    /// взаимной блокировки нет, и обработчик видит уже записанный текущий запрос
    func test05_HandlerMayReadLogWithoutDeadlock() async throws {
        let api = NetStub.api()
        NetStub.reset { _, p in .json(["ok": true, "seen": NetStub.paths().filter { $0 == p }.count]) }
        let first = try await api.json("GET", pre + "state")
        let second = try await api.json("GET", pre + "state")
        XCTAssertEqual(first["seen"].int, 1); XCTAssertEqual(second["seen"].int, 2)
    }
}
