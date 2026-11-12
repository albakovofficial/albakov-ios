import SwiftUI

// Подарочные сертификаты: покупка (оплата ЮKassa в окне приложения, код уходит получателю на почту) и проверка остатка.
struct GiftView: View {
    @EnvironmentObject private var shop: Shop
    @EnvironmentObject private var router: Router
    @State private var amount = 0
    @State private var custom = false
    @State private var customText = ""
    @State private var toName = ""
    @State private var toEmail = ""
    @State private var message = ""
    @State private var onDate = false
    @State private var sendAt = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var fromName = ""
    @State private var offer = false
    @State private var consent = false
    @State private var busy = false
    @State private var error: String?
    @State private var payURL: URL?
    @State private var placed: (id: String, token: String)?
    @State private var checkCode = ""
    @State private var checked = JSON(nil)
    @State private var checkError: String?

    private var cfg: JSON { shop.giftCfg }
    private var nominals: [Int] { let n = cfg["nominals"].array.compactMap(\.int); return n.isEmpty ? [5000, 10000, 20000] : n }
    private var minSum: Int { cfg["min"].int ?? 3000 }
    private var maxSum: Int { cfg["max"].int ?? 100000 }
    private var months: Int { cfg["months"].int ?? 12 }
    private var sum: Int { custom ? Int(customText.filter(\.isNumber)) ?? 0 : amount }
    private var canBuy: Bool { shop.payReady && shop.settings.payOnline }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow(text: "Подарочные сертификаты")
                    Text("Подарите \(shop.settings.storeName)").font(Theme.font(30, .light)).kerning(-0.6)
                    Text("Электронный сертификат придёт получателю на почту — сразу или в день праздника. Им можно оплатить любые вещи, целиком или за несколько покупок.")
                        .font(Theme.font(14.5)).foregroundStyle(Theme.muted)
                }
                card
                HStack(spacing: 10) {
                    fact("\(months) \(Fmt.plural(months, "месяц", "месяца", "месяцев"))", "срок действия")
                    fact("Частями", "в несколько покупок")
                    fact("На почту", "в выбранный день")
                }
                section("Сумма") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(nominals, id: \.self) { n in chip(Fmt.rub(n), on: !custom && amount == n) { custom = false; amount = n } }
                            chip("Своя сумма", on: custom) { custom = true }
                        }
                    }
                    if custom { Field(label: "Своя сумма, ₽ — от \(Fmt.rub(minSum)) до \(Fmt.rub(maxSum))", text: $customText, placeholder: "15 000", keyboard: .numberPad) }
                }
                section("Кому") {
                    Field(label: "Имя получателя", text: $toName, placeholder: "Анна", content: .name)
                    Field(label: "Почта получателя", text: $toEmail, keyboard: .emailAddress, content: .emailAddress, capitalization: .never)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Пожелание — необязательно").font(Theme.font(13)).foregroundStyle(Theme.muted)
                        TextField("С днём рождения! Выбери то, что понравится", text: $message, axis: .vertical).font(Theme.font(15)).lineLimit(2...5)
                            .padding(14).background(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line))
                    }
                    Option(selected: !onDate, title: "Отправить сразу после оплаты", sub: "", trailing: nil) { onDate = false }
                    Option(selected: onDate, title: "В выбранный день", sub: "Письмо придёт в 10:00 по Москве", trailing: nil) { onDate = true }
                    if onDate {
                        DatePicker("Дата отправки", selection: $sendAt, in: tomorrow...yearAhead, displayedComponents: .date)
                            .font(Theme.font(15)).environment(\.locale, Locale(identifier: "ru_RU")).tint(Theme.ink)
                    }
                }
                section("От кого") {
                    HStack(spacing: 10) {
                        Field(label: "Ваше имя", text: $firstName, content: .givenName)
                        Field(label: "Фамилия", text: $lastName, content: .familyName)
                    }
                    Field(label: "Телефон", text: $phone, placeholder: "+7", keyboard: .phonePad, content: .telephoneNumber)
                    Field(label: "Ваша почта — для чека", text: $email, keyboard: .emailAddress, content: .emailAddress, capitalization: .never)
                    Field(label: "Подпись в сертификате — необязательно", text: $fromName, placeholder: "Например, Илья")
                }
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: $offer) { legal("Принимаю условия публичной оферты", "offer") }.tint(Theme.ink)
                    Toggle(isOn: $consent) { legal("Даю согласие на обработку персональных данных", "consent") }.tint(Theme.ink)
                }
                ErrorText(text: error)
                if canBuy {
                    PrimaryButton(title: sum > 0 ? "Оплатить \(Fmt.rub(sum))" : "Выберите сумму", icon: "arrow.right", busy: busy, disabled: sum == 0) { Task { await buy() } }
                    Text("Оплата через ЮKassa. Код придёт получателю письмом, вам — чек на почту.").font(Theme.font(12.5)).foregroundStyle(Theme.muted)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Покупка онлайн скоро появится").font(Theme.font(16, .medium))
                        Text("Пока сертификат можно заказать, написав нам — оформим и пришлём код на почту.").font(Theme.font(14)).foregroundStyle(Theme.muted)
                        GhostButton(title: "Написать нам") { router.reset(.account, to: [.support]) }
                    }.padding(16).background(RoundedRectangle(cornerRadius: 20).fill(Theme.surface))
                }
                Divider1()
                section("Проверить остаток") {
                    Text("Введите код сертификата — покажем, сколько на нём осталось и до какого числа он действует.").font(Theme.font(14)).foregroundStyle(Theme.muted)
                    HStack(spacing: 10) {
                        TextField("GIFT-XXXX-XXXX", text: $checkCode).font(Theme.font(16)).textInputAutocapitalization(.characters).autocorrectionDisabled()
                            .padding(.horizontal, 14).frame(height: 50).background(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line))
                            .onSubmit { Task { await check() } }
                        Button("Проверить") { Task { await check() } }
                            .font(Theme.font(14, .medium)).foregroundStyle(Theme.text).padding(.horizontal, 16).frame(height: 50).background(Capsule().strokeBorder(Theme.line))
                    }
                    ErrorText(text: checkError)
                    if checked.exists {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(checked["code"].str).font(Theme.font(12, .medium)).kerning(1).foregroundStyle(Theme.muted)
                            Text(Fmt.rub(checked["balance"].int ?? 0)).font(Theme.font(28, .light))
                            Text("из \(Fmt.rub(checked["amount"].int ?? 0))" + (checked["expiresAt"].str.isEmpty ? "" : " · действует до " + Fmt.date(ISO.date(checked["expiresAt"].str))))
                                .font(Theme.font(13)).foregroundStyle(Theme.muted)
                            if !checked["message"].str.isEmpty { Text(checked["message"].str).font(Theme.font(13)).foregroundStyle(Theme.danger) }
                        }
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 20).fill(Theme.surface)).opacity(checked["state"].str == "active" ? 1 : 0.6)
                    }
                }
            }
            .padding(Theme.gutter).padding(.bottom, 30)
        }
        .navigationTitle("Подарочный сертификат").navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            if amount == 0 { amount = nominals.count > 1 ? nominals[1] : nominals.first ?? 0 }
            if let u = shop.user, firstName.isEmpty { firstName = u.firstName; lastName = u.lastName; phone = Fmt.phone(u.phone); email = u.email; fromName = u.firstName }
        }
        .fullScreenCover(item: $payURL) { url in
            PaymentSheet(url: url) { _ in
                payURL = nil
                if let p = placed { router.reset(.account, to: [.orders, .order(p.id)]); Toast.shared.show("Спасибо! Сертификат оплачен") }
            }
        }
    }

    // Карточка сертификата — сумма и подпись меняются по мере заполнения
    private var card: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [Color(hex: "#2a3036"), Theme.ink], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color(hex: "#ff9a5c").opacity(0.45), .clear], center: .topTrailing, startRadius: 0, endRadius: 240)
            VStack(alignment: .leading, spacing: 8) {
                Image("Wordmark").resizable().scaledToFit().frame(width: 96).colorInvert()
                Spacer()
                Text(sum > 0 ? Fmt.rub(sum) : "— ₽").font(Theme.font(34, .light)).foregroundStyle(.white)
                Text([toName.isEmpty ? "Для получателя" : "Для " + toName, fromName.isEmpty ? "" : "от " + fromName].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(Theme.font(13)).foregroundStyle(.white.opacity(0.75))
            }.padding(22)
        }
        .frame(height: 200).clipShape(RoundedRectangle(cornerRadius: 24))
    }
    private func fact(_ b: String, _ s: String) -> some View {
        VStack(alignment: .leading, spacing: 3) { Text(b).font(Theme.font(13.5, .medium)); Text(s).font(Theme.font(11.5)).foregroundStyle(Theme.muted) }
            .frame(maxWidth: .infinity, alignment: .leading).padding(12).background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
    }
    private func section<C: View>(_ t: String, @ViewBuilder _ c: () -> C) -> some View { VStack(alignment: .leading, spacing: 12) { Text(t).font(Theme.font(20, .light)); c() } }
    private func chip(_ t: String, on: Bool, _ a: @escaping () -> Void) -> some View {
        Button { Haptic.tap(); a() } label: {
            Text(t).font(Theme.font(14, .medium)).foregroundStyle(on ? .white : Theme.text).padding(.horizontal, 16).frame(height: 40)
                .background(Capsule().fill(on ? Theme.ink : .white)).overlay(Capsule().strokeBorder(on ? Theme.ink : Theme.line))
        }
    }
    private func legal(_ t: String, _ slug: String) -> some View {
        Button { if shop.page(slug) != nil { router.push(.page(slug)) } } label: { Text(t).font(Theme.font(13)).foregroundStyle(Theme.muted).multilineTextAlignment(.leading) }
    }
    private var tomorrow: Date { Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) ?? Date() }
    private var yearAhead: Date { Calendar.current.date(byAdding: .day, value: 365, to: Date()) ?? Date() }

    private func buy() async {
        error = nil
        if !(sum >= minSum && sum <= maxSum) { error = "Сумма — от \(Fmt.rub(minSum)) до \(Fmt.rub(maxSum))"; return }
        if !offer { error = "Примите условия публичной оферты"; return }
        if !consent { error = "Нужно согласие на обработку персональных данных"; return }
        busy = true; defer { busy = false }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        let b: [String: Any] = ["amount": sum, "toName": toName, "toEmail": toEmail, "message": message, "fromName": fromName, "sendAt": onDate ? f.string(from: sendAt) : "",
                                "customer": ["firstName": firstName, "lastName": lastName, "phone": phone, "email": email], "consent": true]
        do {
            let r = try await API.shared.json("POST", "gifts", body: b)
            let id = r["order"]["id"].str
            OrderTokens.save(id, r["token"].str)
            placed = (id, r["token"].str)
            if let s = r["payUrl"].string, let u = URL(string: s) { payURL = u } else { router.reset(.account, to: [.orders, .order(id)]) }
        } catch { self.error = error.localizedDescription; Haptic.error() }
    }
    private func check() async {
        let c = checkCode.trimmingCharacters(in: .whitespaces); guard !c.isEmpty else { return }
        do { checked = try await API.shared.json("POST", "gifts/check", body: ["code": c])["gift"]; checkError = nil }
        catch { checked = JSON(nil); checkError = error.localizedDescription }
    }
}

