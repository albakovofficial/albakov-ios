import UIKit
import UserNotifications

// Push-уведомления Apple (APNs). Адрес устройства (token) отправляется на сервер магазина:
// покупателю — о заказах, поддержке, бонусах; сотруднику — ещё и уведомления панели по его роли.
// Отладочная сборка из Xcode ходит в «песочницу» APNs, TestFlight и App Store — в боевой.
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

    private override init() { super.init() }

    func refreshStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { s in
            DispatchQueue.main.async { self.status = s.authorizationStatus }
        }
    }

    /// Спросить разрешение (по нажатию «Включить уведомления»). true — разрешили.
    @discardableResult
    func request() async -> Bool {
        let c = UNUserNotificationCenter.current()
        let granted = (try? await c.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        refreshStatus()
        if granted { await MainActor.run { UIApplication.shared.registerForRemoteNotifications() } }
        return granted
    }

    func didRegister(deviceToken: Data) {
        token = deviceToken.map { String(format: "%02x", $0) }.joined()
        resend()
    }

    /// Сообщить серверу адрес устройства: после получения адреса, входа и выхода из кабинета.
    func resend() {
        guard let token else { return }
        Task { @MainActor in
            let apns: [String: Any] = ["token": token, "env": PushManager.environment]
            _ = try? await API.shared.raw("POST", "push/subscribe", body: ["apns": apns, "scope": "customer"])
            if Shop.shared.isStaff { _ = try? await API.shared.raw("POST", "push/subscribe", body: ["apns": apns, "scope": "staff"]) }
        }
    }

    var endpoint: String? { token.map { "apns:" + $0 } }

    // MARK: UNUserNotificationCenterDelegate
    // Приложение открыто — всё равно показываем баннер (новый заказ, ответ поддержки).
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound, .badge])
    }

    // Нажали на уведомление — открываем нужный экран по адресу из поля "url" ("/order/42", "/admin?s=orders&id=…").
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if let link = info["url"] as? String, !link.isEmpty {
            DispatchQueue.main.async { Router.shared.open(path: link) }
        }
        completionHandler()
    }
}
