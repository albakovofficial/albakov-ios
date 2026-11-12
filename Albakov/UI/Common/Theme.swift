import SwiftUI
import UIKit

// Фирменный стиль ALBAKOV — один в один как на сайте (public/css/app.css): белый фон, светло-серые подложки,
// капсулы цвета раздела с белым кружком-стрелкой, тонкие заголовки Montserrat с точкой цвета раздела.

/// Цвет раздела (13.63, как на сайте): женщинам — бордо, мужчинам — чёрный, детям — небесный; без раздела — чёрный.
/// Меняется вместе с разделом (Shop.gender); экраны перерисовываются целиком (RootView, .id)
enum Palette {
    static var section: String?
    /// светлый край, основной (текст и плашки с белым текстом), тёмный край перехода
    static var colors: [Color] {
        switch section {
        case "women": return [Color(hex: "#a8384b"), Color(hex: "#821f35"), Color(hex: "#5f1424")]
        case "kids": return [Color(hex: "#7cbdf0"), Color(hex: "#2f78c4"), Color(hex: "#2f72b8")]
        default: return [Color(hex: "#4a4d53"), Color(hex: "#25272b"), Color(hex: "#0e0f11")]
        }
    }
    /// светлая подложка значков
    static var tint: Color { section == "women" ? Color(hex: "#f8ecee") : section == "kids" ? Color(hex: "#e9f3fc") : Color(hex: "#eff0f2") }
}

enum Theme {
    static let ink = Color(hex: "#121417")          // текст и главные элементы
    static let text = Color(hex: "#121417")
    static var dark: Color { Palette.colors[1] }    // главные кнопки — цвет раздела
    static let night = Color(hex: "#0d0e10")        // подвал и кнопка чата
    static let muted = Color(hex: "#464b52")        // холодный графит
    static let dim = Color(hex: "#666c74")
    static let line = Color(hex: "#e3e6ea")
    static let lineStrong = Color(hex: "#c2c7cd")
    static let surface = Color(hex: "#f3f4f6")      // подложки фото и блоков
    static let surface2 = Color(hex: "#e8eaed")
    static let paper = Color.white
    static var accent: Color { Palette.colors[1] }  // цвет раздела: точка в заголовках, счётчики, выделение
    static var accentSoft: Color { Palette.colors[0] }
    static var tint: Color { Palette.tint }
    static let ok = Color(hex: "#3e6847")
    static let warn = Color(hex: "#7a5c16")
    static let danger = Color(hex: "#9e3b30")
    static let sale = Color(hex: "#d8452f")         // цена со скидкой
    static let gutter: CGFloat = 16
    static var accentGradient: LinearGradient { LinearGradient(colors: Palette.colors, startPoint: .topLeading, endPoint: .bottomTrailing) }
    /// светло-серые плитки с лёгким переходом
    static let tile = LinearGradient(colors: [Color(hex: "#f8f9fa"), Color(hex: "#eef0f2")], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let photo = LinearGradient(colors: [Color(hex: "#f6f7f8"), Color(hex: "#eceef1")], startPoint: .top, endPoint: .bottom)

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .light, .thin, .ultraLight: name = "Montserrat-Light"
        case .medium: name = "Montserrat-Medium"
        case .semibold, .bold, .heavy, .black: name = "Montserrat-SemiBold"
        default: name = "Montserrat-Regular"
        }
        return .custom(name, size: size, relativeTo: size >= 22 ? .title2 : size >= 17 ? .body : .subheadline)
    }

    static func setupAppearance() {
        let ink = UIColor(red: 0.07, green: 0.08, blue: 0.09, alpha: 1)
        let nav = UINavigationBarAppearance(); nav.configureWithOpaqueBackground()
        nav.backgroundColor = .white
        nav.shadowColor = UIColor(red: 0.89, green: 0.9, blue: 0.92, alpha: 1)
        nav.titleTextAttributes = [.font: UIFont(name: "Montserrat-Regular", size: 15) ?? .systemFont(ofSize: 15), .foregroundColor: ink]
        nav.largeTitleTextAttributes = [.font: UIFont(name: "Montserrat-Light", size: 30) ?? .systemFont(ofSize: 30), .foregroundColor: ink]
        let back = UIImage(systemName: "arrow.left", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .light))
        nav.setBackIndicatorImage(back, transitionMaskImage: back)
        nav.backButtonAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.clear]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
        UINavigationBar.appearance().tintColor = ink
        UISegmentedControl.appearance().setTitleTextAttributes([.font: UIFont(name: "Montserrat-Medium", size: 13) ?? .systemFont(ofSize: 13)], for: .normal)
    }
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces); if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        let n = UInt64(s, radix: 16) ?? 0
        self.init(.sRGB, red: Double((n >> 16) & 255) / 255, green: Double((n >> 8) & 255) / 255, blue: Double(n & 255) / 255, opacity: 1)
    }
    /// Цвет текста на плашке заданного цвета — как Pricing.inkFor на сайте
    static func ink(on hex: String) -> Color {
        var s = hex; if s.hasPrefix("#") { s.removeFirst() }
        let n = UInt64(s, radix: 16) ?? 0
        let l = (0.299 * Double((n >> 16) & 255) + 0.587 * Double((n >> 8) & 255) + 0.114 * Double(n & 255)) / 255
        return l > 0.62 ? Color(hex: "#141414") : .white
    }
}

