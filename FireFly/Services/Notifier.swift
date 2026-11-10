import Foundation
import UserNotifications

/// Avisos locales: «Se fue la luz», «Batería baja» y «Volvió la luz».
/// Se generan en el teléfono cuando la app ve el cambio de estado, así que funcionan
/// sin la cuenta de pago de Apple Developer (las push remotas sí la necesitan).
@MainActor
final class Notifier {
    enum Kind: String, CaseIterable {
        case outage = "notify.outage"
        case lowBattery = "notify.low"
        case restored = "notify.restored"

        var defaultOn: Bool { self != .restored }
    }

    nonisolated static func isEnabled(_ kind: Kind) -> Bool {
        UserDefaults.standard.object(forKey: kind.rawValue) as? Bool ?? kind.defaultOn
    }

    nonisolated static func setEnabled(_ kind: Kind, _ on: Bool) {
        UserDefaults.standard.set(on, forKey: kind.rawValue)
    }

    func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    func send(_ kind: Kind, title: String, body: String) {
        guard Notifier.isEnabled(kind) else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: kind.rawValue + "." + UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
