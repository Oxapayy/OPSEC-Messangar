import Foundation
import UserNotifications
import UIKit

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    func configure() {
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
            }
        } catch {
            print("Notification auth failed: \(error)")
        }
    }

    func uploadAPNsToken(_ token: String) async {
        // TODO(backend): persist token so the VPS can wake this device.
        do { try await APIClient.shared.registerAPNsToken(token) }
        catch { print("APNs upload failed: \(error)") }
    }

    /// Local delivery for a new-message event received over the WebSocket
    /// while in the background. Used until real APNs is wired up.
    func deliverLocal(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString,
                                        content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }
}
