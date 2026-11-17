import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = PushManager.shared
        // Уведомления уже разрешены — обновляем адрес устройства (Apple может его сменить).
        UNUserNotificationCenter.current().getNotificationSettings { s in
            guard s.authorizationStatus == .authorized || s.authorizationStatus == .provisional else { return }
            DispatchQueue.main.async { application.registerForRemoteNotifications() }
        }
        PushManager.shared.refreshStatus()
        // ПРОВЕРКА TSan (только ветка verify, не для слияния): намеренная гонка данных при запуске — отчёт обязан появиться
        TSanControl.race()
        // Данные магазина начинают загружаться сразу при запуске
        Task { @MainActor in await Shop.shared.load() }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushManager.shared.didRegister(deviceToken: deviceToken)
    }
}

/// ПРОВЕРКА TSan (только ветка verify): два потока пишут одно число без защиты
enum TSanControl {
    nonisolated(unsafe) static var counter = 0
    static func race() { DispatchQueue.concurrentPerform(iterations: 8) { _ in for _ in 0..<1000 { counter += 1 } } }
}
