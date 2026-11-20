import UIKit
import UserNotifications

// Push-уведомления Apple (APNs). Адрес устройства (token) отправляется на сервер магазина:
// покупателю — о заказах, поддержке, бонусах; сотруднику — ещё и уведомления панели по его роли.
// Отладочная сборка из Xcode ходит в «песочницу» APNs, TestFlight и App Store — в боевой.
// Главный актор (этап L.2.6): состояние (статус, адрес устройства, очередь отправок) — интерфейса, его читают экраны,
// меняют Shop, AppDelegate и экраны — все на главном акторе. Методы делегата уведомлений — nonisolated: в SDK они
// не изолированы, система может вызвать их не с главного потока, а состояние PushManager они не трогают
@MainActor
final class PushManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = PushManager()

    static var environment: String {
        #if DEBUG
        return "development"
        #else
        return "production"
        #endif
    }

    @Published private(set) var status: UNAuthorizationStatus = .notDetermined
    private(set) var token: String?
    /// Сервер для подписки; var — для юнит-тестов (как Shop.api)
    var api = API.shared
    /// Последняя отправка подписки и её номер. Вызовы — на главном акторе (вход, выход, панель, AppDelegate)
    private(set) var sync: Task<Void, Never>?
    private var generation = 0

    private override init() { super.init() }

    func refreshStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { s in
            let status = s.authorizationStatus   // на главную очередь — только значение, не сами настройки (они не Sendable)
            DispatchQueue.main.async { self.status = status }
        }
    }

    /// Спросить разрешение (по нажатию «Включить уведомления»). true — разрешили.
    @discardableResult
    func request() async -> Bool {
        let c = UNUserNotificationCenter.current()
        let granted = (try? await c.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        refreshStatus()
        if granted { UIApplication.shared.registerForRemoteNotifications() }
        return granted
    }

    func didRegister(deviceToken: Data) {
        token = deviceToken.map { String(format: "%02x", $0) }.joined()
        resend()
    }

    /// Сообщить серверу адрес устройства: после получения адреса, входа и выхода из кабинета.
    /// Отправки идут строго по очереди: новая ждёт, пока прежняя закончит начатый запрос, и только потом шлёт свои.
    /// Прежняя, у которой появилась более новая, оставшиеся запросы не шлёт — последней всегда выполняется самая новая.
    /// Раньше каждая отправка шла сама по себе: при быстром выходе и входе «отписать сотрудника» могло прийти на сервер
    /// после «подписать», и панель переставала присылать уведомления (аудит K, K-M3). Начатый запрос не отменяем:
    /// отмена на телефоне не отзывает уже отправленный запрос, и сервер мог бы получить его позже нового
    func resend() {
        guard let token else { return }
        generation += 1
        let n = generation, previous = sync, api = self.api
        sync = Task { @MainActor in
            await previous?.value
            let current = { n == self.generation && !Task.isCancelled }
            guard current() else { return }
            let apns: [String: Any] = ["token": token, "env": PushManager.environment]
            _ = try? await api.raw("POST", "push/subscribe", body: ["apns": apns, "scope": "customer"])
            // Уведомления панели (новые заказы, оплаты, вопросы) — только пока на этом iPhone вошли под аккаунтом сотрудника.
            // Вышли или вошёл покупатель — устройство перестаёт получать уведомления панели (1.0.2)
            guard current(), Shop.shared.loaded else { return }   // кто вошёл, станет известно после загрузки — тогда resend вызовется снова
            if Shop.shared.isStaff { _ = try? await api.raw("POST", "push/subscribe", body: ["apns": apns, "scope": "staff"]) }
            else { _ = try? await api.raw("POST", "push/unsubscribe", body: ["endpoint": "apns:" + token, "scope": "staff"]) }
        }
    }

    var endpoint: String? { token.map { "apns:" + $0 } }

    // MARK: UNUserNotificationCenterDelegate
    // Приложение открыто — всё равно показываем баннер (новый заказ, ответ поддержки).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound, .badge])
    }

    // Нажали на уведомление — открываем нужный экран по адресу из поля "url" ("/order/42", "/admin?s=orders&id=…").
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if let link = info["url"] as? String, !link.isEmpty {
            DispatchQueue.main.async { Router.shared.open(path: link) }
        }
        completionHandler()
    }
}
