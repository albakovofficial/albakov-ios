import SwiftUI

// Карточка товара: фото выбранного цвета, цвет, размер, «В корзину», описание, состав, уход, таблица размеров
struct ProductView: View {
    let id: String
    @EnvironmentObject private var shop: Shop
    @EnvironmentObject private var router: Router
    @State private var colorId: String?
    @State private var size: String?
    @State private var photo = 0
    @State private var showSizes = false
    @State private var notify = false
    @State private var sizeHint = false

    var body: some View {
        if let p = shop.product(id) {
            let color = p.color(colorId)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    gallery(color)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 6) { ForEach(Array(shop.badges(p).enumerated()), id: \.offset) { Badge(text: $1.text, color: $1.color) } }
                        Text(p.name).font(Theme.font(24, .light)).kerning(-0.4)
                        PriceView(price: shop.price(p), size: 19)
                        if shop.settings.bonusEnabled && shop.settings.bonusPercent > 0 {
                            Text("+\(shop.price(p).price * shop.settings.bonusPercent / 100) бонусов за покупку").font(Theme.font(13)).foregroundStyle(Theme.muted)
                        }
                    }.padding(.horizontal, Theme.gutter)

                    if p.colors.count > 1 {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Цвет: \(color.name)").font(Theme.font(14)).foregroundStyle(Theme.muted)
                            HStack(spacing: 10) {
                                ForEach(p.colors) { c in
                                    Button { withAnimation { colorId = c.id; photo = 0; size = nil } } label: {
                                        Circle().fill(Color(hex: c.hex.isEmpty ? "#cccccc" : c.hex)).frame(width: 32, height: 32)
                                            .overlay(Circle().strokeBorder(Theme.line))
                                            .padding(3).overlay(Circle().strokeBorder(c.id == color.id ? Theme.ink : .clear, lineWidth: 1.5))
                                    }
                                }
                            }
                        }.padding(.horizontal, Theme.gutter)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Размер").font(Theme.font(14)).foregroundStyle(sizeHint ? Theme.danger : Theme.muted)
                            Spacer()
                            if shop.sizeChart(p.sizeChartId) != nil { Button("Таблица размеров") { showSizes = true }.font(Theme.font(13, .medium)).foregroundStyle(Theme.text) }
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 62), spacing: 8)], spacing: 8) {
                            ForEach(color.sizes, id: \.size) { s in
                                let out = s.stock <= 0 && p.preorderLeft <= 0
                                Button { withAnimation(.easeOut(duration: 0.15)) { size = s.size; sizeHint = false }; Haptic.tap() } label: {
                                    VStack(spacing: 2) {
                                        Text(s.size).font(Theme.font(15, size == s.size ? .semibold : .regular))
                                        if s.stock > 0 && s.stock <= 2 { Text("мало").font(Theme.font(9.5)).foregroundStyle(Theme.accent) }
                                    }
                                    .frame(maxWidth: .infinity).frame(height: 50)
                                    .foregroundStyle(out ? Theme.dim : Theme.text)
                                    .background(RoundedRectangle(cornerRadius: 14).fill(size == s.size ? Theme.surface : .white))
                                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(size == s.size ? Theme.ink : Theme.line, lineWidth: size == s.size ? 1.5 : 1))
                                    .overlay(out ? AnyView(Rectangle().fill(Theme.dim).frame(height: 1).rotationEffect(.degrees(-20)).padding(.horizontal, 14)) : AnyView(EmptyView()))
                                }
                            }
                        }
                        if let s = size, color.sizes.first(where: { $0.size == s })?.stock ?? 0 <= 0, p.preorderLeft <= 0 {
                            Button { notify = true } label: { Label("Сообщить, когда \(s) появится", systemImage: "bell").font(Theme.font(14, .medium)).foregroundStyle(Theme.text) }
                        }
                    }.padding(.horizontal, Theme.gutter)

                    VStack(spacing: 0) {
                        info("Описание", p.description)
                        info("Посадка", p.fit)
                        info("Состав", p.composition)
                        info("Уход", p.care)
                        if !p.sku.isEmpty { info("Артикул", p.sku) }
                    }.padding(.horizontal, Theme.gutter)

                    let more = shop.visibleProducts.filter { $0.categoryId == p.categoryId && $0.id != p.id }.prefix(8)
                    if !more.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            SectionTitle(title: "Ещё в разделе")
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(alignment: .top, spacing: 12) { ForEach(Array(more)) { ProductCard(product: $0).frame(width: 160) } }.padding(.horizontal, Theme.gutter)
                            }
                        }
                    }
                }
                .padding(.bottom, 110)
            }
            .ignoresSafeArea(edges: .top)
            .overlay(alignment: .bottom) { buyBar(p, color) }
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if let url = URL(string: "https://albakovofficial.ru/product/\(p.slug)") {
                        ShareLink(item: url, subject: Text(p.name), message: Text(p.name)) { Image(systemName: "square.and.arrow.up") }
                    }
                    Button { shop.toggleFavorite(p.id) } label: { Image(systemName: shop.isFavorite(p.id) ? "heart.fill" : "heart").foregroundStyle(shop.isFavorite(p.id) ? Theme.danger : Theme.text) }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showSizes) { NavigationStack { ScrollView { if let c = shop.sizeChart(p.sizeChartId) { SizeChartTable(chart: c).padding(Theme.gutter) } }.navigationTitle("Размеры").navigationBarTitleDisplayMode(.inline) }.presentationDetents([.medium, .large]) }
            .sheet(isPresented: $notify) { NotifySheet(product: p, colorId: color.id, size: size ?? "").presentationDetents([.height(360)]) }
            .onAppear { if colorId == nil { colorId = p.colors.first(where: { $0.stock > 0 })?.id ?? p.colors.first?.id } }
        } else {
            EmptyState(icon: "bag", title: "Товар не найден", text: "Возможно, его уже нет в продаже")
        }
    }

    private func gallery(_ c: PColor) -> some View {
        let imgs = c.images.isEmpty ? [""] : c.images
        return TabView(selection: $photo) {
            ForEach(Array(imgs.enumerated()), id: \.offset) { i, src in RemoteImage(path: src).tag(i) }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 520)
        .overlay(alignment: .bottom) {
            if imgs.count > 1 {
                HStack(spacing: 6) { ForEach(imgs.indices, id: \.self) { i in Capsule().fill(Theme.ink.opacity(i == photo ? 1 : 0.25)).frame(width: i == photo ? 18 : 6, height: 3) } }
                    .padding(.bottom, 14).animation(.easeOut, value: photo)
            }
        }
    }

    @ViewBuilder
    private func info(_ title: String, _ text: String) -> some View {
        if !text.isEmpty {
            DisclosureGroup {
                Text(text).font(Theme.font(14.5)).foregroundStyle(Theme.muted).lineSpacing(4).frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 14)
            } label: { Text(title).font(Theme.font(16, .medium)).foregroundStyle(Theme.text).padding(.vertical, 14) }
            .tint(Theme.text)
            .overlay(alignment: .bottom) { Divider1() }
        }
    }

    private func buyBar(_ p: Product, _ color: PColor) -> some View {
        let s = color.sizes.first { $0.size == size }
        let canBuy = s.map { $0.stock > 0 || p.preorderLeft > 0 } ?? true
        return HStack(spacing: 12) {
            PrimaryButton(title: !p.available ? "Нет в наличии" : s != nil && s!.stock <= 0 && p.preorderLeft > 0 ? "Предзаказ" : "В корзину", icon: "bag", disabled: !p.available || !canBuy) {
                guard let size else { withAnimation { sizeHint = true }; Haptic.error(); Toast.shared.show("Выберите размер"); return }
                shop.add(p, color: color.id, size: size)
                Haptic.success(); Toast.shared.show("Добавлено в корзину")
            }
        }
        .padding(.horizontal, Theme.gutter).padding(.top, 12).padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }
}

// «Сообщить о поступлении»: письмо, когда размер снова будет в наличии
struct NotifySheet: View {
    let product: Product, colorId: String, size: String
    @EnvironmentObject private var shop: Shop
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Сообщим о поступлении").font(Theme.font(22, .light))
            Text("\(product.name), размер \(size). Напишем на почту, как только он появится.").font(Theme.font(14)).foregroundStyle(Theme.muted)
            Field(label: "Почта", text: $email, placeholder: "you@mail.ru", keyboard: .emailAddress, content: .emailAddress, capitalization: .never)
            ErrorText(text: error)
            PrimaryButton(title: "Сообщить мне", busy: busy) {
                busy = true; error = nil
                Task {
                    do { _ = try await API.shared.raw("POST", "notify", body: ["productId": product.id, "colorId": colorId, "size": size, "email": email, "consent": true]); Toast.shared.show("Готово — напишем, как только появится"); dismiss() }
                    catch { self.error = error.localizedDescription }
                    busy = false
                }
            }
            Text("Нажимая кнопку, вы соглашаетесь на обработку адреса почты.").font(Theme.font(11.5)).foregroundStyle(Theme.dim)
        }
        .padding(20)
        .onAppear { email = shop.user?.email ?? "" }
    }
}
