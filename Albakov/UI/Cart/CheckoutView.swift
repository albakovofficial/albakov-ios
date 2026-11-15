import SwiftUI
import CryptoKit
import WebKit

// Оформление заказа: контакты, доставка (пункт СДЭК, курьер, самовывоз), оплата, промокод, бонусы.
// Итог считает сервер, заказ создаёт сервер; онлайн-оплата — страница ЮKassa в окне приложения.
struct CheckoutView: View {
    @EnvironmentObject private var shop: Shop
    @EnvironmentObject private var router: Router

    @State private var firstName = ""
    @State private var ageAsk = false
    @State private var ageStep: AgeCheckSheet.Step = .intro
    @State private var lastName = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var deliveryId = ""
    @State private var city: CdekCity?
    @State private var point: CdekPoint?
    @State private var cityText = ""
    @State private var address = ""
    @State private var payment = "online"
    @State private var code = ""
    @State private var appliedCode = ""
    @State private var gift = ""
    @State private var appliedGift = ""
    @State private var showGift = false
    @State private var useBonus = false
    @State private var comment = ""
    @State private var consent = false
    @State private var offer = false
    @State private var quote = JSON(nil)
    @State private var busy = false
    @State private var error: String?
    @State private var pickCity = false
    @State private var pickPoint = false
    @State private var payURL: URL?
    @State private var placed: (id: String, token: String)?
    /// Ключ повтора заказа (1.0.2): одинаков для одной и той же корзины и данных, пока заказ не оформлен —
    /// повторное нажатие или повтор после обрыва связи, даже с нового экрана оформления, не создадут второй заказ
    @AppStorage("checkoutNonce") private var nonce = UUID().uuidString

    private var method: DeliveryMethod? { shop.settings.delivery.first { $0.id == deliveryId } }
    private var onlineOk: Bool { shop.settings.payOnline && shop.payReady }

