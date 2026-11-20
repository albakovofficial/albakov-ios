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
        // Клавиатура закрывается, когда страницу прокручивают (1.0.0)
        UIScrollView.appearance().keyboardDismissMode = .interactive
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

// MARK: - Подложки как на сайте: тонкая внутренняя линия, без теней (решение владельца 12.11)

extension View {
    /// Внутренняя линия 1px (box-shadow: inset 0 0 0 1px rgba(18,20,23,a))
    func hairline<S: InsettableShape>(_ shape: S, _ alpha: Double = 0.07) -> some View { overlay(shape.strokeBorder(Theme.ink.opacity(alpha), lineWidth: 1)) }
    /// Карточка: белая, скругление 18, тонкая линия
    func softCard(_ radius: CGFloat = 18, fill: Color = .white, alpha: Double = 0.08) -> some View {
        background(RoundedRectangle(cornerRadius: radius).fill(fill)).hairline(RoundedRectangle(cornerRadius: radius), alpha)
    }
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

/// Чип (размер, фильтр, вариант): выбранный — заливка цвета раздела с белым текстом
struct Chip: View {
    let title: String
    var on = false
    var out = false
    var height: CGFloat = 44
    /// Все оставшиеся штуки этого размера уже в корзине покупателя — значок сумки в углу
    var inBag = false
    let action: () -> Void
    var body: some View {
        Button(action: { Haptic.tap(); action() }) {
            Text(title).font(Theme.font(14, on ? .medium : .regular)).kerning(0.56).lineLimit(1)
                .foregroundStyle(on ? .white : out ? Theme.dim : Theme.text)
                .padding(.horizontal, 14).frame(minWidth: 48).frame(height: height)
                .background(Capsule().fill(on ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Theme.surface)))
                .overlay(Capsule().strokeBorder(Theme.ink.opacity(on ? 0 : 0.07), lineWidth: 1))
                .overlay(out ? Rectangle().fill(on ? Color.white.opacity(0.7) : Theme.dim.opacity(0.7)).frame(height: 1).rotationEffect(.degrees(-22)).padding(.horizontal, 10) : nil)
                .overlay(alignment: .topTrailing) {
                    if inBag {
                        Image(systemName: "bag.fill").font(.system(size: 8.5, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: 19, height: 19).background(Circle().fill(Theme.accent)).overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                            .offset(x: 4, y: -4)
                    }
                }
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
    }
}

/// Тонкий заголовок с оранжевой точкой: «Категории.», «Корзина.», «Вход.»
struct DotTitle: View {
    let text: String
    var size: CGFloat = 30
    var dot = true
    var body: some View {
        // без точки в конце заголовка — везде (владелец 15.11); параметр dot оставлен, чтобы не трогать вызовы
        Text(text).foregroundColor(Theme.text)
            .font(Theme.font(size, .light)).kerning(-size * 0.035).lineSpacing(-2)
            // крупный системный шрифт: заголовок не растёт бесконечно и уменьшается, а не рвёт слово посередине (аудит 16.11, M-7)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge).lineLimit(3).minimumScaleFactor(0.6)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Заголовок раздела на главной: тонкий заголовок и капсула «Смотреть все →» в одну строку
/// (капсула раздела «мужчинам» убрана — владелец 15.11)
struct SectionTitle: View {
    let title: String
    var action: String? = nil
    var onAction: (() -> Void)? = nil
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            DotTitle(text: title, size: 30).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 6)
            if let action, let onAction { MoreButton(title: action, action: onAction).fixedSize() }
        }
        .padding(.horizontal, Theme.gutter)
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
            Text(Fmt.rub(price.price)).font(Theme.font(size, .medium)).kerning(0.3).foregroundStyle(price.oldPrice > 0 ? Theme.sale : Theme.text).lineLimit(1).minimumScaleFactor(0.6).layoutPriority(1)
            if price.oldPrice > 0 { Text(Fmt.rub(price.oldPrice)).font(Theme.font(size - 2)).strikethrough().foregroundStyle(Theme.dim).lineLimit(1).minimumScaleFactor(0.6) }
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

/// Сердечко (.fav-btn): белый кружок 32 с тонкой линией
struct FavCircle: View {
    let on: Bool
    var size: CGFloat = 32
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: on ? "heart.fill" : "heart").font(.system(size: size * 0.4, weight: .regular))
                .foregroundStyle(on ? Theme.accent : Theme.text)
                .frame(width: size, height: size).background(Circle().fill(.white.opacity(0.94))).hairline(Circle())
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

/// Ошибка загрузки внутри экрана (Q-3): причина и кнопка повтора — вместо пустого места или «0 ₽»
struct ErrorRetry: View {
    let text: String
    var button = "Повторить"
    let retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ErrorText(text: text)
            Button(button, action: retry).font(Theme.font(14, .medium)).foregroundStyle(Theme.text)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Пустой экран как на сайте: мягкая карточка, белый кружок со значком, тонкий заголовок, текст и чёрная кнопка
struct EmptyState: View {
    let icon: String, title: String
    var text: String = ""
    var button: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 24, weight: .light)).foregroundStyle(Theme.accent)
                .frame(width: 70, height: 70).background(Circle().fill(.white)).hairline(Circle())
            Text(title).font(Theme.font(26, .light)).kerning(-0.8).multilineTextAlignment(.center)
            if !text.isEmpty { Text(text).font(Theme.font(15)).foregroundStyle(Theme.muted).multilineTextAlignment(.center).lineSpacing(4) }
            if let button, let action { PrimaryButton(title: button, action: action).frame(maxWidth: 230).padding(.top, 6) }
        }
        .padding(.horizontal, 24).padding(.vertical, 34).frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 24).fill(RadialGradient(colors: [Theme.tint, Theme.surface], center: .top, startRadius: 0, endRadius: 320)))
        .hairline(RoundedRectangle(cornerRadius: 24), 0.06)
        .padding(.horizontal, Theme.gutter)
    }
    /// Данные экрана не загрузились (Q-3): причина и «Повторить» вместо пустого экрана
    static func loadFailed(_ text: String, retry: @escaping () -> Void) -> EmptyState {
        EmptyState(icon: "wifi.exclamationmark", title: "Не удалось загрузить", text: text, button: "Повторить", action: retry)
    }
}

