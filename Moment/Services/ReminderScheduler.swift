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
    func deliverPreview(body: String) async -> Bool
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

    func deliverPreview(body: String) async -> Bool {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBody.isEmpty else { return false }

        do {
            let content = baseNotificationContent(body: trimmedBody)
            content.userInfo = ["preview": true]
            try await center.add(
                UNNotificationRequest(
                    identifier: "moment.preview.\(UUID().uuidString)",
                    content: content,
                    trigger: nil
                )
            )
            return true
        } catch {
            return false
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

        let pendingRequests = await center.pendingNotificationRequests()
        let activeReminderIDs = Set(
            reminders
                .filter(\.isEnabled)
                .flatMap {
                    [notificationID($0.id), nextNotificationID($0)]
                }
        )
        let staleReminderIDs = pendingRequests
            .map(\.identifier)
            .filter {
                $0.hasPrefix("moment.reminder.")
                    && !activeReminderIDs.contains($0)
            }
        if !staleReminderIDs.isEmpty {
            center.removePendingNotificationRequests(
                withIdentifiers: staleReminderIDs
            )
        }
        let pendingByIdentifier = Dictionary(
            uniqueKeysWithValues: pendingRequests.map {
                ($0.identifier, $0)
            }
        )

        let deliveredIDs = Set(
            await center.deliveredNotifications().map(\.request.identifier)
        )
        for reminder in reminders where reminder.isEnabled {
            await schedule(
                reminder,
                existingRequest: pendingByIdentifier[notificationID(reminder.id)],
                existingNextRequest: pendingByIdentifier[
                    nextNotificationID(reminder)
                ],
                wasDelivered: deliveredIDs.contains(notificationID(reminder.id))
                    || deliveredIDs.contains(nextNotificationID(reminder)),
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
        existingRequest: UNNotificationRequest?,
        existingNextRequest: UNNotificationRequest?,
        wasDelivered: Bool,
        onFire: @escaping @Sendable (String, Date) -> Void
    ) async {
        let now = Date()
        let dueAt = reminder.nextTriggerAt
            ?? now.addingTimeInterval(TimeInterval(reminder.intervalSeconds))
        var delay = max(0, dueAt.timeIntervalSince(now))
        let hasExistingRequest = existingRequest != nil
        let hasExistingNextRequest = existingNextRequest != nil
        let existingRequestMatches = request(
            existingRequest,
            matches: reminder
        )
        let existingNextRequestMatches = initialRequest(
            existingNextRequest,
            matches: reminder
        )

        let wasOverdue = delay == 0
        if wasOverdue {
            if !wasDelivered {
                await deliverNow(reminder)
            }
            onFire(reminder.id, now)
            guard reminder.repeats else { return }
            delay = TimeInterval(reminder.intervalSeconds)
        }

        if reminder.repeats && reminder.intervalSeconds < 60 {
            if hasExistingRequest || hasExistingNextRequest {
                center.removePendingNotificationRequests(
                    withIdentifiers: [
                        notificationID(reminder.id),
                        nextNotificationID(reminder)
                    ]
                )
            }
            monitorTasks[reminder.id] = subminuteTask(
                reminder,
                initialDelay: delay,
                onFire: onFire
            )
            return
        }

        let requiresInitialAlignment = reminder.repeats
            && !hasExistingRequest
            && delay + 0.5 < TimeInterval(reminder.intervalSeconds)

        if requiresInitialAlignment,
           !existingNextRequestMatches {
            do {
                try await center.add(
                    UNNotificationRequest(
                        identifier: nextNotificationID(reminder),
                        content: notificationContent(for: reminder),
                        trigger: UNTimeIntervalNotificationTrigger(
                            timeInterval: max(1, delay),
                            repeats: false
                        )
                    )
                )
            } catch {
                // The repeating backup remains available.
            }
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

        if wasOverdue || !existingRequestMatches {
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
        }

        monitorTasks[reminder.id] = monitorTask(
            reminder,
            initialDelay: delay,
            realignsSystemSchedule: requiresInitialAlignment
                || hasExistingNextRequest,
            onFire: onFire
        )
    }

    private func request(
        _ request: UNNotificationRequest?,
        matches reminder: ReminderRecord
    ) -> Bool {
        guard
            let request,
            request.content.body == reminder.content,
            let trigger = request.trigger as? UNTimeIntervalNotificationTrigger,
            trigger.repeats == reminder.repeats
        else {
            return false
        }

        if reminder.repeats {
            return abs(
                trigger.timeInterval - TimeInterval(reminder.intervalSeconds)
            ) < 0.5
        }
        guard
            let scheduledDueAt = request.content.userInfo["dueAt"] as? TimeInterval,
            let dueAt = reminder.nextTriggerAt?.timeIntervalSince1970
        else {
            return false
        }
        return abs(scheduledDueAt - dueAt) < 0.5
    }

    private func initialRequest(
        _ request: UNNotificationRequest?,
        matches reminder: ReminderRecord
    ) -> Bool {
        guard
            let request,
            request.content.body == reminder.content,
            let trigger = request.trigger as? UNTimeIntervalNotificationTrigger,
            !trigger.repeats,
            let scheduledDueAt = request.content.userInfo["dueAt"] as? TimeInterval,
            let dueAt = reminder.nextTriggerAt?.timeIntervalSince1970
        else {
            return false
        }
        return abs(scheduledDueAt - dueAt) < 0.5
    }

    private func monitorTask(
        _ reminder: ReminderRecord,
        initialDelay: TimeInterval,
        realignsSystemSchedule: Bool = false,
        onFire: @escaping @Sendable (String, Date) -> Void
    ) -> Task<Void, Never> {
        Task {
            do {
                try await sleep(seconds: initialDelay)
                if realignsSystemSchedule, !Task.isCancelled {
                    await realignRepeatingNotification(reminder)
                }
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

    private func realignRepeatingNotification(
        _ reminder: ReminderRecord
    ) async {
        center.removePendingNotificationRequests(
            withIdentifiers: [notificationID(reminder.id)]
        )
        do {
            try await center.add(
                UNNotificationRequest(
                    identifier: notificationID(reminder.id),
                    content: notificationContent(for: reminder),
                    trigger: UNTimeIntervalNotificationTrigger(
                        timeInterval: TimeInterval(reminder.intervalSeconds),
                        repeats: true
                    )
                )
            )
        } catch {
            // The in-process monitor continues to advance state.
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
        var userInfo: [String: Any] = [
            "reminderID": reminder.id,
            "intervalSeconds": reminder.intervalSeconds,
            "repeats": reminder.repeats
        ]
        if let dueAt = reminder.nextTriggerAt {
            userInfo["dueAt"] = dueAt.timeIntervalSince1970
        }
        content.userInfo = userInfo
        return content
    }

    private func baseNotificationContent(
        body: String
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleDisplayName"
        ) as? String ?? "Zaki"
        content.body = body
        content.sound = .default
        return content
    }

    private func notificationID(_ reminderID: String) -> String {
        "moment.reminder.\(reminderID)"
    }

    private func nextNotificationID(_ reminder: ReminderRecord) -> String {
        let dueTimestamp = Int64(
            (reminder.nextTriggerAt ?? reminder.createdAt)
                .timeIntervalSince1970
                .rounded()
        )
        return "moment.reminder.\(reminder.id).next.\(dueTimestamp)"
    }
}
