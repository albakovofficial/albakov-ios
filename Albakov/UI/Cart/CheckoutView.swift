import SwiftUI
import WebKit

// Оформление заказа: контакты, доставка (пункт СДЭК, курьер, самовывоз), оплата, промокод, бонусы.
// Итог считает сервер, заказ создаёт сервер; онлайн-оплата — страница ЮKassa в окне приложения.
struct CheckoutView: View {
    @EnvironmentObject private var shop: Shop
    @EnvironmentObject private var router: Router

    @State private var firstName = "", lastName = "", phone = "", email = ""
    @State private var deliveryId = ""
    @State private var city: CdekCity?
    @State private var point: CdekPoint?
    @State private var cityText = "", address = ""
    @State private var payment = "online"
    @State private var code = ""
    @State private var appliedCode = ""
    @State private var useBonus = false
    @State private var comment = ""
    @State private var consent = false
    @State private var quote = JSON(nil)
    @State private var busy = false
    @State private var error: String?
    @State private var pickCity = false
    @State private var pickPoint = false
    @State private var payURL: URL?
    @State private var placed: (id: String, token: String)?
    @State private var idem = UUID().uuidString.replacingOccurrences(of: "-", with: "")

    private var method: DeliveryMethod? { shop.settings.delivery.first { $0.id == deliveryId } }
    private var onlineOk: Bool { shop.settings.payOnline && shop.payReady }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                block("Получатель") {
                    HStack(spacing: 10) {
                        Field(label: "Имя", text: $firstName, content: .givenName)
                        Field(label: "Фамилия", text: $lastName, content: .familyName)
                    }
                    Field(label: "Телефон", text: $phone, placeholder: "+7", keyboard: .phonePad, content: .telephoneNumber)
                    Field(label: "Почта — для чека и статуса заказа", text: $email, keyboard: .emailAddress, content: .emailAddress, capitalization: .never)
                }

                block("Доставка") {
                    ForEach(shop.settings.delivery) { m in
                        Option(selected: deliveryId == m.id, title: m.name, sub: m.desc, trailing: deliveryPrice(m)) { deliveryId = m.id; point = nil }
                    }
                    if let m = method {
                        if (m.isPvz || m.isDoor) && shop.cdekReady {
                            Button { pickCity = true } label: { pickerRow("Город", city.map { $0.title } ?? "Выберите город") }
                            if m.isPvz, city != nil {
                                Button { pickPoint = true } label: { pickerRow(point?.type == "postamat" ? "Постамат" : "Пункт выдачи", point?.address ?? "Выберите пункт") }
                            }
                            if m.isDoor { Field(label: "Улица, дом, квартира", text: $address, content: .fullStreetAddress) }
                        } else if m.needsAddress {
                            Field(label: "Город", text: $cityText, content: .addressCity)
                            Field(label: "Улица, дом, квартира", text: $address, content: .fullStreetAddress)
                        }
                    }
                }

                block("Оплата") {
                    if onlineOk {
                        Option(selected: payment == "online", title: shop.settings.onlineLabel,
                               sub: shop.settings.bonusEnabled && shop.settings.bonusOnlineExtra > 0 ? "+\(shop.settings.bonusOnlineExtra)% бонусами за онлайн-оплату" : "Карта, СБП, SberPay", trailing: nil) { payment = "online" }
                    }
                    if shop.settings.payCod {
                        Option(selected: payment == "cod", title: shop.settings.codLabel, sub: "Примерьте и оплатите только то, что подошло", trailing: nil) { payment = "cod" }
                    }
                }

