import Foundation
import UserNotifications

final class Notifier: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = Notifier()

    var onOpen: ((String) -> Void)?

    private var available: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app" }

    func setup() {
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func post(sessionId: String, title: String, subtitle: String, body: String) {
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
        content.body = body
        content.sound = .default
        content.threadIdentifier = sessionId
        content.userInfo = ["session": sessionId]
        let request = UNNotificationRequest(identifier: sessionId, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        guard available else { return .denied }
        return await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func sendTest() {
        post(
            sessionId: "threadhaven-test",
            title: "ThreadHaven",
            subtitle: String(localized: "Test notification"),
            body: String(localized: "You will see this when a chat needs your approval or finishes its turn.")
        )
    }

    func clear(_ sessionId: String) {
        guard available else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [sessionId])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let id = response.notification.request.content.userInfo["session"] as? String {
            DispatchQueue.main.async { self.onOpen?(id) }
        }
        completionHandler()
    }
}
