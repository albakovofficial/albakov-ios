import SwiftUI

// Карточка товара — как на сайте: крошки, фото выбранного цвета, плашки, название, артикул, выжимка характеристик,
// цена и бонусы, предзаказ, цвет и размер, подбор размера, количество и «Добавить в корзину», «Купить сейчас»,
// доставка в город, гарантия обмена, описание, характеристики, доставка и возврат, образ, похожие и недавние.
struct ProductView: View {
    let id: String
    @EnvironmentObject private var shop: Shop
    @EnvironmentObject private var router: Router
    @State private var colorId: String?
    @State private var size: String?
    @State private var qty = 1
    @State private var photo = 0
    @State private var showSizes = false
    @State private var notify = false
    @State private var finder = false
    @State private var compare = false
    @State private var sizeHint = false

    private var pid: String { id.components(separatedBy: "?color=")[0] }
    private var notifyOn: Bool { !(shop.settings.raw["notify"]["enabled"].exists && !shop.settings.raw["notify"]["enabled"].bool) }

    var body: some View {
        if let p = shop.product(pid) {
            let color = p.color(colorId)
            let pr = shop.price(p)
            let pre = p.preorder && p.preorderLeft > 0
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Crumbs(items: [("Главная", { router.reset(.home) }), ("Каталог", { router.reset(.catalog) })] + (shop.category(p.categoryId).map { c in [(c.name, { router.push(.catalog(cat: c.id, tag: nil, sale: false)) })] } ?? []))
                        .padding(.vertical, 16)
                    gallery(color)
                    VStack(alignment: .leading, spacing: 14) {
                        let badges = shop.badges(p)
                        if !badges.isEmpty { HStack(spacing: 6) { ForEach(Array(badges.enumerated()), id: \.offset) { Badge(text: $1.text, color: $1.color, filled: $1.text.contains("%")) } } }
                        Text(p.name).font(Theme.font(26, .light)).kerning(-0.78).fixedSize(horizontal: false, vertical: true)
                        if !p.sku.isEmpty { (Text("Арт. ").foregroundColor(Theme.muted) + Text(p.sku).font(Theme.font(13, .medium)).foregroundColor(Theme.text)).font(Theme.font(13)).kerning(0.26) }
                        let sum = Specs.summary(p)
                        if !sum.isEmpty { FlowRow(spacing: 6) { ForEach(sum, id: \.self) { Text($0).font(Theme.font(13)).foregroundStyle(Theme.muted).padding(.horizontal, 10).padding(.vertical, 4).overlay(Capsule().strokeBorder(Theme.line)) } } }
                        PriceView(price: pr, size: 19).padding(.top, 2)
                        if !pr.promoTitle.isEmpty { Text("Акция «\(pr.promoTitle)»" + (pr.promoEnds.isEmpty ? "" : " до " + Fmt.date(ISO.date(pr.promoEnds + "T12:00:00Z")))).font(Theme.font(13)).foregroundStyle(Theme.sale) }
                        if shop.bonusFor(pr.price) > 0 { bonusCard(shop.bonusFor(pr.price)) }
                        if pre { preorderBox(p) }
                    }.padding(.horizontal, Theme.gutter).padding(.top, 22)

                    // Цвет
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            (Text("Цвет: ").foregroundColor(Theme.muted) + Text(color.name).font(Theme.font(15, .medium)).foregroundColor(Theme.text)).font(Theme.font(15))
                            Spacer()
                            if p.colors.count > 1 { Text("\(p.colors.count) \(Fmt.plural(p.colors.count, "цвет", "цвета", "цветов"))").font(Theme.font(13)).foregroundStyle(Theme.muted) }
                        }
                        HStack(spacing: 10) {
                            ForEach(p.colors) { c in
                                Button { withAnimation { colorId = c.id; photo = 0; qty = 1 } } label: {
                                    Circle().fill(Color(hex: c.hex.isEmpty ? "#cccccc" : c.hex)).frame(width: 36, height: 36).overlay(Circle().strokeBorder(Theme.ink.opacity(0.12)))
                                        .padding(4).overlay(Circle().strokeBorder(c.id == color.id ? Theme.ink : .clear, lineWidth: 1))
                                        .opacity(c.stock == 0 ? 0.45 : 1)
                                }.accessibilityLabel(c.name)
                            }
                        }
                    }.padding(.horizontal, Theme.gutter).padding(.top, 26)

