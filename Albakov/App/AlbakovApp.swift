import SwiftUI

// ALBAKOV для iPhone: магазин albakovofficial.ru внутри приложения + то, чего сайт в браузере не умеет:
// push-уведомления Apple, системное «Поделиться», виброотклик, число на значке, ссылки albakovofficial.ru сразу в приложении.
@main
struct AlbakovApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var router = Router.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(router)
                .onOpenURL { url in router.open(url) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { router.open(url) }
                }
        }
    }
}

// Куда перейти: ссылка albakovofficial.ru (из письма, мессенджера), нажатие на push, адрес albakov://…
final class Router: ObservableObject {
    static let shared = Router()

    let baseURL: URL
    @Published var pendingURL: URL?

    private init() {
        let raw = Bundle.main.object(forInfoDictionaryKey: "AlbakovBaseURL") as? String ?? "https://albakovofficial.ru"
        baseURL = URL(string: raw) ?? URL(string: "https://albakovofficial.ru")!
    }

    func open(_ url: URL) {
        if url.scheme == "albakov" {
            // albakov://product/futbolka → https://albakovofficial.ru/product/futbolka
            let path = "/" + [url.host, url.path].compactMap { $0 }.joined().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            open(path: path + (url.query.map { "?" + $0 } ?? ""))
        } else if isInternal(url) {
            pendingURL = url
        }
    }

    func open(path: String) {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL, isInternal(url) else { return }
        pendingURL = url
    }

    func isInternal(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(), let base = baseURL.host?.lowercased() else { return false }
        return host == base || host == "www." + base
    }
}