                block("Промокод и бонусы") {
                    HStack(spacing: 10) {
                        TextField("Промокод", text: $code).font(Theme.font(16)).textInputAutocapitalization(.characters).autocorrectionDisabled()
                            .padding(.horizontal, 14).frame(height: 50).background(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line))
                        Button(appliedCode.isEmpty ? "Применить" : "Убрать") { appliedCode = appliedCode.isEmpty ? code.trimmingCharacters(in: .whitespaces) : ""; if appliedCode.isEmpty { code = "" } }
                            .font(Theme.font(14, .medium)).foregroundStyle(Theme.text).padding(.horizontal, 16).frame(height: 50).background(Capsule().strokeBorder(Theme.line))
                    }
                    if let m = quote["promo"]["message"].string, !appliedCode.isEmpty { Text(m).font(Theme.font(13)).foregroundStyle(quote["promo"]["ok"].bool ? Theme.ok : Theme.danger) }
                    if let u = shop.user, u.bonus > 0, shop.settings.bonusEnabled {
                        Toggle(isOn: $useBonus) { VStack(alignment: .leading, spacing: 2) { Text("Списать бонусы").font(Theme.font(15)); Text("На счёте \(u.bonus)").font(Theme.font(12.5)).foregroundStyle(Theme.muted) } }.tint(Theme.ink)
                    }
                }

                block("Комментарий") {
                    TextField("Пожелания к заказу", text: $comment, axis: .vertical).font(Theme.font(15)).lineLimit(2...5)
                        .padding(14).background(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line))
                }

                summary

                Toggle(isOn: $consent) {
                    Text("Согласен на обработку персональных данных и с условиями оферты").font(Theme.font(13)).foregroundStyle(Theme.muted)
                }.tint(Theme.ink)
                ErrorText(text: error)
                PrimaryButton(title: payment == "online" && onlineOk ? "Оплатить \(Fmt.rub(quote["total"].int ?? 0))" : "Оформить заказ", busy: busy, disabled: !consent) { Task { await place() } }
                HStack(spacing: 14) {
                    ForEach(["offer", "privacy", "consent"], id: \.self) { s in if let p = shop.page(s) { Button(p.title) { router.push(.page(s), on: .cart) }.font(Theme.font(11.5)).foregroundStyle(Theme.dim) } }
                }
            }
            .padding(Theme.gutter).padding(.bottom, 30)
        }
        .navigationTitle("Оформление")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .onAppear(perform: prefill)
        .task(id: quoteKey) { await recalc() }
        .sheet(isPresented: $pickCity) { CityPicker { city = $0; point = nil; pickCity = false } }
        .sheet(isPresented: $pickPoint) { if let c = city { PointPicker(city: c, cod: payment == "cod") { point = $0; pickPoint = false } } }
        .fullScreenCover(item: $payURL) { url in
            PaymentSheet(url: url) { finished in
                payURL = nil
                if let p = placed { openOrder(p.id, paid: finished) }
            }
        }
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
        .padding(14).background(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line))
    }
    private func deliveryPrice(_ m: DeliveryMethod) -> String? {
        if m.id == deliveryId, let d = quote["delivery"]["price"].int { return d == 0 ? "Бесплатно" : Fmt.rub(d) }
        if m.priceAuto { return "по тарифу" }
        let sub = quote["subtotal"].int ?? 0
        return m.price == 0 || (m.freeFrom > 0 && sub >= m.freeFrom) ? "Бесплатно" : Fmt.rub(m.price)
    }
    private var summary: some View {
        VStack(spacing: 10) {
            row("Товары", Fmt.rub(quote["subtotal"].int ?? 0))
            if let v = quote["saleDiscount"].int, v > 0 { row("Скидка", "−" + Fmt.rub(v), Theme.danger) }
            if let v = quote["promoDiscount"].int, v > 0 { row("Промокод", "−" + Fmt.rub(v), Theme.danger) }
            if let v = quote["bonusUsed"].int, v > 0 { row("Бонусы", "−" + Fmt.rub(v), Theme.danger) }
            row("Доставка", quote["delivery"].exists ? ((quote["deliveryPrice"].int ?? 0) == 0 ? "Бесплатно" : Fmt.rub(quote["deliveryPrice"].int ?? 0)) : "—")
            Divider1()
            HStack { Text("Итого").font(Theme.font(19, .medium)); Spacer(); Text(Fmt.rub(quote["total"].int ?? 0)).font(Theme.font(19, .medium)) }
            if let b = earn, b > 0 { Text("+\(b) бонусов после получения").font(Theme.font(13)).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading) }
        }
        .padding(16).background(RoundedRectangle(cornerRadius: 20).fill(Theme.surface))
    }
    private var earn: Int? { shop.user == nil ? nil : (quote["bonusEarn"].int ?? 0) + (payment == "online" ? quote["bonusOnline"].int ?? 0 : 0) }
    private func row(_ t: String, _ v: String, _ c: Color = Theme.text) -> some View { HStack { Text(t).font(Theme.font(14.5)).foregroundStyle(Theme.muted); Spacer(); Text(v).font(Theme.font(14.5)).foregroundStyle(c) } }

    // MARK: Логика
    private func prefill() {
        if let u = shop.user, firstName.isEmpty { firstName = u.firstName; lastName = u.lastName; phone = Fmt.phone(u.phone); email = u.email }
        if deliveryId.isEmpty { deliveryId = shop.settings.delivery.first?.id ?? "" }
        if !onlineOk { payment = "cod" }
    }
    private var quoteKey: String { [deliveryId, appliedCode, String(useBonus), payment, String(city?.code ?? 0), point?.type ?? "", String(shop.cart.count)].joined(separator: "|") }
    private var body0: [String: Any] {
        var b: [String: Any] = ["lines": shop.cart.map(\.dict), "deliveryId": deliveryId, "payment": payment, "useBonus": useBonus]
        if !appliedCode.isEmpty { b["code"] = appliedCode }
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
        busy = true; defer { busy = false }
        var b = body0
        b["idem"] = idem
        b["customer"] = ["firstName": firstName, "lastName": lastName, "phone": phone, "email": email]
        b["consent"] = consent
        b["comment"] = comment
        if let p = point { b["pvz"] = p.code }
        if m.isDoor || !(shop.cdekReady && m.isPvz) { b["address"] = address; b["city"] = city?.city ?? cityText }
        do {
            let r = try await API.shared.json("POST", "orders", body: b)
            let id = r["order"]["id"].str, token = r["token"].str
            OrderTokens.save(id, token)
            placed = (id, token)
            shop.clearCart()
            Haptic.success()
            if let s = r["payUrl"].string, let u = URL(string: s) { payURL = u } else { openOrder(id, paid: false) }
        } catch { self.error = error.localizedDescription; Haptic.error() }
    }
    private func openOrder(_ id: String, paid: Bool) {
        router.reset(.cart)
        router.reset(.account, to: [.orders, .order(id)])
        Toast.shared.show("Спасибо! Заказ оформлен")
        Task { await shop.refreshUser() }
    }
}