    private var lines: [CartLine] { shop.buyNow ?? shop.cart }
    @State private var showComment = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Crumbs(items: [("Корзина", { router.reset(.cart) }), ("Оформление", nil)]).padding(.horizontal, -Theme.gutter).padding(.top, 14)
                DotTitle(text: "Оформление заказа", size: 32).padding(.top, 6).padding(.bottom, 6)
                if shop.user == nil {
                    HStack(alignment: .center, spacing: 14) {
                        Text("Б").font(Theme.font(13, .semibold)).foregroundStyle(.white).frame(width: 32, height: 32).background(Circle().fill(Theme.accentGradient))
                        (Text("Уже покупали у нас? ").font(Theme.font(14.5, .medium)) + Text("Войдите, чтобы копить бонусы и видеть историю заказов. Можно оформить и без регистрации.").font(Theme.font(14.5)).foregroundColor(Theme.muted))
                            .onTapGesture { router.reset(.account) }
                    }.padding(16).background(RoundedRectangle(cornerRadius: 18).fill(Theme.surface))
                }
                step(1, "Покупатель", "Для связи по заказу и электронного чека", done: !firstName.isEmpty && !lastName.isEmpty && phone.filter(\.isNumber).count >= 11 && email.contains("@")) {
                    Field(label: "Имя", text: $firstName, placeholder: "Иван", content: .givenName)
                    Field(label: "Фамилия", text: $lastName, placeholder: "Иванов", content: .familyName)
                    Field(label: "Телефон", text: $phone, placeholder: "+7 (___) ___-__-__", keyboard: .phonePad, content: .telephoneNumber)
                    Field(label: "Электронная почта", text: $email, placeholder: "mail@example.ru", keyboard: .emailAddress, content: .emailAddress, capitalization: .never)
                }
                step(2, "Доставка", "Выберите способ и укажите, куда привезти", done: method != nil && (city != nil || !cityText.isEmpty || !(method?.needsAddress ?? true))) {
                    ForEach(shop.settings.delivery) { m in
                        Option(selected: deliveryId == m.id, title: m.name, sub: m.desc, trailing: deliveryPrice(m), icon: m.isPvz || m.isDoor ? "delivery" : m.needsAddress ? "delivery" : "pin") { deliveryId = m.id; point = nil }
                    }
                    if let m = method {
                        VStack(alignment: .leading, spacing: 12) {
                            if (m.isPvz || m.isDoor) && shop.cdekReady {
                                Button { pickCity = true } label: { pickerRow("Город или посёлок", city.map { $0.title } ?? "Начните вводить, например «Мурино»") }
                                if m.isPvz, city != nil {
                                    Button { pickPoint = true } label: { pickerRow(point?.type == "postamat" ? "Постамат" : "Пункт выдачи", point?.address ?? "Выберите пункт") }
                                }
                                if m.isDoor { Field(label: "Адрес", text: $address, placeholder: "Улица, дом, квартира", content: .fullStreetAddress) }
                            } else if m.needsAddress {
                                Field(label: "Город или посёлок", text: $cityText, placeholder: "Москва", content: .addressCity)
                                Field(label: "Адрес", text: $address, placeholder: "Улица, дом, квартира", content: .fullStreetAddress)
                            }
                        }.padding(14).background(RoundedRectangle(cornerRadius: 18).fill(Theme.surface))
                    }
                    if showComment || !comment.isEmpty {
                        AreaField(label: "Комментарий к заказу", text: $comment, placeholder: "Пожелания к заказу", lines: 2...5)
                    } else {
                        Button { withAnimation { showComment = true } } label: {
                            HStack(spacing: 10) { Image(systemName: "plus").font(.system(size: 10, weight: .medium)).frame(width: 22, height: 22).overlay(Circle().strokeBorder(Theme.lineStrong)); Text("Добавить комментарий к заказу").font(Theme.font(14.5)) }.foregroundStyle(Theme.text)
                        }
                    }
                }
                step(3, "Оплата", payment == "online" && onlineOk ? "Картой, СБП или SberPay — на защищённой странице ЮKassa" : "Оплатите заказ при получении — наличными или картой", done: true) {
                    if onlineOk {
                        Option(selected: payment == "online", title: shop.settings.onlineLabel,
                               sub: shop.settings.bonusEnabled && shop.settings.bonusOnlineExtra > 0 ? "+\(shop.settings.bonusOnlineExtra)% бонусами за онлайн-оплату" : "Карта, СБП, SberPay", trailing: nil, icon: "payment") { payment = "online" }
                    }
                    if shop.settings.payCod {
                        Option(selected: payment == "cod", title: shop.settings.codLabel, sub: "Наличными или картой при получении", trailing: nil, icon: "cash") { payment = "cod" }
                    }
                }
                orderCard
                VStack(alignment: .leading, spacing: 12) {
                    checkRow($offer) { Text("Принимаю условия ") + Text("публичной оферты").underline() }
                    checkRow($consent) { Text("Даю ") + Text("согласие на обработку персональных данных").underline() }
                    ErrorText(text: error)
                    PrimaryButton(title: payment == "online" && onlineOk && !paidInFull ? "Перейти к оплате · \(Fmt.rub(quote["total"].int ?? 0))" : "Подтвердить заказ", busy: busy, disabled: !consent || !offer) { Task { await place() } }
                    HStack(spacing: 14) {
                        ForEach(["offer", "privacy", "consent"], id: \.self) { s in if let p = shop.page(s) { Button(p.title) { router.push(.page(s)) }.font(Theme.font(11.5)).foregroundStyle(Theme.dim) } }
                    }
                }.padding(20).background(RoundedRectangle(cornerRadius: 24).fill(Theme.surface))
            }
            .padding(.horizontal, Theme.gutter).padding(.bottom, 40)
        }
        .navigationTitle("Оформление")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .onAppear(perform: prefill)
        .onDisappear { if placed == nil && ![router.home, router.catalog, router.favorites, router.cart, router.account].contains(where: { $0.contains(.checkout) }) { shop.buyNow = nil } }
        .task(id: quoteKey) { await recalc() }
        .sheet(isPresented: $ageAsk) { AgeCheckSheet(step: $ageStep) { Task { await place() } } }
        .sheet(isPresented: $pickCity) { CityPicker { city = $0; point = nil; pickCity = false } }
        .sheet(isPresented: $pickPoint) { if let c = city { PointPicker(city: c, cod: payment == "cod") { point = $0; pickPoint = false } } }
        .fullScreenCover(item: $payURL) { url in
            PaymentSheet(url: url) { finished in
                payURL = nil
                // окно закрыли до оплаты — заказ сохранён и ждёт оплаты; вернулись со страницы оплаты — статус покажет заказ
                if let p = placed { openOrder(p.id, toast: finished ? "Спасибо! Заказ оформлен" : "Заказ ждёт оплаты — оплатить можно в заказе") }
            }
        }
    }

    // «Ваш заказ»: вещи, промокод, сертификат, бонусы и суммы
    private var orderCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ваш заказ").font(Theme.font(26, .light))
            ForEach(lines) { l in
                if shop.buyNow == nil { CartRow(line: l, q: quote["lines"].array.first { $0["productId"].str == l.productId && $0["colorId"].str == l.colorId && $0["size"].str == l.size } ?? JSON(nil), compact: true) }
                else { buyNowRow(l) }
            }
            codeField("ПРОМОКОД", text: $code, applied: $appliedCode)
            if let m = quote["promo"]["message"].string, !appliedCode.isEmpty { Text(m).font(Theme.font(13)).foregroundStyle(quote["promo"]["ok"].bool ? Theme.ok : Theme.danger) }
            if shop.giftEnabled {
                if showGift || !appliedGift.isEmpty {
                    codeField("GIFT-XXXX-XXXX", text: $gift, applied: $appliedGift)
                    if !appliedGift.isEmpty, quote["gift"].exists {
                        let ok = quote["gift"]["ok"].bool
                        VStack(alignment: .leading, spacing: 2) {
                            if ok { Text("Сертификат \(quote["gift"]["code"].str) — спишем \(Fmt.rub(quote["giftUsed"].int ?? 0))").font(Theme.font(13.5, .medium)).foregroundStyle(Theme.ok) }
                            Text(quote["gift"]["message"].str).font(Theme.font(13)).foregroundStyle(ok ? Theme.muted : Theme.danger)
                        }
                    }
                } else {
                    Button { withAnimation { showGift = true } } label: { Text("Есть подарочный сертификат?").font(Theme.font(14.5)).foregroundStyle(Theme.muted) }
                }
            }
            if let u = shop.user, u.bonus > 0, shop.settings.bonusEnabled {
                Toggle(isOn: $useBonus) { VStack(alignment: .leading, spacing: 2) { Text("Списать бонусы").font(Theme.font(15)); Text("На счёте \(Fmt.num(u.bonus))").font(Theme.font(12.5)).foregroundStyle(Theme.muted) } }.tint(Theme.ink)
            } else if shop.user == nil, let b = quote["bonusEarn"].int, b > 0 {
                HStack(spacing: 10) {
                    Text("Б").font(Theme.font(10, .semibold)).foregroundStyle(.white).frame(width: 18, height: 18).background(Circle().fill(Theme.accent))
                    Text("Войдите — и получите +\(Fmt.num(b)) \(Fmt.plural(b, "бонус", "бонуса", "бонусов")) за этот заказ").font(Theme.font(14))
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Rectangle().fill(.white)).onTapGesture { router.reset(.account) }
            }
            summary
        }
        .padding(20).background(RoundedRectangle(cornerRadius: 24).fill(Theme.surface)).hairline(RoundedRectangle(cornerRadius: 24), 0.06)
    }
    private func buyNowRow(_ l: CartLine) -> some View {
        let p = shop.product(l.productId), c = p?.color(l.colorId)
        return HStack(alignment: .top, spacing: 14) {
            ProductImage(path: c?.images.first ?? "", kind: c?.artKind ?? "tee", tone: c?.artTone ?? "#3a3632").frame(width: 56, height: 72).background(Theme.photo).clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(p?.name ?? "").font(Theme.font(13.5))
                Text([c?.name ?? "", l.size, "\(l.qty) шт."].joined(separator: " · ")).font(Theme.font(12.5)).foregroundStyle(Theme.muted)
            }
            Spacer()
            if let p { Text(Fmt.rub(shop.price(p).price * l.qty)).font(Theme.font(14)) }
        }.padding(.vertical, 6)
    }
    private func step<C: View>(_ n: Int, _ title: String, _ hint: String, done: Bool, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    if done && n == 3 { Circle().fill(Theme.ok); Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white) }
                    else { Circle().strokeBorder(Theme.lineStrong); Text("\(n)").font(Theme.font(14)) }
                }.frame(width: 34, height: 34).padding(.top, 4)
                VStack(alignment: .leading, spacing: 4) { Text(title).font(Theme.font(23, .light)); Text(hint).font(Theme.font(13.5)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true) }
            }
            c()
        }
        .padding(16).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 24).fill(.white)).hairline(RoundedRectangle(cornerRadius: 24), 0.08)
    }
    private func checkRow(_ b: Binding<Bool>, _ t: () -> Text) -> some View {
        Button { b.wrappedValue.toggle(); Haptic.tap() } label: {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 4).strokeBorder(b.wrappedValue ? Theme.ink : Theme.lineStrong).background(RoundedRectangle(cornerRadius: 4).fill(b.wrappedValue ? Theme.ink : .white))
                    .overlay(b.wrappedValue ? Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white) : nil).frame(width: 20, height: 20).padding(.top, 2)
                t().font(Theme.font(14.5)).foregroundColor(Theme.muted).multilineTextAlignment(.leading)
            }
        }.buttonStyle(.plain)
    }

    // MARK: Части экрана
    private func block<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) { Text(title).font(Theme.font(20, .light)); c() }
    }
    private func pickerRow(_ label: String, _ value: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) { Text(label).font(Theme.font(12.5)).foregroundStyle(Theme.muted); Text(value).font(Theme.font(15)).foregroundStyle(Theme.text).multilineTextAlignment(.leading) }
            Spacer(); Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Theme.dim)
        }
        .padding(14).background(RoundedRectangle(cornerRadius: 14).fill(.white))
    }
    /// Поле кода с кнопкой «Применить» / «Убрать» — для промокода и подарочного сертификата
    private func codeField(_ placeholder: String, text: Binding<String>, applied: Binding<String>) -> some View {
        HStack(spacing: 10) {
            TextField(placeholder, text: text).font(Theme.font(16)).textInputAutocapitalization(.characters).autocorrectionDisabled()
                .padding(.horizontal, 14).frame(height: 50).background(RoundedRectangle(cornerRadius: 14).fill(.white)).overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line))
                .onSubmit { applied.wrappedValue = text.wrappedValue.trimmingCharacters(in: .whitespaces) }
            Button(applied.wrappedValue.isEmpty ? "Применить" : "Убрать") {
                applied.wrappedValue = applied.wrappedValue.isEmpty ? text.wrappedValue.trimmingCharacters(in: .whitespaces) : ""
                if applied.wrappedValue.isEmpty { text.wrappedValue = "" }
            }
            .font(Theme.font(14, .medium)).foregroundStyle(Theme.text).padding(.horizontal, 18).frame(height: 50).background(Capsule().fill(.white)).hairline(Capsule(), 0.1)
        }
    }
    private func deliveryPrice(_ m: DeliveryMethod) -> String? {
        if m.id == deliveryId, let d = quote["delivery"]["price"].int { return d == 0 ? "Бесплатно" : Fmt.rub(d) }
        if m.priceAuto { return "по тарифу" }
        let sub = quote["subtotal"].int ?? 0
        return m.price == 0 || (m.freeFrom > 0 && sub >= m.freeFrom) ? "Бесплатно" : Fmt.rub(m.price)
    }
    private var summary: some View {
        VStack(spacing: 12) {
            row("Товары", Fmt.rub(quote["baseTotal"].int ?? quote["subtotal"].int ?? 0))
            if let v = quote["saleDiscount"].int, v > 0 { row("Скидка по акциям", "−" + Fmt.rub(v), Theme.sale) }
            if let v = quote["promoDiscount"].int, v > 0 { row("Промокод", "−" + Fmt.rub(v), Theme.sale) }
            if let v = quote["bonusUsed"].int, v > 0 { row("Бонусы", "−" + Fmt.rub(v), Theme.sale) }
            if let v = quote["giftUsed"].int, v > 0 { row("Подарочный сертификат", "−" + Fmt.rub(v), Theme.sale) }
            row("Доставка", quote["delivery"].exists ? ((quote["deliveryPrice"].int ?? 0) == 0 ? "Бесплатно" : Fmt.rub(quote["deliveryPrice"].int ?? 0)) : "—")
            Divider1()
            HStack(alignment: .firstTextBaseline) { Text("К оплате").font(Theme.font(19)); Spacer(); Text(Fmt.rub(quote["total"].int ?? 0)).font(Theme.font(23, .light)) }
            if paidInFull { Text("Заказ полностью оплачен \(giftUsed > 0 && (quote["bonusUsed"].int ?? 0) > 0 ? "сертификатом и бонусами" : giftUsed > 0 ? "подарочным сертификатом" : "бонусами") — платить ничего не нужно.").font(Theme.font(13)).foregroundStyle(Theme.ok).frame(maxWidth: .infinity, alignment: .leading) }
            if let b = earn, b > 0 {
                HStack(spacing: 8) {
                    Text("Б").font(Theme.font(10, .semibold)).foregroundStyle(.white).frame(width: 17, height: 17).background(Circle().fill(Theme.accent))
                    Text("Бонусы за заказ").font(Theme.font(14)).foregroundStyle(Theme.muted); Spacer()
                    Text("+\(Fmt.num(b)) \(Fmt.plural(b, "бонус", "бонуса", "бонусов"))").font(Theme.font(14, .medium))
                }
            }
        }.padding(.top, 6)
    }
    private var giftUsed: Int { quote["giftUsed"].int ?? 0 }
    private var paidInFull: Bool { quote["total"].exists && (quote["total"].int ?? 0) == 0 && (giftUsed > 0 || (quote["bonusUsed"].int ?? 0) > 0) }
    private var earn: Int? { shop.user == nil ? nil : (quote["bonusEarn"].int ?? 0) + (payment == "online" ? quote["bonusOnline"].int ?? 0 : 0) }
    private func row(_ t: String, _ v: String, _ c: Color = Theme.text) -> some View { HStack { Text(t).font(Theme.font(14.5)).foregroundStyle(Theme.muted); Spacer(); Text(v).font(Theme.font(14.5)).foregroundStyle(c) } }

    // MARK: Логика
    private func prefill() {
        if let u = shop.user, firstName.isEmpty { firstName = u.firstName; lastName = u.lastName; phone = Fmt.phone(u.phone); email = u.email }
        if deliveryId.isEmpty { deliveryId = shop.settings.delivery.first?.id ?? "" }
        if !onlineOk { payment = "cod" }
    }
    private var quoteKey: String { [deliveryId, appliedCode, appliedGift, String(useBonus), payment, String(city?.code ?? 0), point?.type ?? "", String(lines.count), String(lines.reduce(0) { $0 + $1.qty })].joined(separator: "|") }
    private var body0: [String: Any] {
        var b: [String: Any] = ["lines": lines.map(\.dict), "deliveryId": deliveryId, "payment": payment, "useBonus": useBonus]
        if !appliedCode.isEmpty { b["code"] = appliedCode }
        if !appliedGift.isEmpty { b["gift"] = appliedGift }
        if let c = city { b["cityCode"] = c.code }
        if let p = point { b["pvzType"] = p.type }
        return b
    }
    private func recalc() async {
        if let r = try? await API.shared.json("POST", "quote", body: body0) { withAnimation { quote = r["quote"] } }
    }
    private func place() async {
        error = nil
        guard let m = method else { error = "Выберите способ доставки"; return }
        if (m.isPvz || m.isDoor) && shop.cdekReady && city == nil { error = "Выберите город"; return }
        if m.isPvz && shop.cdekReady && point == nil { error = "Выберите пункт выдачи"; return }
        guard !busy else { return }
        // Кнопка блокируется сразу, до проверки возраста: двойное нажатие не отправит заказ дважды (1.0.2)
        busy = true; defer { busy = false }
        // Возраст: только где этого требует закон (США и др.), один раз — окно ALBAKOV, затем окно Apple
        if await AgeCheck.needed() { ageStep = .intro; ageAsk = true; return }
        var b = body0
        if !quote["gift"]["ok"].bool { b.removeValue(forKey: "gift") }   // недействительный сертификат в заказ не передаём, как на сайте
        b["customer"] = ["firstName": firstName, "lastName": lastName, "phone": phone, "email": email]
        b["consent"] = consent
        b["comment"] = comment
        if let p = point { b["pvz"] = p.code }
        if m.isDoor || !(shop.cdekReady && m.isPvz) { b["address"] = address; b["city"] = city?.city ?? cityText }
        b["idem"] = Self.idem(nonce, b)
        do {
            let r = try await API.shared.json("POST", "orders", body: b)
            nonce = UUID().uuidString   // заказ оформлен: следующий будет новым
            let id = r["order"]["id"].str, token = r["token"].str
            OrderTokens.save(id, token)
            placed = (id, token)
            if shop.buyNow != nil { shop.buyNow = nil } else { shop.clearCart() }
            Haptic.success()
            if let s = r["payUrl"].string, let u = URL(string: s) { payURL = u } else { openOrder(id, toast: "Спасибо! Заказ оформлен") }
        } catch let e as APIError where e.status == 0 {
            // связь пропала: заказ мог успеть оформиться — повторное нажатие вернёт его же, второго не будет
            self.error = "Связь прервалась. Нажмите кнопку ещё раз — если заказ уже оформлен, мы просто откроем его, второго не будет."; Haptic.error()
        } catch { self.error = error.localizedDescription; Haptic.error() }
    }
    /// Ключ повтора: случайная часть + содержимое заказа. Другая корзина или данные — другой ключ
    static func idem(_ nonce: String, _ b: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: b, options: [.sortedKeys])) ?? Data()
        return SHA256.hash(data: Data(nonce.utf8) + data).map { String(format: "%02x", $0) }.joined().prefix(40).description
    }
    private func openOrder(_ id: String, toast: String) {
        router.reset(.cart)
        router.reset(.account, to: [.orders, .order(id)])
        Toast.shared.show(toast)
        Task { await shop.refreshUser() }
    }
}