                    // Размер
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Размер").font(Theme.font(15)).foregroundStyle(sizeHint ? Theme.danger : Theme.muted)
                            Spacer()
                            if Fit.hasTable(p) { LinkButton(title: "Таблица размеров") { showSizes = true } }
                        }
                        FlowRow(spacing: 8) {
                            ForEach(color.sizes, id: \.size) { s in
                                Chip(title: s.size, on: size == s.size, out: s.stock <= 0 && !pre) { withAnimation(.easeOut(duration: 0.15)) { size = s.size; sizeHint = false; qty = 1 } }
                            }
                        }
                        Text(stockNote(p, color, pre)).font(Theme.font(14)).foregroundStyle(stockLow(color) ? Theme.warn : Theme.muted)
                        if !p.fit["modelSize"].str.isEmpty && (p.fit["modelHeight"].int ?? 0) > 0 {
                            (Text("На модели размер ") + Text(p.fit["modelSize"].str).font(Theme.font(13.5, .medium)) + Text(", рост \(p.fit["modelHeight"].int ?? 0) см")).font(Theme.font(13.5)).foregroundStyle(Theme.muted)
                        }
                        FitCheckCard(product: p, color: color, selected: size, onFind: { finder = true }, onCompare: { compare = true }, onPick: pick).padding(.top, 6)
                    }.padding(.horizontal, Theme.gutter).padding(.top, 26)

                    // Купить сейчас, избранное, доставка, гарантия
                    VStack(alignment: .leading, spacing: 12) {
                        if !waitMode(p, color, pre) && (color.stock > 0 || pre) {
                            HStack(spacing: 8) {
                                GhostButton(title: "Купить сейчас", arrow: true) { buyNow(p, color, pre) }
                                GhostButton(title: shop.isFavorite(p.id) ? "В избранном" : "В избранное", icon: shop.isFavorite(p.id) ? "heart.fill" : "heart") { shop.toggleFavorite(p.id) }
                            }
                        }
                        ShipEstimate(product: p)
                        FitGuarantee()
                    }.padding(.horizontal, Theme.gutter).padding(.top, 22)

                    VStack(spacing: 10) {
                        if !p.description.isEmpty {
                            AccordionCard(icon: "text.alignleft", title: "Описание", open: true) {
                                Text(p.description).font(Theme.font(15)).foregroundStyle(Theme.muted).lineSpacing(6).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        SpecsBlock(product: p)
                        if let d = shop.page("delivery") {
                            AccordionCard(icon: "shippingbox", title: "Доставка и возврат", hint: "СДЭК по России · возврат \(max(1, shop.settings.raw["exchange"]["days"].int ?? 14)) дней") { MarkdownText(text: d.body) }
                        }
                    }.padding(.horizontal, Theme.gutter).padding(.top, 22)

                    LookSection(product: p, mainColor: color, mainSize: size).padding(.top, 48)

                    let related = Array((shop.visibleProducts.filter { $0.id != p.id && $0.categoryId == p.categoryId } + shop.visibleProducts.filter { $0.id != p.id && $0.categoryId != p.categoryId }).prefix(4))
                    if !related.isEmpty {
                        VStack(alignment: .leading, spacing: 22) {
                            DotTitle(text: "Вам может понравиться", size: 28).padding(.horizontal, Theme.gutter)
                            ProductGrid(products: related)
                        }.padding(.top, 56)
                    }
                    RecentRow(exceptId: p.id).padding(.top, 48)
                }
                .padding(.bottom, 120)
            }
            .overlay(alignment: .bottom) { buyBar(p, color, pre) }
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if let url = URL(string: "https://albakovofficial.ru/product/\(p.slug)") {
                        ShareLink(item: url, subject: Text(p.name), message: Text(p.name)) { Image(systemName: "square.and.arrow.up").font(.system(size: 15, weight: .light)) }
                    }
                    Button { shop.toggleFavorite(p.id) } label: { Image(systemName: shop.isFavorite(p.id) ? "heart.fill" : "heart").font(.system(size: 15, weight: .light)).foregroundStyle(shop.isFavorite(p.id) ? Theme.accent : Theme.text) }
                }
            }
            .navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showSizes) {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 28) {
                            MeasuresTable(product: p)
                        }.padding(Theme.gutter)
                    }.navigationTitle(p.name).navigationBarTitleDisplayMode(.inline)
                }.presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $notify) { NotifySheet(product: p, color: color, size: size ?? "").presentationDetents([.large]) }
            .sheet(isPresented: $finder) { FitFinderSheet(product: p, color: color, onPick: pick, onCompare: { compare = true }).presentationDetents([.large]) }
            .sheet(isPresented: $compare) { FitCompareSheet(product: p, color: color, onPick: pick).presentationDetents([.large]) }
            .onAppear {
                let parts = id.components(separatedBy: "?color=")
                if colorId == nil { colorId = parts.count > 1 ? parts[1] : (p.colors.first(where: { $0.stock > 0 })?.id ?? p.colors.first?.id) }
                if size == nil, color.sizes.count == 1, color.sizes[0].stock > 0 { size = color.sizes[0].size }
                shop.addRecent(p.id)
                #if DEBUG
                // Снимок для App Store: «/product/FIRST?sizes=1» — сразу открыть таблицу размеров
                if (UserDefaults.standard.string(forKey: "screen") ?? "").contains("sizes=1") { DispatchQueue.main.asyncAfter(deadline: .now() + 1) { showSizes = true } }
                #endif
            }
        } else {
            EmptyState(icon: "bag", title: "Товар не найден", text: "Возможно, его уже нет в продаже").padding(.top, 60)
        }
    }

    // MARK: Части

    private func gallery(_ c: PColor) -> some View {
        let imgs = c.images.isEmpty ? [""] : c.images
        return TabView(selection: $photo) {
            ForEach(Array(imgs.enumerated()), id: \.offset) { i, src in ProductImage(path: src, kind: c.artKind, tone: c.artTone).tag(i) }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 524)
        .background(Theme.photo)
        .overlay(alignment: .bottom) {
            if imgs.count > 1 {
                HStack(spacing: 6) { ForEach(imgs.indices, id: \.self) { i in Capsule().fill(Theme.ink.opacity(i == photo ? 1 : 0.25)).frame(width: i == photo ? 18 : 6, height: 3) } }
                    .padding(.bottom, 14).animation(.easeOut, value: photo)
            }
        }
    }

    private func bonusCard(_ n: Int) -> some View {
        let after = shop.settings.raw["bonus"]["creditOn"].str == "done" ? "после получения" : "после оплаты"
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Б").font(Theme.font(10.5, .semibold)).foregroundStyle(.white).frame(width: 18, height: 18).background(Circle().fill(Theme.accent))
                Text("+\(Fmt.num(n)) \(Fmt.plural(n, "бонус", "бонуса", "бонусов"))").font(Theme.font(15, .medium))
            }
            Text("за покупку · 1 бонус = 1 ₽. Начислим на бонусный счёт \(after), потратить можно на следующие покупки — хоть все сразу." + (shop.user == nil ? " Нужен личный кабинет" : ""))
                .font(Theme.font(14)).foregroundStyle(Theme.muted).lineSpacing(3)
        }
        .padding(.horizontal, 16).padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading).softCard(18, alpha: 0.07)
    }

    private func preorderBox(_ p: Product) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Предзаказ").font(Theme.font(15, .medium))
                Spacer()
                if !p.preorderShip.isEmpty { Text("отправим " + shipDate(p)).font(Theme.font(13)).foregroundStyle(Theme.muted) }
            }
            if p.preorderLimit > 0 {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.surface2)
                        Capsule().fill(Theme.accentGradient).frame(width: g.size.width * min(1, CGFloat(p.preorderSold) / CGFloat(max(1, p.preorderLimit))))
                    }
                }.frame(height: 4)
                Text(p.preorderSold > 0 ? "Осталось \(p.preorderLeft) \(Fmt.plural(p.preorderLeft, "место", "места", "мест")) из \(p.preorderLimit)" : "\(p.preorderLimit) \(Fmt.plural(p.preorderLimit, "место", "места", "мест")) в партии")
                    .font(Theme.font(12.5)).foregroundStyle(Theme.muted)
            }
            Text("Размеры, которых нет в наличии, можно заказать заранее. Если не успеем к сроку — напишем и вернём деньги, если захотите.").font(Theme.font(13.5)).foregroundStyle(Theme.muted)
        }
        .padding(16).background(RoundedRectangle(cornerRadius: 18).fill(Theme.tint)).hairline(RoundedRectangle(cornerRadius: 18), 0.06)
    }
    private func shipDate(_ p: Product) -> String {
        Fmt.date(ISO.date(p.preorderShip + "T12:00:00Z")).replacingOccurrences(of: #" \d{4}$"#, with: "", options: .regularExpression)
    }

    private func stockLow(_ c: PColor) -> Bool { (c.sizes.first { $0.size == size }?.stock ?? 9) <= 2 }
    private func stockNote(_ p: Product, _ c: PColor, _ pre: Bool) -> String {
        let s = c.sizes.first { $0.size == size }, any = c.sizes.contains { $0.stock > 0 }
        if pre, let s, s.stock <= 0 { return "Предзаказ" + (p.preorderShip.isEmpty ? "" : " · отправим " + shipDate(p)) + (p.preorderLimit > 0 ? " · осталось \(p.preorderLeft) \(Fmt.plural(p.preorderLeft, "место", "места", "мест"))" : "") }
        if pre && s == nil { return "Выберите размер" }
        if !any && (s == nil || s!.stock <= 0) { return notifyOn ? "Этого цвета сейчас нет. Оставьте почту — напишем, когда он появится." : "Этого цвета сейчас нет" }
        guard let s else { return "Выберите размер" }
        if s.stock <= 0 { return "Размера \(s.size) сейчас нет. Можем сообщить на почту, когда он появится." }
        if s.stock <= 2 { return "Осталось \(s.stock) шт." }
        return "В наличии"
    }
    private func waitMode(_ p: Product, _ c: PColor, _ pre: Bool) -> Bool {
        if pre { return false }
        let s = c.sizes.first { $0.size == size }, any = c.sizes.contains { $0.stock > 0 }
        return notifyOn && ((s != nil && s!.stock <= 0) || !any)
    }
    private func pick(_ s: String) {
        guard let p = shop.product(pid) else { return }
        let c = p.color(colorId)
        guard let z = c.sizes.first(where: { $0.size == s }) else { return }
        if z.stock <= 0 && !notifyOn { Toast.shared.show("Размера \(s) в цвете «\(c.name)» сейчас нет"); return }
        withAnimation { size = s; sizeHint = false }
    }

    private func buyBar(_ p: Product, _ color: PColor, _ pre: Bool) -> some View {
        let wait = waitMode(p, color, pre), any = color.stock > 0
        let s = color.sizes.first { $0.size == size }
        let preMode = pre && ((s != nil && s!.stock <= 0) || (s == nil && !any))
        let maxQ = s.map { $0.stock > 0 ? $0.stock : pre ? (p.preorderLeft == Int.max ? 99 : p.preorderLeft) : 0 } ?? 99
        return HStack(spacing: 10) {
            if !wait {
                HStack(spacing: 0) {
                    Button { qty = max(1, qty - 1) } label: { Image(systemName: "minus").frame(width: 40, height: 50) }
                    Text("\(qty)").font(Theme.font(16)).frame(minWidth: 24)
                    Button { qty = min(maxQ, qty + 1) } label: { Image(systemName: "plus").frame(width: 40, height: 50) }
                }
                .font(.system(size: 12, weight: .light)).foregroundStyle(Theme.text)
                .background(Capsule().fill(Theme.surface)).hairline(Capsule())
            }
            if wait {
                GhostButton(title: "Сообщить о поступлении", icon: "bell", height: 54) { notify = true }
            } else {
                PrimaryButton(title: preMode ? "Оформить предзаказ" : any ? "Добавить в корзину" : "Нет в наличии в этом цвете", disabled: !any && !pre) { add(p, color, pre) }
            }
        }
        .padding(.horizontal, Theme.gutter).padding(.top, 10).padding(.bottom, 8)
        .background(LinearGradient(colors: [.white.opacity(0), .white.opacity(0.95), .white], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.35)).ignoresSafeArea())
    }

    private func add(_ p: Product, _ color: PColor, _ pre: Bool) {
        guard let size, let s = color.sizes.first(where: { $0.size == size }) else { withAnimation { sizeHint = true }; Haptic.error(); Toast.shared.show("Сначала выберите размер"); return }
        let inCart = shop.cart.first { $0.productId == p.id && $0.colorId == color.id && $0.size == size }?.qty ?? 0
        if pre && s.stock <= 0 {
            if p.preorderLeft != Int.max && inCart + qty > p.preorderLeft { Toast.shared.show("По предзаказу осталось \(p.preorderLeft) \(Fmt.plural(p.preorderLeft, "место", "места", "мест"))"); return }
        } else if inCart + qty > s.stock { Toast.shared.show("В наличии только \(s.stock) шт. этого размера в цвете «\(color.name)»"); return }
        shop.add(p, color: color.id, size: size, qty: qty)
        Haptic.success(); Toast.shared.show("Добавлено в корзину")
    }
    // «Купить сейчас»: оформляем только этот товар, корзину не трогаем
    private func buyNow(_ p: Product, _ color: PColor, _ pre: Bool) {
        guard let size, let s = color.sizes.first(where: { $0.size == size }) else { withAnimation { sizeHint = true }; Haptic.error(); Toast.shared.show("Сначала выберите размер"); return }
        if s.stock <= 0 && !pre { Toast.shared.show("Этого размера сейчас нет"); return }
        if s.stock > 0 && qty > s.stock { Toast.shared.show("В наличии только \(s.stock) шт."); return }
        shop.buyNow = [CartLine(productId: p.id, colorId: color.id, size: size, qty: qty)]
        router.push(.checkout, on: router.tab)
    }
}

