import SwiftUI
import UIKit
import os

// Картинки с сайта с кэшем в памяти и на диске (URLCache): каталог листается без повторной загрузки фото.
// Одинаковые адреса, запрошенные разом (сетка каталога, карточка и её миниатюра), качаются один раз:
// второй и следующие ждут ту же загрузку (running). load вызывается из разных потоков —
// список загрузок под OSAllocatedUnfairLock.withLock: NSLock.lock()/unlock() в async-коде — ошибка в Swift 6 (аудит Q-B3).
// Под замком нет await, внутри — только чтение и запись словаря: взаимной блокировки быть не может.
final class ImageCache {
    static let shared = ImageCache()
    private let memory = NSCache<NSURL, UIImage>()
    private let session: URLSession
    private let running = OSAllocatedUnfairLock(initialState: [URL: Task<UIImage?, Never>]())

    /// configuration — только для тестов (подставной URLProtocol); приложение берёт обычную, кэш на диске тот же
    init(configuration c: URLSessionConfiguration = .default) {
        memory.totalCostLimit = 80 * 1024 * 1024
        c.urlCache = URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: 300 * 1024 * 1024)
        c.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: c)
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil) { [weak self] _ in self?.memory.removeAllObjects() }
    }

    func cached(_ url: URL) -> UIImage? { memory.object(forKey: url as NSURL) }

    /// Отмена того, кто ждёт, загрузку не прерывает: она нужна и другим ждущим, и следующему показу (картинка ляжет в кэш)
    func load(_ url: URL) async -> UIImage? {
        if let i = cached(url) { return i }
        if let t = running.withLock({ $0[url] }) { return await t.value }
        // Между первой проверкой и замком загрузка этого адреса могла закончиться: картинка уже в кэше (её кладут туда раньше,
        // чем убирают загрузку из списка) — второй раз не качаем
        if let i = cached(url) { return i }
        let session = self.session
        let (task, mine) = running.withLock { running -> (Task<UIImage?, Never>, Bool) in
            if let t = running[url] { return (t, false) }
            let t = Task<UIImage?, Never> {
                guard let (data, _) = try? await session.data(from: url), let img = UIImage(data: data) else { return nil }
                return await Task.detached(priority: .userInitiated) { img.preparingForDisplay() ?? img }.value
            }
            running[url] = t
            return (t, true)
        }
        let img = await task.value
        if mine {
            if let img { memory.setObject(img, forKey: url as NSURL, cost: Int(img.size.width * img.size.height * img.scale * img.scale * 4)) }
            running.withLock { $0[url] = nil }   // после кэша: иначе в промежутке тот же адрес начал бы качаться второй раз
        }
        return img
    }
}

struct RemoteImage: View {
    let path: String
    var contentMode: ContentMode = .fill
    @State private var image: UIImage?

    var body: some View {
        let url = API.shared.url(path)
        // Фото занимает ровно отведённое место: при заполнении лишнее обрезается и не раздвигает карточку
        Color.clear.overlay {
            if let img = image ?? url.flatMap({ ImageCache.shared.cached($0) }) {
                Image(uiImage: img).resizable().aspectRatio(contentMode: contentMode).transition(.opacity)
            } else {
                Placeholder()
            }
        }
        .clipped()
        .task(id: path) {
            guard let url else { image = nil; return }
            if let c = ImageCache.shared.cached(url) { image = c; return }
            image = nil
            let i = await ImageCache.shared.load(url)
            // путь сменился, пока картинка грузилась (.task(id:) отменил эту задачу): старая картинка не должна лечь поверх новой
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { image = i }
        }
    }
}

/// Пока фото нет: мягкий серый фон и знак AV
struct Placeholder: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: "#eef0f2"), Color(hex: "#e2e5e9")], startPoint: .top, endPoint: .bottom)
            Image("Logo").resizable().scaledToFit().frame(width: 36).opacity(0.12)
        }
    }
}