// MARK: - Подложки и тени как на сайте: тонкая внутренняя линия + мягкая тень

extension View {
    /// Внутренняя линия 1px (box-shadow: inset 0 0 0 1px rgba(18,20,23,a))
    func hairline<S: InsettableShape>(_ shape: S, _ alpha: Double = 0.07) -> some View { overlay(shape.strokeBorder(Theme.ink.opacity(alpha), lineWidth: 1)) }
    /// Карточка: белая, скругление 18, тонкая линия
    func softCard(_ radius: CGFloat = 18, fill: Color = .white, alpha: Double = 0.08) -> some View {
        background(RoundedRectangle(cornerRadius: radius).fill(fill)).hairline(RoundedRectangle(cornerRadius: radius), alpha)
    }
    func dropShadow(_ a: Double = 0.25, y: CGFloat = 6, r: CGFloat = 16) -> some View { shadow(color: Theme.ink.opacity(a * 0.45), radius: r / 2, y: y) }
}

/// Белый кружок со стрелкой внутри чёрной кнопки (и чёрный — внутри светлой)
struct ArrowDot: View {
    var size: CGFloat = 28
    var dark = false
    var body: some View {
        Image(systemName: "arrow.right").font(.system(size: size * 0.42, weight: .regular))
            .foregroundStyle(dark ? .white : Theme.ink)
            .frame(width: size, height: size).background(Circle().fill(dark ? Theme.ink : .white))
    }
}

// MARK: - Кнопки

/// Главная кнопка сайта (.btn): капсула цвета раздела, 14 medium, разрядка .06em; со стрелкой — белый кружок справа
struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    var busy = false
    var disabled = false
    var arrow = false
    var height: CGFloat = 54
    let action: () -> Void
    var body: some View {
        Button(action: { Haptic.tap(); action() }) {
            HStack(spacing: 10) {
                if busy { ProgressView().tint(.white) } else {
                    if let icon { Image(systemName: icon).font(.system(size: 14, weight: .regular)) }
                    Text(title).font(Theme.font(14, .medium)).kerning(0.84).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity).frame(height: height)
            .overlay(alignment: .trailing) { if arrow && !busy { ArrowDot(size: height - 18).padding(.trailing, 9) } }
            .foregroundStyle(.white)
            .background(Capsule().fill(Theme.accentGradient).opacity(disabled ? 0.4 : 1))
            .shadow(color: Theme.accent.opacity(disabled ? 0 : 0.3), radius: 12, y: 10)
        }
        .buttonStyle(Pressable())
        .disabled(busy || disabled)
    }
}

