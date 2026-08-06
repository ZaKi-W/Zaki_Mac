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
        todos: [TodoRecord],
        life: LifeData,
        language: AppLanguage,
        onFire: @escaping @Sendable (String, Date) -> Void
    ) async
    func cancelAll() async
}

enum TodoFollowUpSchedule {
    static func dates(
        scheduledDay: LocalDay,
        now: Date,
        through endDate: Date,
        calendar: Calendar
    ) -> [Date] {
        guard let dueDate = scheduledDay.date(at: .midnight, calendar: calendar) else {
            return []
        }
        let dueOnWorkday = (2...6).contains(
            calendar.component(.weekday, from: dueDate)
        )
        let firstDay: Date
        if dueOnWorkday {
            firstDay = dueDate
        } else if let next = nextWorkday(after: dueDate, calendar: calendar) {
            firstDay = next
        } else {
            return []
        }

        var result: [Date] = []
        var day = max(firstDay, calendar.startOfDay(for: now))
        while day <= endDate {
            if (2...6).contains(calendar.component(.weekday, from: day)) {
                let isDueWorkday = dueOnWorkday
                    && calendar.isDate(day, inSameDayAs: dueDate)
                let times: [LocalTime] = isDueWorkday
                    ? [LocalTime(hour: 17, minute: 30)]
                    : [
                        LocalTime(hour: 9, minute: 0),
                        LocalTime(hour: 13, minute: 30),
                        LocalTime(hour: 17, minute: 30)
                    ]
                let localDay = LocalDay(date: day, calendar: calendar)
                result.append(contentsOf: times.compactMap { time in
                    guard let fireAt = localDay.date(at: time, calendar: calendar),
                          fireAt > now,
                          fireAt <= endDate else {
                        return nil
                    }
                    return fireAt
                })
            }
            guard let nextDay = calendar.date(
                byAdding: .day,
                value: 1,
                to: day
            ) else {
                break
            }
            day = nextDay
        }
        return result
    }

    private static func nextWorkday(
        after date: Date,
        calendar: Calendar
    ) -> Date? {
        var day = date
        for _ in 0..<7 {
            guard let next = calendar.date(
                byAdding: .day,
                value: 1,
                to: day
            ) else {
                return nil
            }
            day = next
            if (2...6).contains(calendar.component(.weekday, from: day)) {
                return day
            }
        }
        return nil
    }
}

