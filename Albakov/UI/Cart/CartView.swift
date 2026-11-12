import SwiftUI

// Корзина как на сайте: заголовок с точкой, строки товаров, справа количество и «Удалить»,
// ниже — карточка суммы с полосой «до бесплатной доставки», итогом, бонусами и «Оформить заказ».
// Цены и наличие считает сервер (POST /api/quote) — те же правила, что на сайте.
struct CartView: View {
    @EnvironmentObject private var shop: Shop
    @EnvironmentObject private var router: Router
    @State private var quote = JSON(nil)
    @State private var loading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DotTitle(text: "Корзина", size: 34).padding(.horizontal, Theme.gutter).padding(.top, 22)
                if shop.cart.isEmpty {
                    EmptyState(icon: "bag", title: "В корзине пока пусто", text: "Загляните в каталог — там новая коллекция", button: "Перейти в каталог") { router.reset(.catalog) }
                        .padding(.top, 22)
                    RecentRow(exceptId: nil, tab: .cart).padding(.top, 40)
                } else {
                    VStack(spacing: 0) { ForEach(shop.cart) { line in CartRow(line: line, q: quoteLine(line)) } }
                        .padding(.horizontal, Theme.gutter).padding(.top, 14)
                    summary.padding(.horizontal, Theme.gutter).padding(.top, 24)
                }
            }.padding(.bottom, 40)
        }
        .task(id: shop.cart) { await recalc() }
    }

    private var summary: some View {
        let sub = quote["subtotal"].int ?? 0, count = quote["count"].int ?? shop.cartCount
        return VStack(alignment: .leading, spacing: 14) {
            FreeShipBar(subtotal: sub)
            row("\(count) \(Fmt.plural(count, "товар", "товара", "товаров"))", Fmt.rub(quote["baseTotal"].int ?? sub))
            if let d = quote["saleDiscount"].int, d > 0 { row("Скидка по акциям", "−" + Fmt.rub(d), Theme.sale) }
            Divider1()
            HStack { Text("Итого").font(Theme.font(19)); Spacer(); Text(Fmt.rub(sub)).font(Theme.font(21, .light)) }
            if let b = quote["bonusEarn"].int, b > 0 {
                HStack(spacing: 8) {
                    Text("Б").font(Theme.font(10, .semibold)).foregroundStyle(.white).frame(width: 17, height: 17).background(Circle().fill(Theme.ink))
                    Text("Бонусы за заказ").font(Theme.font(14)).foregroundStyle(Theme.muted)
                    Spacer()
                    Text("+\(Fmt.num(b)) \(Fmt.plural(b, "бонус", "бонуса", "бонусов"))").font(Theme.font(14, .medium))
                }
            }
            if let u = shop.user, u.bonus > 0, shop.settings.bonusEnabled {
                Text("На бонусном счёте \(Fmt.num(u.bonus)) \(Fmt.plural(u.bonus, "бонус", "бонуса", "бонусов")) — спишете при оформлении").font(Theme.font(13)).foregroundStyle(Theme.muted)
            }
            PrimaryButton(title: "Оформить заказ", busy: loading, disabled: hasProblems) { shop.buyNow = nil; router.push(.checkout, on: .cart) }.padding(.top, 4)
        }
        .padding(22)
        .background(RoundedRectangle(cornerRadius: 24).fill(Theme.surface)).hairline(RoundedRectangle(cornerRadius: 24), 0.06)
    }
    private var hasProblems: Bool { quote["lines"].array.contains { $0["problem"].exists } }
    private func quoteLine(_ l: CartLine) -> JSON { quote["lines"].array.first { $0["productId"].str == l.productId && $0["colorId"].str == l.colorId && $0["size"].str == l.size } ?? JSON(nil) }
    private func row(_ t: String, _ v: String, _ c: Color = Theme.text) -> some View {
        HStack { Text(t).font(Theme.font(15)).foregroundStyle(Theme.muted); Spacer(); Text(v).font(Theme.font(15)).foregroundStyle(c) }
    }
    private func recalc() async {
        guard !shop.cart.isEmpty else { return }
        loading = true
        if let r = try? await API.shared.json("POST", "quote", body: ["lines": shop.cart.map(\.dict)]) { withAnimation { quote = r["quote"] } }
        loading = false
    }
}

