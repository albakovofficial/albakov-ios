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
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Заказ ждёт оплаты").font(Theme.font(17, .medium))
                        Text("Вещи отложены за вами").font(Theme.font(13)).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    PayRing(left: left, hot: hot, tone: tone)
                }
                PayCheckList(order: order)
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: hot ? "exclamationmark.circle" : "arrow.uturn.backward.circle").font(.system(size: 13, weight: .regular)).padding(.top, 1)
                    Text(left <= 0 ? "Время вышло — проверяем, не прошла ли оплата…" : hot ? "Меньше 5 минут — потом заказ отменится, а вещи вернутся в корзину" : "Не успеете — заказ отменится, а вещи вернутся в вашу корзину")
                        .font(Theme.font(12.5)).fixedSize(horizontal: false, vertical: true)
                }.foregroundStyle(hot ? tone : Theme.muted)
                if left > 0 { PrimaryButton(title: "Оплатить · \(Fmt.rub(order.total))", action: onPay) }
            }
            .padding(20)
            // фон всегда белый — краснеют только кольцо, тонкая рамка и подсказка
            .background(RoundedRectangle(cornerRadius: 22).fill(.white).shadow(color: Theme.ink.opacity(0.06), radius: 18, y: 8))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(hot ? PayClock.red.opacity(0.35) : Theme.ink.opacity(0.07), lineWidth: hot ? 1.2 : 1))
            .animation(.easeInOut(duration: 0.4), value: hot)
            .onChange(of: left <= -75) { gone in if gone && !fired { fired = true; onExpire() } }   // сервер ждёт ЮKassa минуту и отменяет — обновим заказ
        }
    }
}

/// Таймер оплаты — кольцо в цвете раздела: тает вместе со временем; последние 5 минут — красное и мягко пульсирует
struct PayRing: View {
    let left: TimeInterval, hot: Bool, tone: Color
    @Environment(\.accessibilityReduceMotion) private var still
    var body: some View {
        let frac = max(0, min(1, left / PayClock.window))
        let beat = hot && !still && Int(left.rounded(.up)) % 2 == 0
        ZStack {
            Circle().fill(RadialGradient(colors: [tone.opacity(hot ? 0.10 : 0.05), .clear], center: .init(x: 0.5, y: 0.4), startRadius: 0, endRadius: 54))
            Circle().stroke(tone.opacity(0.14), lineWidth: 5)
            Circle().trim(from: 0, to: frac).stroke(tone, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: frac)
            Circle().stroke(tone.opacity(beat ? 0.10 : 0), lineWidth: 8).padding(-6).animation(.easeInOut(duration: 0.9), value: beat)
            VStack(spacing: 3) {
                Text(PayClock.mmss(left)).font(Theme.font(23)).monospacedDigit().foregroundStyle(hot ? tone : Theme.text)
                Text("осталось").font(Theme.font(10.5)).kerning(0.5).foregroundStyle(hot ? tone : Theme.muted)
            }
        }
        .frame(width: 104, height: 104)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Осталось \(Int(max(0, left)) / 60) мин \(Int(max(0, left)) % 60) с на оплату")
    }
}