/// Светлая кнопка (.btn.ghost, «Купить сейчас», «В избранное»): белая капсула с тонкой линией
struct GhostButton: View {
    let title: String
    var icon: String? = nil
    var arrow = false
    var height: CGFloat = 52
    let action: () -> Void
    var body: some View {
        Button(action: { Haptic.tap(); action() }) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).font(.system(size: 14)) }
                Text(title).font(Theme.font(14, .medium)).kerning(0.84).lineLimit(1).minimumScaleFactor(0.8)
                if arrow { Spacer(minLength: 4); ArrowDot(size: 34, dark: true) }
            }
            .padding(.leading, arrow ? 22 : 18).padding(.trailing, arrow ? 8 : 18)
            .frame(maxWidth: .infinity).frame(height: height)
            .foregroundStyle(Theme.text)
            .background(Capsule().fill(.white.opacity(0.7))).hairline(Capsule())
        }
        .buttonStyle(Pressable())
    }
}

/// «Весь каталог →», «Смотреть все →» (.sh-more): серая капсула, текст 13 и чёрный кружок со стрелкой
struct MoreButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: { Haptic.tap(); action() }) {
            HStack(spacing: 10) { Text(title).font(Theme.font(13)).kerning(0.39); ArrowDot(size: 28, dark: true) }
                .foregroundStyle(Theme.text).padding(.leading, 14).padding(.trailing, 4).frame(height: 36)
                .background(Capsule().fill(Theme.surface)).hairline(Capsule(), 0.06)
        }.buttonStyle(Pressable())
    }
}

/// Ссылка с линией снизу (.link): «Таблица размеров», «Весь каталог →»
struct LinkButton: View {
    let title: String
    var arrow = false
    var color: Color = Theme.text
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) { Text(title); if arrow { Image(systemName: "arrow.right").font(.system(size: 12, weight: .light)) } }
                .font(Theme.font(14)).kerning(0.42).foregroundStyle(color)
                .padding(.bottom, 3).overlay(alignment: .bottom) { Rectangle().fill(Theme.lineStrong).frame(height: 1) }
        }
    }
}

struct Pressable: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Капсула-переключатель (.chip): размеры, суммы, фильтры; выбранная — с тенью и рамкой цвета раздела
struct Chip: View {
    let title: String
    var on = false
    var out = false
    var dark = false
    var height: CGFloat = 44
    let action: () -> Void
    var body: some View {
        Button(action: { Haptic.tap(); action() }) {
            Text(title).font(Theme.font(14)).kerning(0.56).lineLimit(1)
                .foregroundStyle(on && dark ? .white : out ? Theme.dim : Theme.text)
                .padding(.horizontal, 14).frame(minWidth: 48).frame(height: height)
                .background(Capsule().fill(on && dark ? Theme.accent : on ? .white : Theme.surface))
                .overlay(Capsule().strokeBorder(on ? Theme.accent : Theme.ink.opacity(0.07), lineWidth: on ? 1.2 : 1))
                .overlay(out ? Rectangle().fill(Theme.dim.opacity(0.7)).frame(height: 1).rotationEffect(.degrees(-22)).padding(.horizontal, 10) : nil)
                .shadow(color: Theme.dark.opacity(on ? 0.25 : 0), radius: 8, y: 6)
        }.buttonStyle(Pressable())
    }
}

// MARK: - Текст и оформление

/// Плашка над заголовком (.eyebrow): белая капсула, оранжевая точка, 11 medium ПРОПИСНЫМИ
struct Eyebrow: View {
    let text: String
    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(Theme.accentGradient).frame(width: 6, height: 6)
            Text(text.uppercased()).font(Theme.font(11, .medium)).kerning(0.66).foregroundStyle(Theme.text).lineLimit(2)
        }
        .padding(.leading, 10).padding(.trailing, 11).padding(.vertical, 6)
        .background(Capsule().fill(.white.opacity(0.85))).hairline(Capsule())
        .shadow(color: Theme.ink.opacity(0.08), radius: 8, y: 6)
    }
}