/// «Ещё 9 100 ₽ — и доставка бесплатно»: значок грузовика и полоса
struct FreeShipBar: View {
    let subtotal: Int
    @EnvironmentObject private var shop: Shop
    var body: some View {
        let free = shop.freeFromMin
        if free > 0 {
            let left = max(0, free - subtotal)
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "truck.box").font(.system(size: 15, weight: .light)).frame(width: 34, height: 34).background(Circle().fill(.white)).hairline(Circle())
                    if left > 0 { (Text("Ещё ") + Text(Fmt.rub(left)).font(Theme.font(14.5, .semibold)) + Text(" — и доставка бесплатно")).font(Theme.font(14.5)) }
                    else { Text("Доставка будет бесплатной").font(Theme.font(14.5, .medium)).foregroundStyle(Theme.ok) }
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) { Capsule().fill(Theme.surface2); Capsule().fill(Theme.ink).frame(width: g.size.width * min(1, CGFloat(subtotal) / CGFloat(free))) }
                }.frame(height: 4)
                Text("Бесплатно от \(Fmt.rub(free))").font(Theme.font(12.5)).foregroundStyle(Theme.muted)
            }
            .padding(16).background(RoundedRectangle(cornerRadius: 18).fill(Color(hex: "#eef0f2"))).hairline(RoundedRectangle(cornerRadius: 18), 0.06)
        }
    }
}

struct CartRow: View {
    let line: CartLine
    let q: JSON
    var compact = false
    @EnvironmentObject private var shop: Shop
    @EnvironmentObject private var router: Router
    var body: some View {
        let p = shop.product(line.productId)
        let c = p?.color(line.colorId)
        HStack(alignment: .top, spacing: 16) {
            Button { router.push(.product(line.productId)) } label: {
                ProductImage(path: c?.images.first ?? "", kind: c?.artKind ?? "tee", tone: c?.artTone ?? "#3a3632")
                    .frame(width: compact ? 56 : 84, height: compact ? 72 : 112).background(Theme.photo).clipShape(RoundedRectangle(cornerRadius: 12))
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Text(p?.name ?? q["name"].str).font(Theme.font(compact ? 13.5 : 14.5)).lineLimit(2)
                    Spacer(minLength: 8)
                    if !compact { stepper }
                }
                Text(compact ? [c?.name, line.size].compactMap { $0 }.joined(separator: " · ") : "Цвет: \(c?.name ?? "") · Размер: \(line.size)").font(Theme.font(13)).foregroundStyle(Theme.muted)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let pr = q["price"].int {
                        Text(Fmt.rub(pr * line.qty)).font(Theme.font(15)).foregroundStyle((q["oldPrice"].int ?? 0) > 0 ? Theme.sale : Theme.text)
                        if let o = q["oldPrice"].int, o > 0 { Text(Fmt.rub(o * line.qty)).font(Theme.font(13)).strikethrough().foregroundStyle(Theme.dim) }
                    } else if let p { PriceView(price: shop.price(p)) }
                    Spacer()
                    if !compact { Button { withAnimation { shop.setQty(line, 0) } } label: { Text("Удалить").font(Theme.font(13.5)).foregroundStyle(Theme.muted) } }
                }
                if compact {
                    HStack(spacing: 14) { stepper; Button { withAnimation { shop.setQty(line, 0) } } label: { Text("Убрать").font(Theme.font(13)).foregroundStyle(Theme.muted).underline() } }
                }
                if let problem = q["problem"].string { Text(problem).font(Theme.font(12.5, .medium)).foregroundStyle(Theme.danger) }
            }
        }
        .padding(.vertical, 16).overlay(alignment: .bottom) { Divider1() }
    }
    private var stepper: some View {
        HStack(spacing: 0) {
            Button { Haptic.tap(); withAnimation { shop.setQty(line, line.qty - 1) } } label: { Image(systemName: "minus").frame(width: 30, height: 32) }
            Text("\(line.qty)").font(Theme.font(15)).frame(minWidth: 20)
            Button { Haptic.tap(); withAnimation { shop.setQty(line, line.qty + 1) } } label: { Image(systemName: "plus").frame(width: 30, height: 32) }
        }
        .font(.system(size: 10, weight: .light)).foregroundStyle(Theme.text)
        .background(Capsule().fill(.white)).overlay(Capsule().strokeBorder(Theme.lineStrong))
    }
}