extension URL: Identifiable { public var id: String { absoluteString } }

/// Токены заказов без кабинета: по ним покупатель видит свой заказ на этом телефоне
enum OrderTokens {
    static func save(_ id: String, _ t: String) { var d = all; d[id] = t; UserDefaults.standard.set(d, forKey: "orderTokens") }
    static var all: [String: String] { UserDefaults.standard.dictionary(forKey: "orderTokens") as? [String: String] ?? [:] }
}

struct Option: View {
    let selected: Bool, title: String, sub: String
    let trailing: String?
    let action: () -> Void
    var body: some View {
        Button { Haptic.tap(); withAnimation(.easeOut(duration: 0.15)) { action() } } label: {
            HStack(alignment: .top, spacing: 12) {
                Circle().strokeBorder(selected ? Theme.ink : Theme.line, lineWidth: selected ? 6 : 1.5).frame(width: 20, height: 20).padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(Theme.font(15, .medium)).foregroundStyle(Theme.text)
                    if !sub.isEmpty { Text(sub).font(Theme.font(13)).foregroundStyle(Theme.muted).multilineTextAlignment(.leading) }
                }
                Spacer()
                if let trailing { Text(trailing).font(Theme.font(14)).foregroundStyle(Theme.text) }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(selected ? Theme.surface : .white))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(selected ? Theme.ink : Theme.line, lineWidth: selected ? 1.5 : 1))
        }
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
                try? await Task.sleep(nanoseconds: 300_000_000)
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
