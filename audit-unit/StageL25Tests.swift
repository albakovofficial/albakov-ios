import XCTest
import UIKit
@testable import Albakov

// Этап L.2.5: ImageCache — на главном акторе. Загрузку одним разом, повтор из памяти, повтор после сбоя и отмену ждущего
// проверяет ImageCacheTests (этап D, тот же подставной сервер ImageStub). Здесь — ключи, очистка памяти и отмена загружающего.

/// Шлёт предупреждение о нехватке памяти из текущего потока; true — если это главный поток
private func postMemoryWarning() -> Bool {
    NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
    return Thread.isMainThread
}

@MainActor
final class ImageCacheKeyAndPurgeTests: XCTestCase {
    private func cache() -> ImageCache {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [ImageStub.self]
        return ImageCache(configuration: c)
    }
    private func url(_ name: String = UUID().uuidString) throws -> URL { try XCTUnwrap(URL(string: "http://stub.test/\(name).png")) }

    /// Ключ — адрес по значению: экран на каждой отрисовке собирает URL заново (API.shared.url(path)) и находит картинку,
    /// загруженную по другому экземпляру того же адреса. Другой адрес — своя запись и своя загрузка
    func test01_KeyIsURLValue() async throws {
        let c = cache(), name = UUID().uuidString, u = try url(name), other = try url()
        let first = await c.load(u)
        XCTAssertNotNil(first)
        let same = try url(name)
        XCTAssertNotNil(c.cached(same), "Тот же адрес, собранный заново, не нашёл картинку")
        XCTAssertNil(c.cached(other))
        let again = await c.load(same)
        XCTAssertNotNil(again)
        XCTAssertEqual(ImageStub.count(u), 1, "Тот же адрес качался второй раз")
    }

    /// Предупреждение о нехватке памяти (UIKit шлёт его из главного потока) очищает память кэша сразу, до возврата из post;
    /// следующий показ загружает картинку заново и снова кэширует
    func test02_MemoryWarningPurgesAndReloads() async throws {
        let c = cache(), u = try url()
        let first = await c.load(u)
        XCTAssertNotNil(first); XCTAssertNotNil(c.cached(u))
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        XCTAssertNil(c.cached(u), "Память кэша не очистилась сразу")
        let reloaded = await c.load(u)
        XCTAssertNotNil(reloaded, "После очистки картинка не загружается")
        XCTAssertNotNil(c.cached(u))
        XCTAssertEqual(ImageStub.count(u), 2)
    }

    /// Уведомление из другого потока: обработчик выполняется на главной очереди, проверка assumeIsolated не падает,
    /// к продолжению теста память очищена
    func test03_MemoryWarningFromBackgroundThread() async throws {
        let c = cache(), u = try url()
        let first = await c.load(u)
        XCTAssertNotNil(first)
        let posterWasMain = await Task.detached { postMemoryWarning() }.value
        XCTAssertFalse(posterWasMain)
        XCTAssertNil(c.cached(u), "Память кэша не очистилась")
    }

    /// Отменили того, кто начал загрузку (ячейку пролистали): загрузка не прерывается — второй показ получает картинку
    /// без новой загрузки, картинка ложится в кэш
    func test04_CancelledLoaderDoesNotBreakLoad() async throws {
        let c = cache(), u = try url()
        let first = Task { await c.load(u) }
        let started = try await until { ImageStub.count(u) == 1 }
        XCTAssertTrue(started, "Загрузка не началась")
        first.cancel()
        let second = await c.load(u)
        XCTAssertNotNil(second, "Отмена загружающего сорвала загрузку")
        _ = await first.value
        XCTAssertNotNil(c.cached(u))
        XCTAssertEqual(ImageStub.count(u), 1, "После отмены адрес качался ещё раз")
    }
}
