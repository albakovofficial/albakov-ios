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

/// Карточка на странице заказа: «Заказ ждёт оплаты» + 14:32 + полоса в цвете раздела
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
                Text(left <= 0 ? "Время вышло — проверяем, не прошла ли оплата…" : hot ? "Меньше 5 минут — потом заказ отменится, а вещи вернутся в продажу" : "Если не оплатить, заказ отменится, а вещи вернутся в продажу")
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

/// Время вышло: заказ отменён, «Оформить заново» кладёт вещи обратно в корзину
struct PayExpiredCard: View {
    let order: Order
    @EnvironmentObject private var shop: Shop
    @EnvironmentObject private var router: Router
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "clock.badge.xmark").font(.system(size: 20, weight: .light)).foregroundStyle(Theme.muted)
                    .frame(width: 42, height: 42).background(Circle().fill(Theme.surface))
                Text("Время на оплату вышло").font(Theme.font(17, .medium))
            }
            Text("Заказ отменён, вещи вернулись в продажу. Оформите заново — если они ещё в наличии, они сразу окажутся в корзине.")
                .font(Theme.font(13.5)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            PrimaryButton(title: "Оформить заново") { again() }
        }.padding(18).softCard(20)
    }
    private func again() {
        var n = 0
        for it in order.items {
            guard let p = shop.products.first(where: { $0.id == it.productId && $0.active }),
                  let c = p.colors.first(where: { $0.id == it.colorId }),
                  let z = c.sizes.first(where: { $0.size == it.size }), z.stock > 0 else { continue }
            shop.add(p, color: c.id, size: it.size, qty: min(it.qty, z.stock)); n += 1
        }
        if n == 0 { Toast.shared.show("Эти вещи уже закончились"); return }
        Toast.shared.show(n < order.items.count ? "Часть вещей уже закончилась — остальные в корзине" : "Вещи снова в корзине")
        router.reset(.cart)
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
