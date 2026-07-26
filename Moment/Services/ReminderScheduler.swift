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
        life: LifeData,
        language: AppLanguage,
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
        NotificationCenter.default.post(
            name: Notification.Name("moment.show-main-window"),
            object: nil
        )

        let notificationInfo = response.notification.request.content.userInfo
        guard let route = notificationInfo["route"] as? String else {
            return
        }

        var selectionInfo: [String: String] = ["route": route]
        if let expenseID = notificationInfo["expenseID"] as? String {
            selectionInfo["expenseID"] = expenseID
        }
        NotificationCenter.default.post(
            name: Notification.Name("moment.notification-selection"),
            object: nil,
            userInfo: selectionInfo
        )
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
        life: LifeData,
        language: AppLanguage,
        onFire: @escaping @Sendable (String, Date) -> Void
    ) async {
        for task in monitorTasks.values {
            task.cancel()
        }
        monitorTasks.removeAll()
        await removePendingMomentNotifications()

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

        await scheduleInventoryReview(from: life, language: language)
        await scheduleRecurringExpenses(from: life, language: language)
    }

    func cancelAll() async {
        for task in monitorTasks.values {
            task.cancel()
        }
        monitorTasks.removeAll()
        await removePendingMomentNotifications()
    }

    private func removePendingMomentNotifications() async {
        let identifiers = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix("moment.") }
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private func scheduleInventoryReview(
        from life: LifeData,
        language: AppLanguage
    ) async {
        let settings = life.inventoryReviewSettings
        guard
            settings.isEnabled,
            life.householdItems.contains(where: { !$0.isArchived })
        else {
            return
        }

        var dateComponents = DateComponents()
        dateComponents.weekday = min(max(settings.weekday, 1), 7)
        dateComponents.hour = min(max(settings.hour, 0), 23)
        dateComponents.minute = min(max(settings.minute, 0), 59)

        let content = baseNotificationContent(
            body: L10n.text("notification.inventory.review", language)
        )
        content.userInfo = ["route": "inventory"]

        do {
            try await center.add(
                UNNotificationRequest(
                    identifier: "moment.inventory.review",
                    content: content,
                    trigger: UNCalendarNotificationTrigger(
                        dateMatching: dateComponents,
                        repeats: true
                    )
                )
            )
        } catch {
            // A later synchronization will retry scheduling.
        }
    }

    private func scheduleRecurringExpenses(
        from life: LifeData,
        language: AppLanguage
    ) async {
        let now = Date()
        let calendar = Calendar.current
        let delivered = await center.deliveredNotifications()

        for expense in life.recurringExpenses
        where expense.isEnabled && expense.reminderEnabled {
            guard let dueDate = expense.nextDueDate(
                onOrAfter: now,
                calendar: calendar
            ) else {
                continue
            }

            let reminderDate = calendar.date(
                byAdding: .day,
                value: -max(0, expense.reminderLeadDays),
                to: dueDate
            ) ?? dueDate
            let identifier = "moment.expense.\(expense.id)"
            if let previous = delivered.first(where: {
                $0.request.identifier == identifier
            }) {
                let previousDueAt = previous.request.content.userInfo["dueAt"]
                    as? TimeInterval
                if let previousDueAt,
                   abs(previousDueAt - dueDate.timeIntervalSince1970) < 1,
                   reminderDate <= now {
                    continue
                }
                center.removeDeliveredNotifications(withIdentifiers: [identifier])
            }
            let triggerDate = reminderDate > now
                ? reminderDate
                : now.addingTimeInterval(1)
            var dateComponents = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: triggerDate
            )
            dateComponents.calendar = calendar
            dateComponents.timeZone = calendar.timeZone

            let content = baseNotificationContent(
                body: L10n.text("notification.expense.due", language)
            )
            content.title = expense.name
            content.userInfo = [
                "route": "expense",
                "expenseID": expense.id,
                "dueAt": dueDate.timeIntervalSince1970
            ]

            do {
                try await center.add(
                    UNNotificationRequest(
                        identifier: identifier,
                        content: content,
                        trigger: UNCalendarNotificationTrigger(
                            dateMatching: dateComponents,
                            repeats: false
                        )
                    )
                )
            } catch {
                // A later synchronization will retry scheduling.
            }
        }
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
        let content = baseNotificationContent(body: reminder.content)
        content.userInfo = ["reminderID": reminder.id]
        return content
    }

    private func baseNotificationContent(
        body: String
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleDisplayName"
        ) as? String ?? "Moment"
        content.body = body
        content.sound = .default
        return content
    }

    private func notificationID(_ reminderID: String) -> String {
        "moment.reminder.\(reminderID)"
    }
}