/// Тонкий заголовок с оранжевой точкой: «Категории.», «Корзина.», «Вход.»
struct DotTitle: View {
    let text: String
    var size: CGFloat = 30
    var dot = true
    var body: some View {
        (Text(text).foregroundColor(Theme.text) + Text(dot ? "." : "").foregroundColor(Theme.accent))
            .font(Theme.font(size, .light)).kerning(-size * 0.035).lineSpacing(-2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Маленькая серая капсула рядом с заголовком: «Новинки (мужчинам)»
struct HSub: View {
    let text: String
    var body: some View {
        HStack(spacing: 5) { Circle().fill(Theme.accentGradient).frame(width: 5, height: 5); Text(text).font(Theme.font(12.5)).kerning(0.25) }
            .foregroundStyle(Theme.text).padding(.horizontal, 9).padding(.vertical, 3.5)
            .background(Capsule().fill(Theme.surface)).hairline(Capsule(), 0.06)
    }
}

/// Заголовок раздела на главной: тонкий заголовок с точкой + капсула «Весь каталог →»
struct SectionTitle: View {
    let title: String
    var sub: String? = nil
    var action: String? = nil
    var onAction: (() -> Void)? = nil
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            DotTitle(text: title, size: 30, dot: sub == nil)
            if let sub { HSub(text: sub) }
            Spacer(minLength: 6)
            if let action, let onAction, sub == nil { MoreButton(title: action, action: onAction) }
        }
        .padding(.horizontal, Theme.gutter)
        .overlay(alignment: .bottomLeading) {
            if let action, let onAction, sub != nil { MoreButton(title: action, action: onAction).padding(.horizontal, Theme.gutter).offset(y: 52) }
        }
        .padding(.bottom, sub != nil && action != nil ? 52 : 0)
    }
}

/// «Хлебные крошки» (.crumbs): серые капсулы через «/»
struct Crumbs: View {
    let items: [(String, (() -> Void)?)]
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, it in
                    if i > 0 { Text("/").font(Theme.font(12)).foregroundStyle(Theme.muted) }
                    Group {
                        if let a = it.1 { Button(action: a) { Text(it.0).padding(.horizontal, 9).padding(.vertical, 4).background(Capsule().fill(Theme.surface)) } }
                        else { Text(it.0).padding(.horizontal, 9).padding(.vertical, 4).background(Capsule().fill(Theme.surface)) }
                    }.font(Theme.font(12)).kerning(0.36).foregroundStyle(Theme.muted)
                }
            }.padding(.horizontal, Theme.gutter)
        }
    }
}

struct PriceView: View {
    let price: Price
    var size: CGFloat = 15
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Fmt.rub(price.price)).font(Theme.font(size, .medium)).kerning(0.3).foregroundStyle(price.oldPrice > 0 ? Theme.sale : Theme.text)
            if price.oldPrice > 0 { Text(Fmt.rub(price.oldPrice)).font(Theme.font(size - 2)).strikethrough().foregroundStyle(Theme.dim) }
        }
    }
}

/// Плашка на карточке (.badge): белая капсула с точкой цвета плашки; «Скидка» — целиком цветная
struct Badge: View {
    let text: String, color: String
    var filled = false
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(filled ? Color.white.opacity(0.9) : Color(hex: color)).frame(width: 6, height: 6)
            Text(text).font(Theme.font(10, .semibold)).kerning(0.4)
        }
        .padding(.leading, 7).padding(.trailing, 9).padding(.vertical, 4)
        .foregroundStyle(filled ? Color.ink(on: color) : Theme.text)
        .background(Capsule().fill(filled ? AnyShapeStyle(LinearGradient(colors: [Color(hex: color).opacity(0.85), Color(hex: color)], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Color.white.opacity(0.86))))
        .hairline(Capsule(), 0.06)
        .shadow(color: .black.opacity(0.12), radius: 6, y: 4)
    }
}