extension URL: Identifiable { public var id: String { absoluteString } }

/// Токены заказов без кабинета: по ним покупатель видит свой заказ на этом телефоне
enum OrderTokens {
    static func save(_ id: String, _ t: String) { var d = all; d[id] = t; UserDefaults.standard.set(d, forKey: "orderTokens") }
    static var all: [String: String] { UserDefaults.standard.dictionary(forKey: "orderTokens") as? [String: String] ?? [:] }
}

/// Вариант доставки или оплаты (.opt): белая карточка, кружок выбора, картинка-значок, подпись и цена капсулой
struct Option: View {
    let selected: Bool, title: String, sub: String
    let trailing: String?
    var icon: String? = nil
    let action: () -> Void
    var body: some View {
        Button { Haptic.tap(); withAnimation(.easeOut(duration: 0.15)) { action() } } label: {
            HStack(alignment: .top, spacing: 12) {
                Circle().strokeBorder(selected ? Theme.ink : Theme.lineStrong, lineWidth: selected ? 6 : 1.2).frame(width: 20, height: 20).padding(.top, 12)
                if let icon { RemoteImage(path: "img/benefits/\(icon).webp", contentMode: .fit).frame(width: 44, height: 44) }
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(Theme.font(15.5, .medium)).foregroundStyle(Theme.text).multilineTextAlignment(.leading)
                    if !sub.isEmpty { Text(sub).font(Theme.font(13.5)).foregroundStyle(Theme.muted).multilineTextAlignment(.leading) }
                    if let trailing {
                        Text(trailing).font(Theme.font(14, .medium)).foregroundStyle(selected ? .white : Theme.text)
                            .padding(.horizontal, 12).padding(.vertical, 5).background(Capsule().fill(selected ? Theme.accent : Theme.surface)).padding(.top, 4)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(selected ? Theme.ink : Theme.line, lineWidth: selected ? 1.5 : 1))
        }.buttonStyle(.plain)
    }
}

// MARK: - СДЭК: город и пункт выдачи
struct CdekCity: Identifiable, Hashable {
    let code: Int, city: String, region: String
    var id: Int { code }
    var title: String { region.isEmpty ? city : city + ", " + region }
}
struct CdekPoint: Identifiable, Hashable {
    let code: String, type: String, address: String, hours: String, metro: String, cod: Bool
    var id: String { code }
}

struct CityPicker: View {
    let pick: (CdekCity) -> Void
    @State private var q = ""
    @State private var list: [CdekCity] = []
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).font(Theme.font(14)).foregroundStyle(Theme.danger) }
                ForEach(list) { c in
                    Button { pick(c) } label: { VStack(alignment: .leading, spacing: 2) { Text(c.city).font(Theme.font(16)); if !c.region.isEmpty { Text(c.region).font(Theme.font(12.5)).foregroundStyle(Theme.muted) } } }
                        .foregroundStyle(Theme.text)
                }
            }
            .listStyle(.plain)
            .searchable(text: $q, placement: .navigationBarDrawer(displayMode: .always), prompt: "Начните вводить город")
            .navigationTitle("Город").navigationBarTitleDisplayMode(.inline)
            .task(id: q) {
                guard q.count >= 2 else { list = []; return }
                guard (try? await Task.sleep(nanoseconds: 300_000_000)) != nil else { return }
                do {
                    let r = try await API.shared.json("GET", "cdek/cities", query: ["q": q])
                    list = r["cities"].array.map { CdekCity(code: $0["code"].int ?? 0, city: $0["city"].str, region: $0["region"].str) }; error = nil
                } catch { self.error = error.localizedDescription }
            }
        }
    }
}

