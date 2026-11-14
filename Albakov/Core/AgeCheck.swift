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

/// Окно в стиле ALBAKOV перед системным окном Apple: зачем это нужно и что именно узнает магазин
struct AgeCheckSheet: View {
    enum Step { case intro, minor, declined }
    @Binding var step: Step
    let onAdult: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ZStack {
                Circle().fill(Theme.accentGradient)
                Image(systemName: icon).font(.system(size: 24, weight: .light)).foregroundStyle(.white)
            }
            .frame(width: 56, height: 56)
            Text(title).font(Theme.font(24, .light)).kerning(-0.6).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
            Text(text).font(Theme.font(14.5)).foregroundStyle(Theme.muted).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            if step != .minor {
                VStack(alignment: .leading, spacing: 10) {
                    row("checkmark.shield", "Узнаем только «18+» — без даты рождения")
                    row("doc.text.magnifyingglass", "Без документов и фото")
                    row("clock.arrow.circlepath", "Спросим один раз")
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.tint))
            }
            Spacer(minLength: 0)
            if step == .minor {
                PrimaryButton(title: "Понятно") { dismiss() }
            } else {
                PrimaryButton(title: step == .declined ? "Поделиться возрастом" : "Продолжить", busy: busy, arrow: true) { Task { await ask() } }
                Button("Не сейчас") { dismiss() }
                    .font(Theme.font(14, .medium)).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity).frame(height: 40)
            }
        }
        .padding(.horizontal, 24).padding(.top, 28).padding(.bottom, 12)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var icon: String {
        switch step {
        case .intro: return "person.badge.shield.checkmark"
        case .minor: return "figure.and.child.holdinghands"
        case .declined: return "hand.raised"
        }
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
        case .intro: return "В вашем регионе закон требует, чтобы заказ оформлял взрослый. Сейчас Apple покажет окно — нажмите «Поделиться»."
        case .minor: return "Покупки в приложении доступны с 18 лет. Попросите родителя оформить заказ — корзина сохранится."
        case .declined: return "Это требование закона в вашем регионе. Магазин узнает только, что вам есть 18."
        }
    }
    private func row(_ icon: String, _ t: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 15, weight: .regular)).foregroundStyle(Theme.accent).frame(width: 22)
            Text(t).font(Theme.font(13.5)).foregroundStyle(Theme.text)
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