/// Бонусы за покупку (.b-pill): чёрный кружок «Б» и «+295 бонусов»
struct BonusPill: View {
    let amount: Int
    var body: some View {
        HStack(spacing: 6) {
            Text("Б").font(Theme.font(10.5, .semibold)).foregroundStyle(.white).frame(width: 18, height: 18).background(Circle().fill(Theme.accent))
            Text("+\(Fmt.num(amount)) \(Fmt.plural(amount, "бонус", "бонуса", "бонусов"))").font(Theme.font(12.5)).kerning(0.2).foregroundStyle(Theme.text)
        }
        .padding(.leading, 4).padding(.trailing, 10).padding(.vertical, 4)
        .background(Capsule().fill(.white)).hairline(Capsule(), 0.1)
    }
}

/// Сердечко (.fav-btn): белый кружок 32 с тенью
struct FavCircle: View {
    let on: Bool
    var size: CGFloat = 32
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: on ? "heart.fill" : "heart").font(.system(size: size * 0.4, weight: .regular))
                .foregroundStyle(on ? Theme.accent : Theme.text)
                .frame(width: size, height: size).background(Circle().fill(.white.opacity(0.94))).hairline(Circle())
                .shadow(color: Theme.ink.opacity(0.18), radius: 8, y: 6)
        }.buttonStyle(Pressable())
    }
}

/// Значок в квадрате (.acc-ic): серая подложка 36×36, скругление 12
struct IconTile: View {
    let icon: String
    var size: CGFloat = 36
    var fill: Color = Theme.surface
    var tint: Color = Theme.text
    var body: some View {
        Image(systemName: icon).font(.system(size: size * 0.42, weight: .light)).foregroundStyle(tint)
            .frame(width: size, height: size).background(RoundedRectangle(cornerRadius: size / 3).fill(fill))
    }
}

/// Раскрывающийся блок карточки товара (.acc details): белая карточка 18, значок, заголовок, подсказка и чёрный «+/−»
struct AccordionCard<Content: View>: View {
    let icon: String, title: String
    var hint: String = ""
    @State var open: Bool
    @ViewBuilder let content: () -> Content
    init(icon: String, title: String, hint: String = "", open: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.icon = icon; self.title = title; self.hint = hint; _open = State(initialValue: open); self.content = content
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.easeOut(duration: 0.25)) { open.toggle() } } label: {
                HStack(spacing: 14) {
                    IconTile(icon: icon)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(Theme.font(16, .medium)).foregroundStyle(Theme.text)
                        if !hint.isEmpty { Text(hint).font(Theme.font(12.5)).foregroundStyle(Theme.muted).lineLimit(2).multilineTextAlignment(.leading) }
                    }
                    Spacer(minLength: 6)
                    Image(systemName: open ? "minus" : "plus").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(open ? .white : Theme.text).frame(width: 30, height: 30)
                        .background(Circle().fill(open ? Theme.ink : .white)).overlay(Circle().strokeBorder(Theme.ink, lineWidth: 1))
                }.padding(14).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if open { content().padding(.horizontal, 18).padding(.bottom, 18).transition(.opacity) }
        }
        .background(RoundedRectangle(cornerRadius: 18).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.lineStrong.opacity(0.9)))
        .shadow(color: Color(hex: "#141416").opacity(open ? 0.12 : 0), radius: 18, y: 12)
    }
}

struct Divider1: View { var body: some View { Rectangle().fill(Theme.line).frame(height: 1) } }

/// Поле ввода (.input): серая подложка, скругление 14, высота 50, подпись 14 сверху
struct Field: View {
    let label: String
    @Binding var text: String
    var placeholder = ""
    var keyboard: UIKeyboardType = .default
    var content: UITextContentType? = nil
    var secure = false
    var capitalization: TextInputAutocapitalization = .sentences
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !label.isEmpty { Text(label).font(Theme.font(14)).kerning(0.28).foregroundStyle(Theme.muted) }
            Group {
                if secure { SecureField(placeholder, text: $text) } else { TextField(placeholder, text: $text) }
            }
            .focused($focused)
            .font(Theme.font(16))
            .keyboardType(keyboard).textContentType(content).textInputAutocapitalization(capitalization).autocorrectionDisabled(keyboard != .default)
            .padding(.horizontal, 16).frame(minHeight: 50)
            .background(RoundedRectangle(cornerRadius: 14).fill(focused ? .white : Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(focused ? Theme.accent : .clear, lineWidth: 1))
            .animation(.easeOut(duration: 0.15), value: focused)
        }
    }
}

