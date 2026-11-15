import SwiftUI

/* Время на оплату (1.0.3): 10 минут — как у страницы ЮKassa, отсчёт от создания платежа по часам сервера.
   Последние 5 минут — красным. Время вышло — сервер отменяет заказ и возвращает вещи в продажу,
   а здесь появляется «Оформить заново»: вещи, которые ещё в наличии, снова в корзине. */

enum PayClock {
    static let window: TimeInterval = 10 * 60
    static let hot: TimeInterval = 5 * 60
    static let red = Color(hex: "#b42318")
    static func mmss(_ s: TimeInterval) -> String { let t = max(0, Int(s.rounded(.up))); return String(format: "%02d:%02d", t / 60, t % 60) }
    static func left(_ o: Order, _ now: Date) -> TimeInterval { o.payLeft(at: now, skew: ServerClock.skew) }
    /// Ждёт оплаты и время ещё есть
    static func open(_ o: Order, _ now: Date) -> Bool { o.awaitingPay && o.payBy != nil && left(o, now) > 0 }
}

/// Карточка на странице заказа: «Заказ ждёт оплаты» + 08:35 + полоса, «Проверьте заказ» и «Оплатить»
struct PayTimerCard: View {
    let order: Order
    let onPay: () -> Void
    let onExpire: () -> Void
    @State private var fired = false
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let left = PayClock.left(order, ctx.date)
            let hot = left <= PayClock.hot
            let tone = hot ? PayClock.red : Theme.accent
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Заказ ждёт оплаты").font(Theme.font(17, .medium))
                        Text("Вещи отложены за вами").font(Theme.font(13)).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(PayClock.mmss(left)).font(Theme.font(28, .light)).monospacedDigit().foregroundStyle(tone)
                        Text("осталось").font(Theme.font(11.5)).foregroundStyle(hot ? tone : Theme.muted)
                    }
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(tone.opacity(0.14))
                        Capsule().fill(tone).frame(width: g.size.width * max(0, min(1, left / PayClock.window)))
                    }
                }.frame(height: 5)
                PayCheckList(order: order)
                Text(left <= 0 ? "Время вышло — проверяем, не прошла ли оплата…" : hot ? "Меньше 5 минут — потом заказ отменится, а вещи вернутся в корзину" : "Не успеете — заказ отменится, а вещи вернутся в вашу корзину")
                    .font(Theme.font(12.5)).foregroundStyle(hot ? tone : Theme.muted).fixedSize(horizontal: false, vertical: true)
                if left > 0 { PrimaryButton(title: "Оплатить · \(Fmt.rub(order.total))", action: onPay) }
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 20).fill(hot ? Color(hex: "#fdf3f2") : .white))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(hot ? PayClock.red.opacity(0.22) : Theme.ink.opacity(0.08), lineWidth: 1))
            .animation(.easeInOut(duration: 0.4), value: hot)
            .onChange(of: left <= -75) { gone in if gone && !fired { fired = true; onExpire() } }   // сервер ждёт ЮKassa минуту и отменяет — обновим заказ
        }
    }
}

/// «Проверьте перед оплатой»: что в заказе, куда везём и кто получает — чтобы не платить за ошибку
struct PayCheckList: View {
    let order: Order
    var body: some View {
        let n = order.items.reduce(0) { $0 + $1.qty }
        let where_ = [order.city, order.address].filter { !$0.isEmpty }.joined(separator: ", ")
        let names = order.items.reduce(into: [String]()) { if !$0.contains($1.name) { $0.append($1.name) } }
        let grouped = names.map { n in n + " · " + order.items.filter { $0.name == n }.map(\.size).joined(separator: ", ") }.joined(separator: "; ")
        VStack(alignment: .leading, spacing: 10) {
            Text("ПРОВЕРЬТЕ ПЕРЕД ОПЛАТОЙ").font(Theme.font(10.5, .medium)).kerning(1.1).foregroundStyle(Theme.muted)
            row("bag", "\(n) \(Fmt.plural(n, "вещь", "вещи", "вещей")) · \(Fmt.rub(order.total))", grouped)
            row("shippingbox", order.deliveryName.isEmpty ? "Доставка" : order.deliveryName, where_)
            row("person", order.customerName, Fmt.phone(order.phone))
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
    }
    private func row(_ icon: String, _ title: String, _ sub: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon).font(.system(size: 13.5, weight: .regular)).foregroundStyle(Theme.text).frame(width: 30, height: 30).background(Circle().fill(.white))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Theme.font(14, .medium)).lineLimit(1)
                if !sub.isEmpty { Text(sub).font(Theme.font(12.5)).foregroundStyle(Theme.muted).lineLimit(2) }
            }
            Spacer(minLength: 0)
        }
    }
}