final class MomentNotificationDelegate:
    NSObject,
    UNUserNotificationCenterDelegate,
    @unchecked Sendable
{
    static let shared = MomentNotificationDelegate()
    static let todoCategoryIdentifier = "moment.todo.category"
    static let todoCompleteActionIdentifier = "moment.todo.complete"

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

        var selectionInfo: [String: String] = [
            "route": route,
            "actionIdentifier": response.actionIdentifier
        ]
        if let expenseID = notificationInfo["expenseID"] as? String {
            selectionInfo["expenseID"] = expenseID
        }
        if let todoID = notificationInfo["todoID"] as? String {
            selectionInfo["todoID"] = todoID
        }
        if let occurrenceID = notificationInfo["occurrenceID"] as? String {
            selectionInfo["occurrenceID"] = occurrenceID
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
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: MomentNotificationDelegate.todoCategoryIdentifier,
                actions: [
                    UNNotificationAction(
                        identifier: MomentNotificationDelegate
                            .todoCompleteActionIdentifier,
                        title: "完成",
                        options: []
                    )
                ],
                intentIdentifiers: [],
                options: []
            )
        ])
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
        todos: [TodoRecord],
        life: LifeData,
        language: AppLanguage,
        onFire: @escaping @Sendable (String, Date) -> Void
    ) async {
        registerTodoNotificationCategory(language: language)
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
        await synchronizeTodos(todos, language: language)
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

    private func registerTodoNotificationCategory(language: AppLanguage) {
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: MomentNotificationDelegate.todoCategoryIdentifier,
                actions: [
                    UNNotificationAction(
                        identifier: MomentNotificationDelegate
                            .todoCompleteActionIdentifier,
                        title: language == .zh ? "完成" : "Complete",
                        options: []
                    )
                ],
                intentIdentifiers: [],
                options: []
            )
        ])
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

    private struct TodoNotificationCandidate {
        let identifier: String
        let fireAt: Date
        let content: UNMutableNotificationContent
    }

    private func synchronizeTodos(
        _ todos: [TodoRecord],
        language: AppLanguage
    ) async {
        let pendingTodoIDs = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix("moment.todo.") }
        if !pendingTodoIDs.isEmpty {
            center.removePendingNotificationRequests(
                withIdentifiers: pendingTodoIDs
            )
        }

        let now = Date()
        let calendar = Calendar.current
        let todayDate = calendar.startOfDay(for: now)
        guard
            let previousMonthDate = calendar.date(
                byAdding: .month,
                value: -1,
                to: todayDate
            ),
            let scheduleHorizonDate = calendar.date(
                byAdding: .day,
                value: 370,
                to: todayDate
            ),
            let followUpHorizonDate = calendar.date(
                byAdding: .day,
                value: 30,
                to: todayDate
            )
        else {
            return
        }

        let previousMonth = LocalDay(
            date: previousMonthDate,
            calendar: calendar
        )
        let scheduleHorizon = LocalDay(
            date: scheduleHorizonDate,
            calendar: calendar
        )
        var activeOccurrenceIDs: Set<String> = []
        var candidates: [TodoNotificationCandidate] = []

        for todo in todos {
            guard let scheduledDay = todo.scheduledDay else { continue }
            let rangeStart: LocalDay
            switch todo.recurrence {
            case .none:
                rangeStart = scheduledDay
            case .monthly:
                rangeStart = previousMonth
            }

            let occurrences = todo.occurrences(
                from: rangeStart,
                through: scheduleHorizon,
                calendar: calendar
            )
            for (index, occurrence) in occurrences.enumerated()
            where occurrence.state == .active {
                guard occurrence.scheduledDay != nil else { continue }
                activeOccurrenceIDs.insert(occurrence.id.rawValue)
                if occurrence.notificationEnabled,
                   let initial = initialTodoNotification(
                       for: occurrence,
                       now: now,
                       calendar: calendar
                   ) {
                    candidates.append(initial)
                }

                guard occurrence.completionFollowUpEnabled else { continue }
                var occurrenceFollowUpEnd = followUpHorizonDate
                if occurrences.indices.contains(index + 1),
                   let nextScheduledDay = occurrences[index + 1].scheduledDay,
                   let nextOccurrenceDate = nextScheduledDay.date(
                        at: LocalTime(hour: 0, minute: 0),
                        calendar: calendar
                    ),
                   let justBeforeNextOccurrence = calendar.date(
                        byAdding: .second,
                        value: -1,
                        to: nextOccurrenceDate
                   ) {
                    occurrenceFollowUpEnd = min(
                        occurrenceFollowUpEnd,
                        justBeforeNextOccurrence
                    )
                }
                candidates.append(contentsOf: followUpNotifications(
                    for: occurrence,
                    now: now,
                    through: occurrenceFollowUpEnd,
                    calendar: calendar,
                    language: language
                ))
            }
        }

        let staleDeliveredTodoIDs = await center.deliveredNotifications()
            .filter { notification in
                let request = notification.request
                guard request.identifier.hasPrefix("moment.todo.") else {
                    return false
                }
                guard let occurrenceID = request.content
                    .userInfo["occurrenceID"] as? String else {
                    return true
                }
                return !activeOccurrenceIDs.contains(occurrenceID)
            }
            .map(\.request.identifier)
        if !staleDeliveredTodoIDs.isEmpty {
            center.removeDeliveredNotifications(
                withIdentifiers: staleDeliveredTodoIDs
            )
        }

        // Keep headroom for inventory, expense and interval reminders in the
        // system-wide pending-notification limit. Later synchronizations roll
        // this window forward.
        for candidate in candidates
            .filter({ $0.fireAt > now })
            .sorted(by: { $0.fireAt < $1.fireAt })
            .prefix(48) {
            var components = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: candidate.fireAt
            )
            components.calendar = calendar
            components.timeZone = calendar.timeZone
            do {
                try await center.add(
                    UNNotificationRequest(
                        identifier: candidate.identifier,
                        content: candidate.content,
                        trigger: UNCalendarNotificationTrigger(
                            dateMatching: components,
                            repeats: false
                        )
                    )
                )
            } catch {
                // A later activation/day/time-zone synchronization retries.
            }
        }
    }

    private func initialTodoNotification(
        for occurrence: TodoOccurrence,
        now: Date,
        calendar: Calendar
    ) -> TodoNotificationCandidate? {
        let time = occurrence.notificationTime
            ?? occurrence.startTime
            ?? LocalTime(hour: 9, minute: 0)
        guard let scheduledDay = occurrence.scheduledDay,
              let fireAt = scheduledDay.date(
            at: time,
            calendar: calendar
        ), fireAt > now else {
            return nil
        }
        return TodoNotificationCandidate(
            identifier: todoNotificationID(
                occurrenceID: occurrence.id.rawValue,
                kind: "initial",
                fireAt: fireAt
            ),
            fireAt: fireAt,
            content: todoNotificationContent(
                for: occurrence,
                body: occurrence.title,
                kind: "initial"
            )
        )
    }

    private func followUpNotifications(
        for occurrence: TodoOccurrence,
        now: Date,
        through endDate: Date,
        calendar: Calendar,
        language: AppLanguage
    ) -> [TodoNotificationCandidate] {
        guard let scheduledDay = occurrence.scheduledDay else { return [] }
        let body = language == .zh ? "完成了吗？" : "Is this done?"
        return TodoFollowUpSchedule.dates(
            scheduledDay: scheduledDay,
            now: now,
            through: endDate,
            calendar: calendar
        ).map { fireAt in
            TodoNotificationCandidate(
                identifier: todoNotificationID(
                    occurrenceID: occurrence.id.rawValue,
                    kind: "follow-up",
                    fireAt: fireAt
                ),
                fireAt: fireAt,
                content: todoNotificationContent(
                    for: occurrence,
                    body: body,
                    kind: "follow-up"
                )
            )
        }
    }

    private func todoNotificationContent(
        for occurrence: TodoOccurrence,
        body: String,
        kind: String
    ) -> UNMutableNotificationContent {
        let content = baseNotificationContent(body: body)
        if kind == "follow-up" {
            content.title = occurrence.title
        }
        content.categoryIdentifier = MomentNotificationDelegate
            .todoCategoryIdentifier
        content.userInfo = [
            "route": "todos",
            "todoID": occurrence.todoID,
            "occurrenceID": occurrence.id.rawValue,
            "kind": kind
        ]
        return content
    }

    private func todoNotificationID(
        occurrenceID: String,
        kind: String,
        fireAt: Date
    ) -> String {
        let timestamp = Int64(fireAt.timeIntervalSince1970.rounded())
        return "moment.todo.\(occurrenceID).\(kind).\(timestamp)"
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
