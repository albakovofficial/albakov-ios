import SwiftUI
import UIKit

// Фирменный стиль ALBAKOV: чёрно-белый, шрифт Montserrat, тонкие линии, капсульные кнопки — как на сайте.
enum Theme {
    static let ink = Color(hex: "#121417")
    static let text = Color(hex: "#121417")
    static let muted = Color(hex: "#5b616a")
    static let dim = Color(hex: "#8a9098")
    static let line = Color(hex: "#e3e6ea")
    static let surface = Color(hex: "#f3f4f6")
    static let paper = Color.white
    static let accent = Color(hex: "#ff6a3d")
    static let ok = Color(hex: "#3e6847")
    static let danger = Color(hex: "#c4362b")
    static let gutter: CGFloat = 16

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
        let ui = UIFont(name: "Montserrat-Medium", size: 11) ?? .systemFont(ofSize: 11)
        let tab = UITabBarAppearance(); tab.configureWithDefaultBackground()
        tab.backgroundColor = UIColor.white.withAlphaComponent(0.96)
        for item in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
            item.normal.titleTextAttributes = [.font: ui, .foregroundColor: UIColor(white: 0.55, alpha: 1)]
            item.selected.titleTextAttributes = [.font: ui, .foregroundColor: UIColor(red: 0.07, green: 0.08, blue: 0.09, alpha: 1)]
            item.normal.iconColor = UIColor(white: 0.55, alpha: 1)
            item.selected.iconColor = UIColor(red: 0.07, green: 0.08, blue: 0.09, alpha: 1)
        }
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
        let nav = UINavigationBarAppearance(); nav.configureWithDefaultBackground()
        nav.backgroundColor = UIColor.white.withAlphaComponent(0.96)
        nav.shadowColor = UIColor(white: 0.9, alpha: 1)
        nav.titleTextAttributes = [.font: UIFont(name: "Montserrat-Medium", size: 16) ?? .systemFont(ofSize: 16)]
        nav.largeTitleTextAttributes = [.font: UIFont(name: "Montserrat-Light", size: 32) ?? .systemFont(ofSize: 32)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().tintColor = UIColor(red: 0.07, green: 0.08, blue: 0.09, alpha: 1)
    }
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces); if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        let n = UInt64(s, radix: 16) ?? 0
        self.init(.sRGB, red: Double((n >> 16) & 255) / 255, green: Double((n >> 8) & 255) / 255, blue: Double(n & 255) / 255, opacity: 1)
    }
    /// Читаемый цвет текста поверх фона плашки (как inkFor на сайте)
    static func ink(on hex: String) -> Color {
        var s = hex; if s.hasPrefix("#") { s.removeFirst() }
        let n = UInt64(s, radix: 16) ?? 0
        let l = (0.299 * Double((n >> 16) & 255) + 0.587 * Double((n >> 8) & 255) + 0.114 * Double(n & 255)) / 255
        return l > 0.62 ? Color(hex: "#141414") : .white
    }
}

// MARK: - Кнопки

struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    var busy = false
    var disabled = false
    let action: () -> Void
    var body: some View {
        Button(action: { Haptic.tap(); action() }) {
            HStack(spacing: 10) {
                if busy { ProgressView().tint(.white) } else {
                    Text(title).font(Theme.font(15, .medium)).kerning(0.4)
                    if let icon { Image(systemName: icon).font(.system(size: 14, weight: .medium)) }
                }
            }
            .frame(maxWidth: .infinity).frame(height: 54)
            .foregroundStyle(.white)
            .background(Capsule().fill(Theme.ink.opacity(disabled ? 0.35 : 1)))
        }
        .buttonStyle(Pressable())
        .disabled(busy || disabled)
    }
}

struct GhostButton: View {
    let title: String
    var icon: String? = nil
    let action: () -> Void
    var body: some View {
        Button(action: { Haptic.tap(); action() }) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).font(.system(size: 14)) }
                Text(title).font(Theme.font(15, .medium))
            }
            .frame(maxWidth: .infinity).frame(height: 50)
            .foregroundStyle(Theme.text)
            .background(Capsule().strokeBorder(Theme.line, lineWidth: 1))
        }
        .buttonStyle(Pressable())
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