// «Сообщить о поступлении»: письмо один раз, как только вещь появится
struct NotifySheet: View {
    let product: Product, color: PColor, size: String
    @EnvironmentObject private var shop: Shop
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var chosen = ""
    @State private var agree = false
    @State private var busy = false
    @State private var error: String?
    @State private var done: Bool?
    var body: some View {
        let out = color.sizes.filter { $0.stock <= 0 }
        let wholeOut = out.count == color.sizes.count
        let opts = (wholeOut && color.sizes.count > 1 ? [("", "Любой размер")] : []) + out.map { ($0.size, $0.size) }
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let already = done {
                    Image(systemName: "checkmark").font(.system(size: 20, weight: .medium)).foregroundStyle(.white).frame(width: 52, height: 52).background(Circle().fill(Theme.ok))
                    DotTitle(text: already ? "Вы уже в списке" : "Готово, ждите письмо", size: 28, dot: false)
                    Text((already ? "Заявка на этот товар уже оставлена." : "Мы сохранили вашу заявку.") + " Как только «\(product.name)» в цвете «\(color.name)» появится, напишем на \(email).").font(Theme.font(15)).foregroundStyle(Theme.muted)
                    GhostButton(title: "Хорошо") { dismiss() }
                } else {
                    Eyebrow(text: "Нет в наличии")
                    DotTitle(text: "Сообщить о поступлении", size: 28, dot: false)
                    Text("Напишем на почту один раз, как только товар появится. Без рассылок.").font(Theme.font(14.5)).foregroundStyle(Theme.muted)
                    HStack(spacing: 12) {
                        ProductImage(path: color.images.first ?? "", kind: color.artKind, tone: color.artTone).frame(width: 60, height: 76).clipShape(RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(product.name).font(Theme.font(15, .medium))
                            HStack(spacing: 6) { Circle().fill(Color(hex: color.hex.isEmpty ? "#ccc" : color.hex)).frame(width: 10, height: 10); Text(color.name).font(Theme.font(13)).foregroundStyle(Theme.muted) }
                        }
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(RoundedRectangle(cornerRadius: 16).fill(Theme.surface))
                    if opts.count > 1 {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Размер").font(Theme.font(14)).foregroundStyle(Theme.muted)
                            FlowRow(spacing: 8) { ForEach(opts, id: \.0) { o in Chip(title: o.1, on: chosen == o.0, height: 40) { chosen = o.0 } } }
                        }
                    }
                    Field(label: "Электронная почта", text: $email, placeholder: "name@example.ru", keyboard: .emailAddress, content: .emailAddress, capitalization: .never)
                    Toggle(isOn: $agree) { Text("Даю согласие на обработку адреса почты для этого уведомления").font(Theme.font(13)).foregroundStyle(Theme.muted) }.tint(Theme.ink)
                    ErrorText(text: error)
                    PrimaryButton(title: "Сообщить мне", busy: busy) { Task { await send() } }
                }
            }.padding(20)
        }
        .onAppear { email = shop.user?.email ?? ""; chosen = out.contains { $0.size == size } ? size : (opts.first?.0 ?? "") }
    }
    private func send() async {
        error = nil
        guard email.contains("@"), email.contains(".") else { error = "Проверьте электронную почту"; return }
        guard agree else { error = "Нужно согласие на обработку адреса почты"; return }
        busy = true; defer { busy = false }
        do {
            let r = try await API.shared.json("POST", "notify", body: ["productId": product.id, "colorId": color.id, "size": chosen, "email": email, "consent": true])
            withAnimation { done = r["already"].bool }
        } catch { self.error = error.localizedDescription }
    }
}
