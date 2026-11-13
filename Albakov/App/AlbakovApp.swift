import SwiftUI

// ALBAKOV для iPhone — родное приложение: экраны рисует приложение, данные (товары, корзина, заказы, оплата, панель)
// берёт с того же сервера, что и сайт albakovofficial.ru.
@main
struct AlbakovApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var router = Router.shared
    @StateObject private var shop = Shop.shared

    init() { Theme.setupAppearance() }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(router)
                .environmentObject(shop)
                .onOpenURL { router.open($0) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { a in if let u = a.webpageURL { router.open(u) } }
                .preferredColorScheme(.light)
        }
    }
}

enum Tab: Hashable { case home, catalog, favorites, cart, account }

// Куда можно перейти внутри вкладки
enum Dest: Hashable {
    case product(String)
    case catalog(cat: String?, tag: String?, sale: Bool)
    case search
    case page(String)
    case gift
    case track
    case checkout
    case orders
    case order(String)
    case support
    case ticket(String)
    case bonus
    case profile
    case notifications
    case admin
    case adminOrders
    case adminOrder(String)
    case adminSupport
    case adminTicket(String)
    case adminProducts
    case adminProduct(String)
    case adminPush
    case adminAudit
    case adminCustomers
    case adminSection(String)          // раздел панели по ключу, как ?s=… на сайте
    case adminItem(String, String)     // запись коллекции: (categories, id) …
}

// Ссылки albakovofficial.ru (письма, push, мессенджеры), albakov://… и внутренние ссылки из слайдов
final class Router: ObservableObject {
    static let shared = Router()

    @Published var tab: Tab = .home
    @Published var menuOpen = false
    @Published var home: [Dest] = []
    @Published var catalog: [Dest] = []
    @Published var favorites: [Dest] = []
    @Published var cart: [Dest] = []
    @Published var account: [Dest] = []

    func binding(_ t: Tab) -> Binding<[Dest]> {
        switch t {
        case .home: return Binding(get: { self.home }, set: { self.home = $0 })
        case .catalog: return Binding(get: { self.catalog }, set: { self.catalog = $0 })
        case .favorites: return Binding(get: { self.favorites }, set: { self.favorites = $0 })
        case .cart: return Binding(get: { self.cart }, set: { self.cart = $0 })
        case .account: return Binding(get: { self.account }, set: { self.account = $0 })
        }
    }

    func push(_ d: Dest, on t: Tab? = nil) {
        let target = t ?? tab
        tab = target
        switch target {
        case .home: home.append(d)
        case .catalog: catalog.append(d)
        case .favorites: favorites.append(d)
        case .cart: cart.append(d)
        case .account: account.append(d)
        }
    }
    func pop(on t: Tab) {
        switch t {
        case .home: if !home.isEmpty { home.removeLast() }
        case .catalog: if !catalog.isEmpty { catalog.removeLast() }
        case .favorites: if !favorites.isEmpty { favorites.removeLast() }
        case .cart: if !cart.isEmpty { cart.removeLast() }
        case .account: if !account.isEmpty { account.removeLast() }
        }
    }
    func reset(_ t: Tab, to list: [Dest] = []) {
        switch t {
        case .home: home = list
        case .catalog: catalog = list
        case .favorites: favorites = list
        case .cart: cart = list
        case .account: account = list
        }
        tab = t
    }

    func open(_ url: URL) {
        if url.scheme == "albakov" {
            open(path: "/" + [url.host, url.path].compactMap { $0 }.joined() + (url.query.map { "?" + $0 } ?? ""))
        } else if let h = url.host?.lowercased(), h.hasSuffix("albakovofficial.ru") {
            open(path: url.path + (url.query.map { "?" + $0 } ?? ""))
        } else {
            UIApplication.shared.open(url)
        }
    }

    /// Адрес сайта → экран приложения: «/product/…», «#/catalog?cat=…», «/order/…», «/account?tab=support», «/admin?s=orders&id=…»
    func open(path raw: String) {
        if raw.hasPrefix("http"), let u = URL(string: raw) { open(u); return }
        var s = raw
        if s.hasPrefix("#") { s.removeFirst() }
        if !s.hasPrefix("/") { s = "/" + s }
        let comps = URLComponents(string: s)
        let parts = (comps?.path ?? s).split(separator: "/").map(String.init)
        let q = Dictionary((comps?.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        switch parts.first ?? "" {
        case "product" where parts.count > 1: push(.product(parts[1]), on: tab == .account ? .home : tab)
        case "catalog": reset(.catalog, to: (q["cat"] != nil || q["tag"] != nil) ? [.catalog(cat: q["cat"], tag: q["tag"], sale: false)] : [])
        case "sale": reset(.catalog, to: [.catalog(cat: nil, tag: nil, sale: true)])
        case "favorites": reset(.favorites)
        case "menu": menuOpen = true
        case "cart": reset(.cart)
        case "checkout": reset(.cart, to: [.checkout])
        case "order" where parts.count > 1: reset(.account, to: [.orders, .order(parts[1])])
        case "page" where parts.count > 1: push(.page(parts[1]))
        case "sizes": reset(.catalog)   // общей таблицы размеров нет — у каждого товара своя
        case "gift": push(.gift, on: tab == .account ? .account : .home)
        case "track": push(.track, on: tab == .account ? .account : .home)
        case "account":
            switch q["tab"] ?? "" {
            case "support": reset(.account, to: q["id"].map { [.support, .ticket($0)] } ?? [.support])
            case "bonus": reset(.account, to: [.bonus])
            case "orders": reset(.account, to: [.orders])
            case "profile": reset(.account, to: [.profile])
            default: reset(.account)
            }
        case "admin":
            let id = q["id"]
            switch q["s"] ?? "" {
            case "orders": reset(.account, to: [.admin, .adminOrders] + (id.map { [.adminOrder($0)] } ?? []))
            case "support": reset(.account, to: [.admin, .adminSupport] + (id.map { [.adminTicket($0)] } ?? []))
            case "products": reset(.account, to: [.admin, .adminProducts] + (id.map { [.adminProduct($0)] } ?? []))
            case "audit": reset(.account, to: [.admin, .adminAudit])
            case "push": reset(.account, to: [.admin, .adminPush])
            case "customers": reset(.account, to: [.admin, .adminCustomers])
            case "": reset(.account, to: [.admin])
            case let k:
                // любой другой раздел панели сайта: категории, акции, финансы, обмен…; id — конкретная запись
                if let id, AdminSections.collectionKeys.contains(k) { reset(.account, to: [.admin, .adminSection(k), .adminItem(k, id)]) }
                else { reset(.account, to: [.admin, .adminSection(k)]) }
            }
        default: reset(.home)
        }
    }
}