// MARK: - Текст и оформление

struct Eyebrow: View {
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(LinearGradient(colors: [Color(hex: "#ff9a5c"), Color(hex: "#ff5a3c")], startPoint: .top, endPoint: .bottom)).frame(width: 6, height: 6)
            Text(text.uppercased()).font(Theme.font(11, .medium)).kerning(1.2).foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Capsule().fill(.white)).overlay(Capsule().strokeBorder(Theme.line))
    }
}

struct SectionTitle: View {
    let title: String
    var action: String? = nil
    var onAction: (() -> Void)? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            (Text(title).font(Theme.font(28, .light)) + Text(".").font(Theme.font(28, .light)).foregroundColor(Theme.accent))
                .kerning(-0.6)
            Spacer()
            if let action, let onAction {
                Button(action: onAction) {
                    HStack(spacing: 6) { Text(action).font(Theme.font(13, .medium)); Image(systemName: "arrow.right").font(.system(size: 12)) }
                        .foregroundStyle(Theme.text)
                }
            }
        }
        .padding(.horizontal, Theme.gutter)
    }
}

struct PriceView: View {
    let price: Price
    var size: CGFloat = 15
    var body: some View {
        HStack(spacing: 8) {
            Text(Fmt.rub(price.price)).font(Theme.font(size, .medium)).foregroundStyle(price.oldPrice > 0 ? Theme.danger : Theme.text)
            if price.oldPrice > 0 { Text(Fmt.rub(price.oldPrice)).font(Theme.font(size - 2)).strikethrough().foregroundStyle(Theme.dim) }
        }
    }
}

struct Badge: View {
    let text: String, color: String
    var body: some View {
        Text(text).font(Theme.font(10.5, .semibold)).kerning(0.3)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .foregroundStyle(Color.ink(on: color))
            .background(Capsule().fill(Color(hex: color)))
    }
}

struct Divider1: View { var body: some View { Rectangle().fill(Theme.line).frame(height: 1) } }

/// Поле ввода в фирменном стиле: подпись сверху, тонкая рамка
struct Field: View {
    let label: String
    @Binding var text: String
    var placeholder = ""
    var keyboard: UIKeyboardType = .default
    var content: UITextContentType? = nil
    var secure = false
    var capitalization: TextInputAutocapitalization = .sentences
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(Theme.font(13)).foregroundStyle(Theme.muted)
            Group {
                if secure { SecureField(placeholder, text: $text) } else { TextField(placeholder, text: $text) }
            }
            .font(Theme.font(16))
            .keyboardType(keyboard).textContentType(content).textInputAutocapitalization(capitalization).autocorrectionDisabled(keyboard != .default)
            .padding(.horizontal, 14).frame(height: 50)
            .background(RoundedRectangle(cornerRadius: 14).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line))
        }
    }
}

struct ErrorText: View {
    let text: String?
    var body: some View {
        if let text, !text.isEmpty { Text(text).font(Theme.font(13)).foregroundStyle(Theme.danger).fixedSize(horizontal: false, vertical: true) }
    }
}

struct EmptyState: View {
    let icon: String, title: String, text: String
    var button: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 30, weight: .light)).foregroundStyle(Theme.text)
                .frame(width: 76, height: 76).background(Circle().fill(Theme.surface))
            Text(title).font(Theme.font(20, .light)).multilineTextAlignment(.center)
            Text(text).font(Theme.font(14)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            if let button, let action { PrimaryButton(title: button, action: action).frame(maxWidth: 280).padding(.top, 6) }
        }
        .padding(32).frame(maxWidth: .infinity)
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
                Text(t).font(Theme.font(14, .medium)).foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 13)
                    .background(Capsule().fill(Theme.ink)).shadow(color: .black.opacity(0.2), radius: 16, y: 8)
                    .padding(.bottom, 90).transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: toast.text)
        .allowsHitTesting(false)
    }
}
