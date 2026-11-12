import Foundation
import SwiftUI

// Состояние магазина в приложении: товары и настройки с сервера, покупатель, корзина, избранное.
// Корзина и избранное хранятся на телефоне; у вошедшего покупателя — ещё и на сервере (видны на сайте и других устройствах).
@MainActor
final class Shop: ObservableObject {
    static let shared = Shop()

    @Published private(set) var loaded = false
    @Published private(set) var loadError: String?
    @Published private(set) var settings = Settings(JSON(nil))
    @Published private(set) var categories: [Category] = []
    @Published private(set) var products: [Product] = []
    @Published private(set) var promotions: [Promotion] = []
    @Published private(set) var sizeCharts: [SizeChart] = []
    @Published private(set) var pages: [Page] = []
    @Published private(set) var hitIds: [String] = []
    @Published private(set) var payReady = false
    @Published private(set) var cdekReady = false
    @Published private(set) var giftCfg = JSON(nil)
    /// Подарочные сертификаты — как на сайте: включены, пока не выключены в панели
    var giftEnabled: Bool { !giftCfg["enabled"].exists || giftCfg["enabled"].bool }
    @Published private(set) var user: User?
    @Published private(set) var isStaff = false
    @Published var cart: [CartLine] = [] { didSet { saveCart() } }
    @Published var favorites: [String] = [] { didSet { saveFavorites() } }
    @Published var gender: String? = UserDefaults.standard.string(forKey: "gender") { didSet { UserDefaults.standard.set(gender, forKey: "gender"); Palette.section = gender } }
    /// «Вы недавно смотрели» — до 12 товаров, новые первыми
    @Published private(set) var recentIds: [String] = UserDefaults.standard.stringArray(forKey: "recent") ?? []
    /// «Купить сейчас»: оформляется только эта вещь, корзина не меняется
    @Published var buyNow: [CartLine]? = nil

    private var cartSync: Task<Void, Never>?
    private var favSync: Task<Void, Never>?

    private init() {
        if let d = UserDefaults.standard.data(forKey: "cart"), let c = try? JSONDecoder().decode([CartLine].self, from: d) { cart = c }
        favorites = UserDefaults.standard.stringArray(forKey: "favorites") ?? []
        Palette.section = gender
        UserDefaults.standard.removeObject(forKey: "gateDone") // экрана выбора раздела больше нет
    }