struct PointPicker: View {
    let city: CdekCity, cod: Bool
    let pick: (CdekPoint) -> Void
    @State private var all: [CdekPoint] = []
    @State private var q = ""
    @State private var loading = true
    @State private var error: String?
    private var list: [CdekPoint] {
        let t = q.lowercased()
        return all.filter { (!cod || $0.cod) && (t.isEmpty || ($0.address + " " + $0.metro).lowercased().contains(t)) }
    }
    var body: some View {
        NavigationStack {
            List {
                if loading { ProgressView().frame(maxWidth: .infinity) }
                if let error { Text(error).font(Theme.font(14)).foregroundStyle(Theme.danger) }
                if cod && !all.isEmpty { Text("Показаны пункты, где можно оплатить при получении").font(Theme.font(12.5)).foregroundStyle(Theme.muted) }
                ForEach(list) { p in
                    Button { pick(p) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack { Text(p.type == "postamat" ? "Постамат" : "Пункт выдачи").font(Theme.font(11.5, .medium)).foregroundStyle(Theme.muted); if !p.metro.isEmpty { Text("м. " + p.metro).font(Theme.font(11.5)).foregroundStyle(Theme.dim) } }
                            Text(p.address).font(Theme.font(15)).foregroundStyle(Theme.text)
                            if !p.hours.isEmpty { Text(p.hours).font(Theme.font(12)).foregroundStyle(Theme.dim) }
                        }.padding(.vertical, 4)
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $q, prompt: "Улица или метро")
            .navigationTitle(city.city).navigationBarTitleDisplayMode(.inline)
            .task {
                do {
                    let r = try await API.shared.json("GET", "cdek/points", query: ["city": String(city.code)])
                    all = r["points"].array.map { CdekPoint(code: $0["code"].str, type: $0["type"].str, address: $0["address"].str, hours: $0["hours"].str, metro: $0["metro"].str, cod: $0["cod"].bool) }
                } catch { self.error = error.localizedDescription }
                loading = false
            }
        }
    }
}

// MARK: - Оплата ЮKassa в окне приложения: после оплаты банк возвращает на albakovofficial.ru — окно закрывается само
struct PaymentSheet: View {
    let url: URL
    let done: (Bool) -> Void
    var body: some View {
        NavigationStack {
            PayWeb(url: url, done: done)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Оплата").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { done(false) } } }
        }
    }
}

struct PayWeb: UIViewRepresentable {
    let url: URL
    let done: (Bool) -> Void
    func makeCoordinator() -> C { C(done: done) }
    func makeUIView(context: Context) -> WKWebView {
        let w = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        w.navigationDelegate = context.coordinator
        w.load(URLRequest(url: url))
        return w
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class C: NSObject, WKNavigationDelegate {
        let done: (Bool) -> Void
        private var finished = false
        init(done: @escaping (Bool) -> Void) { self.done = done }
        func webView(_ webView: WKWebView, decidePolicyFor a: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let u = a.request.url else { return decisionHandler(.cancel) }
            let scheme = u.scheme?.lowercased() ?? ""
            if !["http", "https", "about", "blob", "data"].contains(scheme) { UIApplication.shared.open(u); return decisionHandler(.cancel) }   // приложения банков, СБП
            if let h = u.host?.lowercased(), h.hasSuffix("albakovofficial.ru"), a.targetFrame?.isMainFrame ?? true {
                if !finished { finished = true; DispatchQueue.main.async { self.done(true) } }
                return decisionHandler(.cancel)
            }
            decisionHandler(.allow)
        }
    }
}