// «Где мой заказ» без входа: номер заказа и телефон → страница заказа на этом телефоне
struct TrackView: View {
    @EnvironmentObject private var router: Router
    @State private var number = ""
    @State private var phone = ""
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Eyebrow(text: "Без входа в кабинет")
                Text("Где мой заказ").font(Theme.font(30, .light)).kerning(-0.6)
                Text("Номер заказа есть в письме и SMS после оформления. Телефон — тот, что вы указали в заказе.").font(Theme.font(14.5)).foregroundStyle(Theme.muted)
                Field(label: "Номер заказа", text: $number, placeholder: "1042", keyboard: .numberPad)
                Field(label: "Телефон", text: $phone, placeholder: "+7", keyboard: .phonePad, content: .telephoneNumber)
                ErrorText(text: error)
                PrimaryButton(title: "Найти заказ", busy: busy) { Task { await find() } }
            }.padding(Theme.gutter)
        }
        .navigationTitle("Где мой заказ").navigationBarTitleDisplayMode(.inline)
    }
    private func find() async {
        error = nil; busy = true; defer { busy = false }
        do {
            let r = try await API.shared.json("POST", "track", body: ["number": number, "phone": phone])
            OrderTokens.save(r["id"].str, r["token"].str)
            router.push(.order(r["id"].str))
        } catch { self.error = error.localizedDescription; Haptic.error() }
    }
}