/// Время вышло: заказ отменён, вещи сами возвращаются в корзину (один раз, без задвоения) — остаётся оформить заново
struct PayExpiredCard: View {
    let order: Order
    @EnvironmentObject private var shop: Shop
    @EnvironmentObject private var router: Router
    var body: some View {
        let back = order.items.filter { it in shop.cart.contains { $0.productId == it.productId && $0.colorId == it.colorId && $0.size == it.size } }.count
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "clock.badge.xmark").font(.system(size: 20, weight: .light)).foregroundStyle(Theme.muted)
                    .frame(width: 42, height: 42).background(Circle().fill(Theme.surface))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Время на оплату вышло").font(Theme.font(17, .medium))
                    Text("Заказ № \(order.number) отменён").font(Theme.font(13)).foregroundStyle(Theme.muted)
                }
            }
            Text(back == 0 ? "Эти вещи уже разобрали — загляните в каталог, там много нового." :
                 back < order.items.count ? "Вещи, которые ещё в наличии, вернулись в вашу корзину. Остальные уже разобрали." :
                 "Вещи вернулись в вашу корзину — оформите заказ заново, пока они в наличии.")
                .font(Theme.font(13.5)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            if back > 0 { PrimaryButton(title: "Перейти в корзину") { router.reset(.cart) } }
            else { GhostButton(title: "В каталог") { router.reset(.catalog) } }
        }
        .padding(18).softCard(20)
        .onAppear { shop.returnExpired(order) }
    }
}

/// Фото вещей стопкой; без фото — рисунок вещи
struct OrderThumbs: View {
    let items: [OrderItem]
    var w: CGFloat = 52
    var body: some View {
        let shown = Array(items.prefix(3))
        ZStack(alignment: .leading) {
            ForEach(Array(shown.enumerated().reversed()), id: \.offset) { i, it in
                ProductImage(path: it.image, kind: it.artKind, tone: it.artTone)
                    .frame(width: w, height: w * 4 / 3).background(Theme.photo)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white, lineWidth: i == 0 ? 0 : 2))
                    .offset(x: CGFloat(i) * w * 0.36)
            }
        }
        .frame(width: w + CGFloat(max(0, shown.count - 1)) * w * 0.36, alignment: .leading)
    }
}

/// «Не оплачен · осталось 12:48» — живой отсчёт в строке заказа
struct PayLeftLabel: View {
    let order: Order
    var prefix = "Не оплачен · осталось "
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let left = PayClock.left(order, ctx.date)
            if left > 0 {
                (Text(prefix) + Text(PayClock.mmss(left)).monospacedDigit().fontWeight(.semibold))
                    .font(Theme.font(12)).foregroundStyle(left <= PayClock.hot ? PayClock.red : Theme.danger)
            } else {
                Text("Время на оплату вышло").font(Theme.font(12)).foregroundStyle(Theme.muted)
            }
        }
    }
}

/// Капсула «Оплатить · осталось 12:48» для карточки в «Моих заказах»
struct PayNowButton: View {
    let order: Order
    let action: () -> Void
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let left = PayClock.left(order, ctx.date)
            let hot = left <= PayClock.hot
            Button(action: { Haptic.tap(); action() }) {
                HStack(spacing: 5) {
                    Text("Оплатить · осталось")
                    Text(PayClock.mmss(left)).monospacedDigit().fontWeight(.semibold)
                }
                .font(Theme.font(13.5, .medium)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 42)
                .background(Capsule().fill(hot ? AnyShapeStyle(PayClock.red) : AnyShapeStyle(Theme.accentGradient)))
            }
            .buttonStyle(Pressable())
            .disabled(left <= 0)
            .opacity(left <= 0 ? 0.4 : 1)
        }
    }
}