/// Всплывающая подсказка внизу экрана («Добавлено в корзину»). Текст и задача показа принадлежат главному актору
/// (этап L.2.2): show вызывают экраны и @MainActor-код, сообщение рисует ToastView в окне ToastWindow
@MainActor
final class Toast: ObservableObject {
    static let shared = Toast()
    @Published var text: String?
    private var task: Task<Void, Never>?
    /// Сообщение об ошибке: отменённый запрос (nil) не показываем (1.0.3)
    func show(_ t: String?) { if let t, !t.isEmpty { show(t) } }
    func show(_ t: String) {
        task?.cancel()
        task = Task { @MainActor in
            guard !Task.isCancelled else { return }   // сразу пришёл следующий тост — показываем его
            ToastWindow.setVisible(true)   // окно показывается и отрисовывается пустым — тост появится с анимацией
            self.text = t
            // отмена сна — это новый тост вместо этого: он сам решит, когда спрятать окно
            try? await Task.sleep(nanoseconds: 2_400_000_000); guard !Task.isCancelled else { return }
            self.text = nil
            try? await Task.sleep(nanoseconds: 500_000_000); guard !Task.isCancelled else { return }   // тост уходит с анимацией
            ToastWindow.setVisible(false)
        }
    }
}

/// Тосты — в отдельном окне поверх всех листов и полноэкранных окон (Q-4). Раньше ToastView был частью корневого
/// экрана, и открытый лист закрывал сообщение: например, об ошибке отправки фото в обращении. Окно не принимает
/// касаний — они проходят к приложению под ним. Показывается только пока виден тост (ревью этапа B), чтобы
/// постоянное верхнее окно не влияло на строку состояния. Ограничение размера шрифта — как у всего приложения
@MainActor enum ToastWindow {
    private static var window: UIWindow?
    static func setVisible(_ on: Bool) {
        window?.isHidden = !on
        if on { window?.layoutIfNeeded() }   // отрисовать окно до появления текста: иначе первый тост появился бы без анимации
    }
    /// Окно привязано к сцене. Если система подключила новую сцену, окно создаётся заново в ней,
    /// иначе тосты пропали бы до перезапуска (ревью этапа B)
    static func install() {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first, window?.windowScene !== scene else { return }
        window?.isHidden = true   // прежнее окно (если было) больше не показываем
        let w = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: ToastView().dynamicTypeSize(...DynamicTypeSize.accessibility1))
        host.view.backgroundColor = .clear
        w.rootViewController = host
        w.windowLevel = .alert + 1
        w.isUserInteractionEnabled = false
        w.isHidden = true
        window = w
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
                    .background(Capsule().fill(Theme.dark))
                    .padding(.horizontal, 24).padding(.bottom, 96).transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: toast.text)
        .allowsHitTesting(false)
    }
}