    // MARK: Загрузка
    func load() async {
        do {
            let j = try await API.shared.json("GET", "state")
            apply(j["data"])
            setUser(User(j["user"]), staff: j["isAdmin"].bool, merge: true)
            loaded = true; loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func apply(_ d: JSON) {
        settings = Settings(d["settings"])
        categories = d["categories"].array.map(Category.init).sorted { $0.order < $1.order }
        products = d["products"].array.map(Product.init).filter { $0.active }
        promotions = d["promotions"].array.map(Promotion.init)
        sizeCharts = d["sizeCharts"].array.map(SizeChart.init)
        pages = d["pages"].array.map(Page.init)
        hitIds = d["hits"].array.compactMap { $0.string }
        payReady = d["payReady"].bool; cdekReady = d["cdekReady"].bool
        giftCfg = d["giftCfg"]
    }

    // MARK: Цены — как на сайте (Pricing.productPrice): лучшая из действующих акций или старая цена
    func price(_ p: Product, now: Date = Date()) -> Price {
        let base = p.price
        var best: Promotion?, bestPrice = base
        for pr in promotions where pr.inWindow(now) && pr.applies(to: p) {
            let v = pr.type == "fixed" ? base - Int(pr.value) : Int((Double(base) * (100 - pr.value) / 100).rounded())
            if max(0, v) < bestPrice { bestPrice = max(0, v); best = pr }
        }
        let old = best != nil ? max(base, p.compareAt) : (p.compareAt > base ? p.compareAt : 0)
        return Price(price: bestPrice, oldPrice: old > bestPrice ? old : 0, promoTitle: best?.title ?? "", promoEnds: best?.endsAt ?? "")
    }

    /// Плашки карточки: «Новинка», «Скидка 15%», «Хит продаж» — тексты и цвета из панели.
    func badges(_ p: Product) -> [(text: String, color: String)] {
        let pr = price(p)
        var out: [(text: String, color: String)] = []
        for k in ["new", "sale", "hit"] {
            let show = k == "sale" ? pr.oldPrice > 0 && !p.badgeOff.contains("sale") : (p.tags.contains(k) || (k == "hit" && hitIds.contains(p.id)))
            guard show, let conf = settings.badges[k] else { continue }
            var text = p.badgeText[k] ?? conf.text
            if k == "sale" { text = text.replacingOccurrences(of: "{n}", with: "\(pr.percent)") }
            if !text.isEmpty { out.append((text: text, color: conf.color)) }
        }
        return out
    }

    func product(_ id: String) -> Product? { id == "FIRST" ? visibleProducts.first { $0.available } ?? products.first : products.first { $0.id == id || $0.slug == id } }
    func category(_ id: String) -> Category? { id == "FIRSTCAT" ? visibleCategories.first : categories.first { $0.id == id || $0.slug == id } }
    /// Для снимков экрана на GitHub: положить в корзину первый товар в наличии
    func demoCart() {
        guard cart.isEmpty, let p = products.first(where: { $0.stock > 0 }), let c = p.colors.first(where: { $0.stock > 0 }), let sz = c.sizes.first(where: { $0.stock > 0 }) else { return }
        add(p, color: c.id, size: sz.size)
    }
    /// Раздел закрыт в панели («скоро появится»): его товары не показываются, на главной — страница «скоро»
    func closed(_ g: String?) -> Bool { g.map { settings.gendersOpen[$0] == false } ?? false }
    var visibleProducts: [Product] { products.filter { $0.forGender(gender) && !closed($0.gender) } }
    var visibleCategories: [Category] {
        let ids = Set(visibleProducts.map(\.categoryId))
        return categories.filter { ids.contains($0.id) }
    }
    var newProducts: [Product] { Array(visibleProducts.filter { $0.tags.contains("new") }.sorted { $0.createdAt > $1.createdAt }.prefix(10)) }
    var hits: [Product] {
        let h = hitIds.compactMap { id in visibleProducts.first { $0.id == id } }
        return h.isEmpty ? Array(visibleProducts.filter { $0.tags.contains("hit") }.prefix(10)) : Array(h.prefix(10))
    }
    var activePromos: [Promotion] { promotions.filter { $0.inWindow(Date()) } }
    /// Сколько бонусов придёт за покупку на эту сумму (как Pricing.bonusFor)
    func bonusFor(_ amount: Int) -> Int { settings.bonusEnabled && settings.bonusPercent > 0 ? max(0, amount) * settings.bonusPercent / 100 : 0 }
    func addRecent(_ id: String) { var r = recentIds.filter { $0 != id }; r.insert(id, at: 0); recentIds = Array(r.prefix(12)); UserDefaults.standard.set(recentIds, forKey: "recent") }
    func clearRecent() { recentIds = []; UserDefaults.standard.removeObject(forKey: "recent") }
    /// Самый низкий порог «Бесплатно от» среди способов доставки — для {free} в строке объявления
    var freeFromMin: Int { settings.delivery.map(\.freeFrom).filter { $0 > 0 }.min() ?? 0 }
    var saleProducts: [Product] { visibleProducts.filter { price($0).oldPrice > 0 } }
    func sizeChart(_ id: String) -> SizeChart? { sizeCharts.first { $0.id == id } }
    func page(_ slug: String) -> Page? { pages.first { $0.slug == slug } }

    // MARK: Корзина
    var cartCount: Int { cart.reduce(0) { $0 + $1.qty } }
    func add(_ p: Product, color: String, size: String, qty: Int = 1) {
        if let i = cart.firstIndex(where: { $0.productId == p.id && $0.colorId == color && $0.size == size }) { cart[i].qty += qty }
        else { cart.append(CartLine(productId: p.id, colorId: color, size: size, qty: qty)) }
    }
    func setQty(_ line: CartLine, _ qty: Int) {
        guard let i = cart.firstIndex(of: line) else { return }
        if qty <= 0 { cart.remove(at: i) } else { cart[i].qty = min(qty, 20) }
    }
    func clearCart() { cart = [] }

    private func saveCart() {
        if let d = try? JSONEncoder().encode(cart) { UserDefaults.standard.set(d, forKey: "cart") }
        guard user != nil else { return }
        cartSync?.cancel()
        let lines = cart.map(\.dict)
        cartSync = Task { try? await Task.sleep(nanoseconds: 800_000_000); guard !Task.isCancelled else { return }; _ = try? await API.shared.raw("PUT", "me/cart", body: ["lines": lines]) }
    }

    // MARK: Избранное
    func isFavorite(_ id: String) -> Bool { favorites.contains(id) }
    func toggleFavorite(_ id: String) {
        if let i = favorites.firstIndex(of: id) { favorites.remove(at: i) } else { favorites.insert(id, at: 0) }
        Haptic.tap()
    }
    private func saveFavorites() {
        UserDefaults.standard.set(favorites, forKey: "favorites")
        guard user != nil else { return }
        favSync?.cancel()
        let list = favorites
        favSync = Task { try? await Task.sleep(nanoseconds: 600_000_000); guard !Task.isCancelled else { return }; _ = try? await API.shared.raw("PUT", "me/favorites", body: ["list": list]) }
    }

    // MARK: Покупатель
    func setUser(_ u: User?, staff: Bool, merge: Bool = false) {
        let was = user?.id
        user = u; isStaff = u != nil && staff
        guard let u, merge || was != u.id else { return }
        // После входа: корзина и избранное с телефона объединяются с сохранёнными в аккаунте
        var c = cart
        for l in u.cart where !c.contains(where: { $0.id == l.id }) { c.append(l) }
        if c != cart { cart = c } else if !u.cart.isEmpty || !cart.isEmpty { saveCart() }
        let f = favorites + u.favorites.filter { !favorites.contains($0) }
        if f != favorites { favorites = f }
        PushManager.shared.resend()
    }
    func refreshUser() async {
        if let j = try? await API.shared.json("GET", "state") { apply(j["data"]); setUser(User(j["user"]), staff: j["isAdmin"].bool) }
    }
    func signedIn(_ j: JSON) {
        setUser(User(j["user"]), staff: j["isAdmin"].bool, merge: true)
        Task { await refreshUser() }
    }
    func logout() async {
        _ = try? await API.shared.raw("POST", "auth/logout")
        API.shared.clearSession()
        user = nil; isStaff = false
        PushManager.shared.resend()
    }
}

enum Haptic {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let notify = UINotificationFeedbackGenerator()
    static func tap() { light.impactOccurred() }
    static func success() { notify.notificationOccurred(.success) }
    static func error() { notify.notificationOccurred(.error) }
}
