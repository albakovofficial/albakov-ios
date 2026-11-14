import SwiftUI
import UIKit
#if canImport(DeclaredAgeRange)
import DeclaredAgeRange
#endif

/// Проверка возраста перед заказом (1.0.2) — законы о магазинах приложений (Техас, Юта, Луизиана и др.).
/// Где закон этого требует, Apple знает сама (`isEligibleForAgeFeatures`); в России и других странах проверки нет.
/// Спрашиваем один раз: взрослому ответ запоминаем, окно больше не появляется.
@MainActor
enum AgeCheck {
    enum Outcome { case adult, minor, declined }
    private static let adultKey = "ageCheck.adult"

    /// Нужно ли спросить возраст перед заказом
    static func needed() async -> Bool {
        if UserDefaults.standard.bool(forKey: adultKey) { return false }
        #if canImport(DeclaredAgeRange)
        if #available(iOS 26.2, *) {
            return (try? await AgeRangeService.shared.isEligibleForAgeFeatures) ?? false
        }
        #endif
        return false
    }

    /// Системное окно Apple «Поделиться возрастной категорией». Узнаём только «до 18» или «18+».
    static func request() async -> Outcome {
        #if canImport(DeclaredAgeRange)
        if #available(iOS 26.2, *) {
            guard let vc = topController() else { return .adult }
            do {
                let response = try await AgeRangeService.shared.requestAgeRange(ageGates: 18, in: vc)
                switch response {
                case .sharing(let range):
                    if let upper = range.upperBound, upper < 18 { return .minor }
                    UserDefaults.standard.set(true, forKey: adultKey)
                    return .adult
                case .declinedSharing:
                    return .declined
                @unknown default:
                    return .declined
                }
            } catch {
                return .adult   // сервис Apple недоступен — заказу не мешаем
            }
        }
        #endif
        return .adult
    }

    private static func topController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var vc = scene?.windows.first { $0.isKeyWindow }?.rootViewController ?? scene?.windows.first?.rootViewController
        while let next = vc?.presentedViewController { vc = next }
        return vc
    }
}

/// Окно в стиле ALBAKOV перед системным окном Apple (вариант 1 «Обложка 18+», утверждён 14.11):
/// сверху обложка цвета раздела с крупным «18+», ниже заголовок, текст, три плашки и кнопка.
/// При появлении «18+» плавно проявляется с лёгким увеличением, плашки выезжают по очереди.
struct AgeCheckSheet: View {
    enum Step { case intro, minor, declined }
    @Binding var step: Step
    let onAdult: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var shown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cover
            VStack(alignment: .leading, spacing: 14) {
                Text(title).font(Theme.font(24, .light)).kerning(-0.6).foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(text).font(Theme.font(14)).foregroundStyle(Theme.muted).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                if step != .minor {
                    HStack(spacing: 8) {
                        tile("18+", "без даты рождения", 0)
                        tile("0", "документов и фото", 1)
                        tile("1 раз", "и больше не спросим", 2)
                    }.padding(.top, 4)
                }
                Spacer(minLength: 8)
                if step == .minor {
                    PrimaryButton(title: "Понятно") { dismiss() }
                } else {
                    PrimaryButton(title: step == .declined ? "Поделиться возрастом" : "Продолжить", busy: busy) { Task { await ask() } }
                    Button("Не сейчас") { dismiss() }
                        .font(Theme.font(14)).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity).frame(height: 40)
                }
            }
            .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 10)
        }
        .presentationDetents([.height(640), .large])
        .presentationDragIndicator(.hidden)
        .onAppear { withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.15)) { shown = true } }
    }

    /// Обложка: цвет раздела, ALBAKOV, крупное «18+»
    private var cover: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Text("ALBAKOV").font(Theme.font(13)).kerning(5).foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading)
                Capsule().fill(.white.opacity(0.45)).frame(width: 36, height: 4)
            }
            Spacer(minLength: 0)
            HStack(alignment: .bottom) {
                Text("18+").font(Theme.font(104, .light)).kerning(-6).foregroundStyle(.white)
                    .opacity(shown ? 1 : 0).scaleEffect(shown ? 1 : 0.86, anchor: .bottomLeading)
                Spacer()
                Text("ПРОВЕРКА\nВОЗРАСТА").font(Theme.font(11)).kerning(1.4).lineSpacing(3)
                    .multilineTextAlignment(.trailing).foregroundStyle(.white.opacity(0.85))
                    .padding(.bottom, 10)
            }
        }
        .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 14)
        .frame(height: 210)
        .background(Theme.accentGradient)
    }

    private func tile(_ big: String, _ small: String, _ i: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(big).font(Theme.font(15, .medium)).foregroundStyle(Theme.accent)
            Text(small).font(Theme.font(11.5)).foregroundStyle(Theme.text).lineSpacing(1).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10).padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.line, lineWidth: 1))
        .opacity(shown ? 1 : 0).offset(y: shown ? 0 : 14)
        .animation(.spring(response: 0.6, dampingFraction: 0.85).delay(0.3 + Double(i) * 0.08), value: shown)
    }

    private var title: String {
        switch step {
        case .intro: return "Один шаг перед заказом"
        case .minor: return "Заказ оформит взрослый"
        case .declined: return "Без возраста заказ не оформить"
        }
    }
    private var text: String {
        switch step {
        case .intro: return "В вашем регионе закон требует, чтобы заказ оформлял взрослый. Apple покажет окно — нажмите «Поделиться»."
        case .minor: return "Покупки в приложении доступны с 18 лет. Попросите родителя оформить заказ — корзина сохранится."
        case .declined: return "Это требование закона в вашем регионе. Магазин узнает только, что вам есть 18."
        }
    }
    private func ask() async {
        busy = true; defer { busy = false }
        switch await AgeCheck.request() {
        case .adult: dismiss(); onAdult()
        case .minor: withAnimation { step = .minor }
        case .declined: withAnimation { step = .declined }
        }
    }
}