/// Многострочное поле (.textarea) в том же стиле
struct AreaField: View {
    let label: String
    @Binding var text: String
    var placeholder = ""
    var lines: ClosedRange<Int> = 3...8
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !label.isEmpty { Text(label).font(Theme.font(14)).kerning(0.28).foregroundStyle(Theme.muted) }
            TextField(placeholder, text: $text, axis: .vertical).font(Theme.font(15.5)).lineLimit(lines)
                .padding(14).background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
        }
    }
}

/// Переключатель «Вход | Регистрация» (.seg): серая капсула, выбранное — чёрное
struct Segmented: View {
    let items: [(String, String)]
    @Binding var value: String
    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.0) { it in
                Button { withAnimation(.easeOut(duration: 0.2)) { value = it.0 } } label: {
                    Text(it.1).font(Theme.font(14)).foregroundStyle(value == it.0 ? .white : Theme.muted)
                        .padding(.horizontal, 14).frame(height: 38)
                        .background(Capsule().fill(value == it.0 ? Theme.accent : .clear))
                }.buttonStyle(.plain)
            }
        }
        .padding(4).background(Capsule().fill(Theme.surface)).hairline(Capsule(), 0.06)
    }
}

struct ErrorText: View {
    let text: String?
    var body: some View {
        if let text, !text.isEmpty { Text(text).font(Theme.font(13)).foregroundStyle(Theme.danger).fixedSize(horizontal: false, vertical: true) }
    }
}

/// Пустой экран как на сайте: мягкая карточка, белый кружок со значком, тонкий заголовок, текст и чёрная кнопка
struct EmptyState: View {
    let icon: String, title: String, text: String
    var button: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 24, weight: .light)).foregroundStyle(Theme.accent)
                .frame(width: 70, height: 70).background(Circle().fill(.white)).shadow(color: Theme.accent.opacity(0.18), radius: 16, y: 8)
            Text(title).font(Theme.font(26, .light)).kerning(-0.8).multilineTextAlignment(.center)
            Text(text).font(Theme.font(15)).foregroundStyle(Theme.muted).multilineTextAlignment(.center).lineSpacing(4)
            if let button, let action { PrimaryButton(title: button, action: action).frame(maxWidth: 230).padding(.top, 6) }
        }
        .padding(.horizontal, 24).padding(.vertical, 34).frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 24).fill(RadialGradient(colors: [Theme.tint, Theme.surface], center: .top, startRadius: 0, endRadius: 320)))
        .hairline(RoundedRectangle(cornerRadius: 24), 0.06)
        .padding(.horizontal, Theme.gutter)
    }
}

/// Всплывающая подсказка внизу экрана («Добавлено в корзину»)
final class Toast: ObservableObject {
    static let shared = Toast()
    @Published var text: String?
    private var task: Task<Void, Never>?
    func show(_ t: String) {
        task?.cancel(); text = t
        task = Task { @MainActor in try? await Task.sleep(nanoseconds: 2_400_000_000); if !Task.isCancelled { self.text = nil } }
    }
}

struct ToastView: View {
    @ObservedObject var toast = Toast.shared
    var body: some View {
        VStack {
            Spacer()
            if let t = toast.text {
                Text(t).font(Theme.font(14, .medium)).foregroundStyle(.white).multilineTextAlignment(.center)
                    .padding(.horizontal, 18).padding(.vertical, 13)
                    .background(Capsule().fill(Theme.dark)).shadow(color: .black.opacity(0.2), radius: 16, y: 8)
                    .padding(.horizontal, 24).padding(.bottom, 96).transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: toast.text)
        .allowsHitTesting(false)
    }
}
