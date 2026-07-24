import Foundation
import UserNotifications

enum NotificationAuthorizationState: Equatable, Sendable {
    case unknown
    case allowed
    case denied
}

protocol ReminderScheduling: Sendable {
    func requestAuthorization() async -> Bool
    func authorizationState() async -> NotificationAuthorizationState
    func synchronize(
        _ reminders: [ReminderRecord],
        onFire: @escaping @Sendable (String, Date) -> Void
    ) async
    func cancelAll() async
}

final class MomentNotificationDelegate:
    NSObject,
    UNUserNotificationCenterDelegate,
    @unchecked Sendable
{
    static let shared = MomentNotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        NotificationCenter.default.post(name: .momentShowMainWindow, object: nil)
    }
}

actor ReminderScheduler: ReminderScheduling {
    private let center: UNUserNotificationCenter
    private var monitorTasks: [String: Task<Void, Never>] = [:]

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        center.delegate = MomentNotificationDelegate.shared
    }

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    func authorizationState() async -> NotificationAuthorizationState {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .allowed
        case .denied:
            return .denied
        case .notDetermined:
            return .unknown
        @unknown default:
            return .unknown
        }
    }

    func synchronize(
        _ reminders: [ReminderRecord],
        onFire: @escaping @Sendable (String, Date) -> Void
    ) async {
        for task in monitorTasks.values {
            task.cancel()
        }
        monitorTasks.removeAll()
        center.removeAllPendingNotificationRequests()

        let deliveredIDs = Set(
            await center.deliveredNotifications().map(\.request.identifier)
        )
        for reminder in reminders where reminder.isEnabled {
            await schedule(
                reminder,
                wasDelivered: deliveredIDs.contains(notificationID(reminder.id)),
                onFire: onFire
            )
        }
    }

    func cancelAll() async {
        for task in monitorTasks.values {
            task.cancel()
        }
        monitorTasks.removeAll()
        center.removeAllPendingNotificationRequests()
    }

    private func schedule(
        _ reminder: ReminderRecord,
        wasDelivered: Bool,
        onFire: @escaping @Sendable (String, Date) -> Void
    ) async {
        let now = Date()
        let dueAt = reminder.nextTriggerAt
            ?? now.addingTimeInterval(TimeInterval(reminder.intervalSeconds))
        let delay = max(0, dueAt.timeIntervalSince(now))

        if !reminder.repeats, delay == 0 {
            if !wasDelivered {
                await deliverNow(reminder)
            }
            onFire(reminder.id, now)
            return
        }

        if reminder.repeats && reminder.intervalSeconds < 60 {
            monitorTasks[reminder.id] = subminuteTask(
                reminder,
                initialDelay: delay,
                onFire: onFire
            )
            return
        }

        let content = notificationContent(for: reminder)
        let trigger: UNTimeIntervalNotificationTrigger
        if reminder.repeats {
            trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: TimeInterval(max(60, reminder.intervalSeconds)),
                repeats: true
            )
        } else {
            trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, delay),
                repeats: false
            )
        }

        do {
            try await center.add(
                UNNotificationRequest(
                    identifier: notificationID(reminder.id),
                    content: content,
                    trigger: trigger
                )
            )
        } catch {
            // The in-process monitor still keeps state accurate.
        }

        monitorTasks[reminder.id] = monitorTask(
            reminder,
            initialDelay: delay,
            onFire: onFire
        )
    }

    private func monitorTask(
        _ reminder: ReminderRecord,
        initialDelay: TimeInterval,
        onFire: @escaping @Sendable (String, Date) -> Void
    ) -> Task<Void, Never> {
        Task {
            do {
                try await sleep(seconds: initialDelay)
                while !Task.isCancelled {
                    onFire(reminder.id, .now)
                    guard reminder.repeats else { break }
                    try await sleep(seconds: TimeInterval(reminder.intervalSeconds))
                }
            } catch {
                return
            }
        }
    }

    private func subminuteTask(
        _ reminder: ReminderRecord,
        initialDelay: TimeInterval,
        onFire: @escaping @Sendable (String, Date) -> Void
    ) -> Task<Void, Never> {
        Task {
            do {
                try await sleep(seconds: initialDelay)
                while !Task.isCancelled {
                    await deliverNow(reminder)
                    onFire(reminder.id, .now)
                    try await sleep(seconds: TimeInterval(reminder.intervalSeconds))
                }
            } catch {
                return
            }
        }
    }

    private func sleep(seconds: TimeInterval) async throws {
        guard seconds > 0 else { return }
        try await Task.sleep(
            for: .milliseconds(Int64((seconds * 1_000).rounded()))
        )
    }

    private func deliverNow(_ reminder: ReminderRecord) async {
        do {
            try await center.add(
                UNNotificationRequest(
                    identifier: notificationID(reminder.id),
                    content: notificationContent(for: reminder),
                    trigger: nil
                )
            )
        } catch {
            return
        }
    }

    private func notificationContent(for reminder: ReminderRecord) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleDisplayName"
        ) as? String ?? "Moment"
        content.body = reminder.content
        content.sound = .default
        content.userInfo = ["reminderID": reminder.id]
        return content
    }

    private func notificationID(_ reminderID: String) -> String {
        "moment.reminder.\(reminderID)"
    }
}
