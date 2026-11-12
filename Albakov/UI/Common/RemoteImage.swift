import SwiftUI
import UIKit

// Картинки с сайта с кэшем в памяти и на диске (URLCache): каталог листается без повторной загрузки фото.
final class ImageCache {
    static let shared = ImageCache()
    private let memory = NSCache<NSURL, UIImage>()
    private let session: URLSession
    private var running: [URL: Task<UIImage?, Never>] = [:]
    private let lock = NSLock()

    private init() {
        memory.totalCostLimit = 80 * 1024 * 1024
        let c = URLSessionConfiguration.default
        c.urlCache = URLCache(memoryCapacity: 16 * 1024 * 1024, diskCapacity: 300 * 1024 * 1024)
        c.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: c)
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil) { [weak self] _ in self?.memory.removeAllObjects() }
    }

    func cached(_ url: URL) -> UIImage? { memory.object(forKey: url as NSURL) }

    func load(_ url: URL) async -> UIImage? {
        if let i = cached(url) { return i }
        lock.lock()
        if let t = running[url] { lock.unlock(); return await t.value }
        let t = Task<UIImage?, Never> { [session] in
            guard let (data, _) = try? await session.data(from: url), let img = UIImage(data: data) else { return nil }
            return await Task.detached(priority: .userInitiated) { img.preparingForDisplay() ?? img }.value
        }
        running[url] = t
        lock.unlock()
        let img = await t.value
        lock.lock(); running[url] = nil; lock.unlock()
        if let img { memory.setObject(img, forKey: url as NSURL, cost: Int(img.size.width * img.size.height * img.scale * img.scale * 4)) }
        return img
    }
}

struct RemoteImage: View {
    let path: String
    var contentMode: ContentMode = .fill
    @State private var image: UIImage?

    var body: some View {
        let url = API.shared.url(path)
        ZStack {
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