/// «Проверьте перед оплатой»: что в заказе, куда везём и кто получает — список с тонкими линиями, без серой подложки
struct PayCheckList: View {
    let order: Order
    var body: some View {
        let n = order.items.reduce(0) { $0 + $1.qty }
        let where_ = [order.city, order.address].filter { !$0.isEmpty }.joined(separator: ", ")
        let names = order.items.reduce(into: [String]()) { if !$0.contains($1.name) { $0.append($1.name) } }
        let grouped = names.map { n in n + " · " + order.items.filter { $0.name == n }.map(\.size).joined(separator: ", ") }.joined(separator: "; ")
        VStack(alignment: .leading, spacing: 0) {
            Text("ПРОВЕРЬТЕ ПЕРЕД ОПЛАТОЙ").font(Theme.font(10.5, .medium)).kerning(1.1).foregroundStyle(Theme.dim).padding(.bottom, 4)
            row("bag", "\(n) \(Fmt.plural(n, "вещь", "вещи", "вещей")) · \(Fmt.rub(order.total))", grouped)
            Divider().padding(.leading, 46)
            row("shippingbox", order.deliveryName.isEmpty ? "Доставка" : order.deliveryName, where_)
            Divider().padding(.leading, 46)
            row("person", order.customerName, Fmt.phone(order.phone))
        }
        .padding(.top, 14)
        .overlay(alignment: .top) { Rectangle().fill(Theme.ink.opacity(0.07)).frame(height: 1) }
    }
    private func row(_ icon: String, _ title: String, _ sub: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 14, weight: .light)).foregroundStyle(Theme.text)
                .frame(width: 34, height: 34).background(Circle().fill(Theme.surface))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.font(14.5, .medium)).lineLimit(1)
                if !sub.isEmpty { Text(sub).font(Theme.font(12.5)).foregroundStyle(Theme.muted).lineLimit(2).fixedSize(horizontal: false, vertical: true) }
            }.padding(.top, 1)
            Spacer(minLength: 0)
        }.padding(.vertical, 10)
    }
}

/// Время вышло: заказ отменён, вещи в наличии уже в корзине — «Перейти в корзину»; если всё разобрали — «В каталог»
struct PayExpiredCard: View {
    let order: Order
    @EnvironmentObject private var shop: Shop
    @EnvironmentObject private var router: Router
    var body: some View {
        let back = order.items.filter { shop.expiredAvailable($0) > 0 }
        let gone = order.items.filter { shop.expiredAvailable($0) <= 0 }
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "clock").font(.system(size: 18, weight: .light)).foregroundStyle(Theme.muted)
                    .frame(width: 44, height: 44).background(Circle().fill(Theme.surface))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Время на оплату вышло").font(Theme.font(17, .medium))
                    Text("Заказ № \(order.number) отменён").font(Theme.font(13)).foregroundStyle(Theme.muted)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                if !back.isEmpty {
                    group(back, cap: "СНОВА В ВАШЕЙ КОРЗИНЕ", badge: "checkmark", tone: Theme.ok, dim: false)
                }
                if !gone.isEmpty {
                    if !back.isEmpty { Divider() }
                    group(gone, cap: "УЖЕ РАЗОБРАЛИ", badge: "xmark", tone: Theme.dim, dim: true)
                }
            }
            .padding(.top, 14)
            .overlay(alignment: .top) { Rectangle().fill(Theme.ink.opacity(0.07)).frame(height: 1) }
            Text(back.isEmpty ? "Загляните в каталог — там много нового, а этих размеров может появиться ещё." : "Успейте оформить заново, пока вещи в наличии.")
                .font(Theme.font(13)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            if back.isEmpty { PrimaryButton(title: "В каталог") { router.reset(.catalog) } }
            else { PrimaryButton(title: "Перейти в корзину") { shop.ensureInCart(order); router.reset(.cart) } }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 22).fill(.white).shadow(color: Theme.ink.opacity(0.06), radius: 18, y: 8))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Theme.ink.opacity(0.07), lineWidth: 1))
        .onAppear { shop.returnExpired(order) }
    }
    private func group(_ items: [OrderItem], cap: String, badge: String, tone: Color, dim: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(cap).font(Theme.font(10.5, .medium)).kerning(1.1).foregroundStyle(Theme.dim)
            ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                HStack(spacing: 12) {
                    ProductImage(path: it.image, kind: it.artKind, tone: it.artTone)
                        .frame(width: 44, height: 58).background(Theme.photo).clipShape(RoundedRectangle(cornerRadius: 10))
                        .saturation(dim ? 0 : 1).opacity(dim ? 0.5 : 1)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: badge).font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                                .frame(width: 18, height: 18).background(Circle().fill(tone)).overlay(Circle().strokeBorder(.white, lineWidth: 1.5)).offset(x: 5, y: 5)
                        }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(it.name).font(Theme.font(14.5)).foregroundStyle(dim ? Theme.muted : Theme.text).lineLimit(1)
                        Text(it.meta).font(Theme.font(12)).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
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
