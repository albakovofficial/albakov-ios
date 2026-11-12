import SwiftUI

// Корзина: цены и наличие считает сервер (POST /api/quote) — те же правила, что на сайте
struct CartView: View {
    @EnvironmentObject private var shop: Shop
    @EnvironmentObject private var router: Router
    @State private var quote = JSON(nil)
    @State private var loading = false

    var body: some View {
        Group {
            if shop.cart.isEmpty {
                ScrollView { EmptyState(icon: "bag", title: "Корзина пуста", text: "Загляните в каталог — там новая коллекция", button: "В каталог") { router.reset(.catalog) }.padding(.top, 60) }
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(shop.cart) { line in CartRow(line: line, q: quoteLine(line)) }
                    }.padding(.horizontal, Theme.gutter)
                    VStack(spacing: 10) {
                        sumRow("Товары", Fmt.rub(quote["baseTotal"].int ?? quote["subtotal"].int ?? 0))
                        if let d = quote["saleDiscount"].int, d > 0 { sumRow("Скидка", "−" + Fmt.rub(d), Theme.danger) }
                        Divider1()
                        HStack { Text("Итого").font(Theme.font(18, .medium)); Spacer(); Text(Fmt.rub(quote["subtotal"].int ?? 0)).font(Theme.font(18, .medium)) }
                        if let b = quote["bonusEarn"].int, b > 0 { Text("+\(b) бонусов за заказ").font(Theme.font(13)).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading) }
                        Text("Доставка и промокод — на следующем шаге").font(Theme.font(12.5)).foregroundStyle(Theme.dim).frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(Theme.gutter).padding(.bottom, 100)
                }
                .overlay(alignment: .bottom) {
                    PrimaryButton(title: "Оформить заказ", icon: "arrow.right", busy: loading, disabled: hasProblems) { router.push(.checkout, on: .cart) }
                        .padding(.horizontal, Theme.gutter).padding(.vertical, 10).background(.ultraThinMaterial)
                }
            }
        }
        .navigationTitle("Корзина").navigationBarTitleDisplayMode(.inline)
        .task(id: shop.cart) { await recalc() }
    }

    private var hasProblems: Bool { quote["lines"].array.contains { $0["problem"].exists } }
    private func quoteLine(_ l: CartLine) -> JSON { quote["lines"].array.first { $0["productId"].str == l.productId && $0["colorId"].str == l.colorId && $0["size"].str == l.size } ?? JSON(nil) }
    private func sumRow(_ t: String, _ v: String, _ c: Color = Theme.text) -> some View {
        HStack { Text(t).font(Theme.font(15)).foregroundStyle(Theme.muted); Spacer(); Text(v).font(Theme.font(15)).foregroundStyle(c) }
    }
    private func recalc() async {
        guard !shop.cart.isEmpty else { return }
        loading = true
        if let r = try? await API.shared.json("POST", "quote", body: ["lines": shop.cart.map(\.dict)]) { withAnimation { quote = r["quote"] } }
        loading = false
    }
}

struct CartRow: View {
    let line: CartLine
    let q: JSON
    @EnvironmentObject private var shop: Shop
    @EnvironmentObject private var router: Router
    var body: some View {
        let p = shop.product(line.productId)
        let c = p?.color(line.colorId)
        HStack(alignment: .top, spacing: 14) {
            Button { router.push(.product(line.productId), on: .cart) } label: {
                RemoteImage(path: c?.images.first ?? p?.image ?? "").frame(width: 92, height: 122).clipShape(RoundedRectangle(cornerRadius: 14))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(p?.name ?? q["name"].str).font(Theme.font(14.5)).lineLimit(2)
                Text([c?.name, "размер " + line.size].compactMap { $0 }.joined(separator: " · ")).font(Theme.font(13)).foregroundStyle(Theme.muted)
                if let pr = q["price"].int {
                    HStack(spacing: 6) {
                        Text(Fmt.rub(pr * line.qty)).font(Theme.font(15, .medium)).foregroundStyle(q["oldPrice"].int ?? 0 > 0 ? Theme.danger : Theme.text)
                        if let o = q["oldPrice"].int, o > 0 { Text(Fmt.rub(o * line.qty)).font(Theme.font(13)).strikethrough().foregroundStyle(Theme.dim) }
                    }
                } else if let p { PriceView(price: shop.price(p)) }
                if let problem = q["problem"].string { Text(problem).font(Theme.font(12.5, .medium)).foregroundStyle(Theme.danger) }
                HStack(spacing: 0) {
                    stepBtn("minus") { shop.setQty(line, line.qty - 1) }
                    Text("\(line.qty)").font(Theme.font(15, .medium)).frame(width: 34)
                    stepBtn("plus") { shop.setQty(line, line.qty + 1) }
                    Spacer()
                    Button { withAnimation { shop.setQty(line, 0) } } label: { Image(systemName: "trash").font(.system(size: 14)).foregroundStyle(Theme.dim) }
                }.padding(.top, 4)
            }
        }
        .padding(.vertical, 14).overlay(alignment: .bottom) { Divider1() }
    }
    private func stepBtn(_ icon: String, _ a: @escaping () -> Void) -> some View {
        Button { Haptic.tap(); withAnimation { a() } } label: { Image(systemName: icon).font(.system(size: 12, weight: .medium)).frame(width: 34, height: 34).background(Circle().strokeBorder(Theme.line)) }.foregroundStyle(Theme.text)
    }
}
