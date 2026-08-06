import SwiftUI

struct InventoryWorkspace: View {
    @ObservedObject var model: AppModel
    @State private var searchText = ""
    @State private var location = ""
    @State private var status: InventoryStatusFilter = .all
    @State private var editorItem: HouseholdItem?
    @State private var isShowingEditor = false
    @State private var countItem: HouseholdItem?
    @State private var detailItem: HouseholdItem?

    private var activeItems: [HouseholdItem] {
        model.life.householdItems.filter { !$0.isArchived }
    }

    private var locations: [String] {
        Array(Set(activeItems.map(\.storageLocation).filter { !$0.isEmpty })).sorted()
    }

    private var filteredItems: [HouseholdItem] {
        activeItems.filter { item in
            let matchesSearch = searchText.isEmpty
                || item.name.localizedStandardContains(searchText)
                || item.storageLocation.localizedStandardContains(searchText)
            let matchesLocation = location.isEmpty || item.storageLocation == location
            let matchesStatus: Bool
            switch status {
            case .all:
                matchesStatus = true
            case .low:
                matchesStatus = model.life.isLowStock(item)
            case .expiring:
                matchesStatus = item.nearestExpirationDate.map {
                    $0 >= Calendar.current.startOfDay(for: .now)
                        && $0 <= Calendar.current.date(byAdding: .day, value: 30, to: .now)!
                } ?? false
            case .unreviewed:
                matchesStatus = !wasReviewedThisWeek(item.id)
            }
            return matchesSearch && matchesLocation && matchesStatus
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                reviewAction

                if activeItems.isEmpty {
                    LifeEmptyCard(
                        title: model.text("inventory.empty.title"),
                        message: model.text("inventory.empty.body"),
                        systemImage: "shippingbox",
                        buttonTitle: model.text("inventory.add")
                    ) {
                        editorItem = nil
                        isShowingEditor = true
                    }
                } else if filteredItems.isEmpty {
                    LifeEmptyCard(
                        title: model.text("inventory.noResults.title"),
                        message: model.text("inventory.noResults.body"),
                        systemImage: "line.3.horizontal.decrease.circle",
                        buttonTitle: model.text("inventory.filters.clear")
                    ) {
                        searchText = ""
                        location = ""
                        status = .all
                    }
                } else {
                    LifeSectionHeader(
                        title: model.text("inventory.items"),
                        detail: "\(filteredItems.count)"
                    )

                    LifeCardGrid {
                        ForEach(filteredItems) { item in
                            InventoryItemCard(
                                model: model,
                                item: item,
                                quantity: model.life.currentQuantity(for: item.id),
                                latestCount: model.life.latestInventoryCount(for: item.id),
                                wasReviewedThisWeek: wasReviewedThisWeek(item.id),
                                edit: {
                                    editorItem = item
                                    isShowingEditor = true
                                },
                                updateQuantity: {
                                    countItem = item
                                },
                                openDetails: {
                                    detailItem = item
                                },
                                archive: {
                                    model.archiveHouseholdItem(item)
                                }
                            )
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(model.text("inventory.title"))
        .searchable(
            text: $searchText,
            placement: .toolbar,
            prompt: model.text("inventory.search")
        )
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                filterMenu

                Button {
                    model.showingInventoryReview = true
                } label: {
                    Label(
                        model.text("inventory.review.start"),
                        systemImage: "checklist.checked"
                    )
                }
                .disabled(activeItems.isEmpty)

                Button {
                    editorItem = nil
                    isShowingEditor = true
                } label: {
                    Label(model.text("inventory.add"), systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isShowingEditor) {
            HouseholdItemEditorView(
                model: model,
                item: editorItem,
                isFirstItem: activeItems.isEmpty
            )
        }
        .sheet(item: $countItem) { item in
            InventoryCountEditorView(
                model: model,
                item: item,
                currentQuantity: model.life.currentQuantity(for: item.id) ?? 0,
                currentUnitPrice: model.life
                    .inventoryPriceSummary(for: item.id)?
                    .latest.unitPrice ?? 0
            )
        }
        .sheet(item: $detailItem) { item in
            InventoryItemDetailView(model: model, item: item)
        }
    }

    private var reviewAction: some View {
        let status = model.life.inventoryReviewStatus()
        let title: String
        let message: String
        let image: String
        let tint: Color

        switch status.phase {
        case .disabled:
            title = model.text("dashboard.review.disabled")
            message = model.text("dashboard.review.disabled.body")
            image = "bell.slash"
            tint = .secondary
        case .scheduled:
            title = model.text("dashboard.review.scheduled")
            message = model.text("dashboard.review.scheduled.body")
            image = "calendar"
            tint = .blue
        case .due:
            title = model.text("inventory.review.due")
            message = model.text("inventory.review.due.body")
            image = "calendar.badge.exclamationmark"
            tint = .orange
        case .completed:
            title = model.text("inventory.review.completed")
            message = model.text("inventory.review.completed.body")
            image = "checkmark.seal.fill"
            tint = .green
        }

        return LifeActionCard(
            title: title,
            message: message,
            systemImage: image,
            tint: tint,
            buttonTitle: status.isCompleted
                ? model.text("inventory.review.again")
                : model.text("inventory.review.start")
        ) {
            model.showingInventoryReview = true
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker(model.text("inventory.filter.status"), selection: $status) {
                ForEach(InventoryStatusFilter.allCases) { option in
                    Text(model.text(option.localizationKey)).tag(option)
                }
            }

            Divider()

            Picker(model.text("inventory.filter.location"), selection: $location) {
                Text(model.text("inventory.filter.all")).tag("")
                ForEach(locations, id: \.self) { Text($0).tag($0) }
            }

            Divider()

            Button(model.text("inventory.filters.clear")) {
                location = ""
                status = .all
            }
        } label: {
            Label(model.text("inventory.filters"), systemImage: "line.3.horizontal.decrease")
        }
    }

    private func wasReviewedThisWeek(_ itemID: String) -> Bool {
        guard
            let interval = Calendar.current.dateInterval(
                of: .weekOfYear,
                for: .now
            )
        else { return false }
        return model.life.inventoryReviewSessions.contains {
            interval.contains($0.scheduledWeekStart)
                && $0.reviewedItemIDs.contains(itemID)
        }
    }
}

private enum InventoryStatusFilter: String, CaseIterable, Identifiable {
    case all
    case low
    case expiring
    case unreviewed

    var id: Self { self }
    var localizationKey: String { "inventory.filter.\(rawValue)" }
}

private struct InventoryItemCard: View {
    @ObservedObject var model: AppModel
    let item: HouseholdItem
    let quantity: Decimal?
    let latestCount: InventoryCount?
    let wasReviewedThisWeek: Bool
    let edit: () -> Void
    let updateQuantity: () -> Void
    let openDetails: () -> Void
    let archive: () -> Void

    private var isLow: Bool {
        quantity.map { $0 <= item.lowStockThreshold } ?? false
    }

    private var isExpiring: Bool {
        guard let expiration = item.nearestExpirationDate else { return false }
        return expiration >= Calendar.current.startOfDay(for: .now)
            && expiration <= Calendar.current.date(byAdding: .day, value: 30, to: .now)!
    }

    var body: some View {
        LifeCard {
            Button(action: openDetails) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name)
                                .font(.headline)
                                .lineLimit(1)
                            if !item.storageLocation.isEmpty {
                                Text(item.storageLocation)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        HStack(spacing: 7) {
                            if !wasReviewedThisWeek {
                                Image(systemName: "calendar.badge.exclamationmark")
                                    .foregroundStyle(.secondary)
                                    .help(model.text("inventory.status.unreviewed"))
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Text(
                        quantity.map {
                            LifeFormat.quantity($0, unit: item.unit)
                        } ?? "—"
                    )
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .monospacedDigit()

                    HStack(spacing: 6) {
                        if quantity == nil {
                            LifeStatusPill(
                                title: model.text("inventory.status.notRecorded"),
                                systemImage: "questionmark.circle",
                                tint: .secondary
                            )
                        } else if isLow {
                            LifeStatusPill(
                                title: model.text("inventory.status.low"),
                                systemImage: "exclamationmark.triangle.fill",
                                tint: .orange
                            )
                        } else {
                            LifeStatusPill(
                                title: model.text("inventory.status.ok"),
                                systemImage: "checkmark.circle.fill",
                                tint: .green
                            )
                        }
                        if isExpiring {
                            LifeStatusPill(
                                title: model.text("inventory.status.expiring"),
                                systemImage: "calendar.badge.exclamationmark",
                                tint: .red
                            )
                        }
                    }

                    Divider()

                    Label(
                        LifeFormat.date(latestCount?.recordedAt),
                        systemImage: "clock"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .accessibilityLabel(item.name)
        .accessibilityValue(
            quantity.map { LifeFormat.quantity($0, unit: item.unit) } ?? "—"
        )
        .accessibilityHint(model.text("inventory.details.open"))
        .contextMenu {
            Button(model.text("inventory.details.open"), action: openDetails)
            Button(
                model.text("inventory.quantityPrice.update"),
                action: updateQuantity
            )
            Button(model.text("common.edit"), action: edit)
            Divider()
            Button(model.text("common.archive"), role: .destructive, action: archive)
        }
    }
}

struct InventoryMetadataRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
        .font(.caption)
    }
}

struct HouseholdItemEditorView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let item: HouseholdItem?
    let isFirstItem: Bool

    @State private var name: String
    @State private var location: String
    @State private var unit: String
    @State private var lowStockThreshold: Decimal
    @State private var initialQuantity: Decimal
    @State private var initialUnitPrice: Decimal
    @State private var hasExpiration: Bool
    @State private var expirationDate: Date
    @State private var reviewReminderEnabled = true
    @State private var reviewWeekday = 1
    @State private var reviewTime = Calendar.current.date(
        bySettingHour: 20,
        minute: 0,
        second: 0,
        of: .now
    ) ?? .now

    init(model: AppModel, item: HouseholdItem?, isFirstItem: Bool) {
        self.model = model
        self.item = item
        self.isFirstItem = isFirstItem
        _name = State(initialValue: item?.name ?? "")
        _location = State(initialValue: item?.storageLocation ?? "")
        _unit = State(initialValue: item?.unit ?? "")
        _lowStockThreshold = State(initialValue: item?.lowStockThreshold ?? 0)
        _initialQuantity = State(
            initialValue: item.flatMap { model.life.currentQuantity(for: $0.id) } ?? 0
        )
        _initialUnitPrice = State(initialValue: 0)
        _hasExpiration = State(initialValue: item?.nearestExpirationDate != nil)
        _expirationDate = State(initialValue: item?.nearestExpirationDate ?? .now)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section(model.text("inventory.editor.details")) {
                    TextField(model.text("inventory.field.name"), text: $name)
                    TextField(model.text("inventory.field.location"), text: $location)
                    TextField(model.text("inventory.field.unit"), text: $unit)
                    TextField(
                        model.text("inventory.field.lowThreshold"),
                        value: $lowStockThreshold,
                        format: .number
                    )
                    if item == nil {
                        TextField(
                            model.text("inventory.field.initialQuantity"),
                            value: $initialQuantity,
                            format: .number
                        )
                        TextField(
                            "\(model.text("inventory.price.initialUnitPrice")) (CNY/\(displayUnit))",
                            value: $initialUnitPrice,
                            format: .number.precision(.fractionLength(0...2))
                        )
                    }
                }

                Section(model.text("inventory.field.expiration")) {
                    Toggle(
                        model.text("inventory.expiration.enable"),
                        isOn: $hasExpiration
                    )
                    if hasExpiration {
                        DatePicker(
                            model.text("inventory.field.expiration"),
                            selection: $expirationDate,
                            displayedComponents: .date
                        )
                    }
                }

                if isFirstItem {
                    Section(model.text("inventory.review.schedule")) {
                        Toggle(
                            model.text("inventory.review.reminder"),
                            isOn: $reviewReminderEnabled
                        )
                        Picker(
                            model.text("inventory.review.weekday"),
                            selection: $reviewWeekday
                        ) {
                            ForEach(1...7, id: \.self) { day in
                                Text(
                                    Calendar.current.weekdaySymbols[
                                        (day - 1) % Calendar.current.weekdaySymbols.count
                                    ]
                                )
                                .tag(day)
                            }
                        }
                        DatePicker(
                            model.text("inventory.review.time"),
                            selection: $reviewTime,
                            displayedComponents: .hourAndMinute
                        )
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            LifeSheetFooter(
                cancelTitle: model.text("common.cancel"),
                saveTitle: item == nil
                    ? model.text("common.create")
                    : model.text("common.save"),
                saveDisabled: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || lowStockThreshold < 0
                    || initialQuantity < 0
                    || (item == nil && initialUnitPrice <= 0),
                cancel: { dismiss() }
            ) {
                let value = HouseholdItem(
                    id: item?.id ?? UUID().uuidString,
                    name: name,
                    storageLocation: location,
                    unit: unit,
                    lowStockThreshold: lowStockThreshold,
                    nearestExpirationDate: hasExpiration ? expirationDate : nil,
                    isArchived: false,
                    createdAt: item?.createdAt ?? .now
                )
                let didSave = model.saveHouseholdItem(
                    value,
                    initialQuantity: item == nil ? initialQuantity : nil,
                    initialUnitPrice: item == nil ? initialUnitPrice : nil
                )
                guard didSave else { return }
                if isFirstItem {
                    let time = Calendar.current.dateComponents(
                        [.hour, .minute],
                        from: reviewTime
                    )
                    model.updateInventoryReviewSchedule(
                        weekday: reviewWeekday,
                        hour: time.hour ?? 20,
                        minute: time.minute ?? 0,
                        isEnabled: reviewReminderEnabled
                    )
                    if reviewReminderEnabled {
                        Task { await model.requestNotificationPermissionIfNeeded() }
                    }
                }
                dismiss()
            }
        }
        .frame(width: 520, height: isFirstItem ? 600 : item == nil ? 470 : 420)
    }

    private var displayUnit: String {
        unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? model.text("inventory.unit.default")
            : unit
    }
}

struct InventoryCountEditorView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let item: HouseholdItem
    @State private var quantity: Decimal
    @State private var unitPrice: Decimal

    init(
        model: AppModel,
        item: HouseholdItem,
        currentQuantity: Decimal,
        currentUnitPrice: Decimal
    ) {
        self.model = model
        self.item = item
        _quantity = State(initialValue: currentQuantity)
        _unitPrice = State(initialValue: currentUnitPrice)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField(
                    item.unit.isEmpty
                        ? model.text("inventory.field.quantity")
                        : "\(model.text("inventory.field.quantity")) (\(item.unit))",
                    value: $quantity,
                    format: .number
                )
                TextField(
                    "\(model.text("inventory.price.unitPrice")) (CNY/\(displayUnit))",
                    value: $unitPrice,
                    format: .number.precision(.fractionLength(0...2))
                )
            }
            .formStyle(.grouped)

            Divider()

            LifeSheetFooter(
                cancelTitle: model.text("common.cancel"),
                saveTitle: model.text("common.save"),
                saveDisabled: quantity < 0 || unitPrice <= 0,
                cancel: { dismiss() }
            ) {
                if model.recordInventoryCount(
                    itemID: item.id,
                    quantity: quantity,
                    unitPrice: unitPrice
                ) {
                    dismiss()
                }
            }
        }
        .frame(width: 440, height: 230)
    }

    private var displayUnit: String {
        item.unit.isEmpty
            ? model.text("inventory.unit.default")
            : item.unit
    }
}

struct InventoryReviewView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [String: InventoryReviewEntry] = [:]

    private var items: [HouseholdItem] {
        model.life.householdItems
            .filter { !$0.isArchived }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.text("inventory.review.title"))
                        .font(.title2.weight(.semibold))
                    Text(model.text("inventory.review.skipHint"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(entries.count) / \(items.count)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(20)

            Divider()

            ScrollView {
                LifeCardGrid(minimumCardWidth: 240) {
                    ForEach(items) { item in
                        ReviewItemCard(
                            model: model,
                            item: item,
                            previousQuantity: model.life.currentQuantity(for: item.id),
                            previousUnitPrice: model.life
                                .inventoryPriceSummary(for: item.id)?
                                .latest.unitPrice,
                            entry: Binding(
                                get: { entries[item.id] },
                                set: { entries[item.id] = $0 }
                            )
                        )
                    }
                }
                .padding(20)
            }

            Divider()

            LifeSheetFooter(
                cancelTitle: model.text("common.cancel"),
                saveTitle: model.text("inventory.review.complete"),
                saveDisabled: entries.isEmpty || entries.values.contains {
                    $0.quantity < 0 || $0.unitPrice <= 0
                },
                cancel: { dismiss() }
            ) {
                model.completeInventoryReview(entries)
                dismiss()
            }
        }
        .frame(minWidth: 720, minHeight: 540)
    }
}

private struct ReviewItemCard: View {
    @ObservedObject var model: AppModel
    let item: HouseholdItem
    let previousQuantity: Decimal?
    let previousUnitPrice: Decimal?
    @Binding var entry: InventoryReviewEntry?

    private var quantity: Binding<Decimal> {
        Binding(
            get: { entry?.quantity ?? previousQuantity ?? 0 },
            set: {
                entry = InventoryReviewEntry(
                    quantity: $0,
                    unitPrice: entry?.unitPrice ?? previousUnitPrice ?? 0
                )
            }
        )
    }

    private var unitPrice: Binding<Decimal> {
        Binding(
            get: { entry?.unitPrice ?? previousUnitPrice ?? 0 },
            set: {
                entry = InventoryReviewEntry(
                    quantity: entry?.quantity ?? previousQuantity ?? 0,
                    unitPrice: $0
                )
            }
        )
    }

    var body: some View {
        LifeCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name)
                            .font(.headline)
                        Text(item.storageLocation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if entry != nil {
                        Button {
                            entry = nil
                        } label: {
                            Image(systemName: "arrow.uturn.backward.circle")
                        }
                        .buttonStyle(HoverIconButtonStyle(kind: .accent))
                        .help(model.text("inventory.review.skip"))
                    }
                }

                TextField(
                    item.unit.isEmpty
                        ? model.text("inventory.field.quantity")
                        : item.unit,
                    value: quantity,
                    format: .number
                )
                .textFieldStyle(.roundedBorder)

                TextField(
                    "\(model.text("inventory.price.unitPrice")) (CNY/\(displayUnit))",
                    value: unitPrice,
                    format: .number.precision(.fractionLength(0...2))
                )
                .textFieldStyle(.roundedBorder)

                HStack {
                    Text(model.text("inventory.review.previous"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(
                        previousQuantity.map {
                            LifeFormat.quantity($0, unit: item.unit)
                        } ?? "—"
                    )
                        .monospacedDigit()
                }
                .font(.caption)

                HStack {
                    Text(model.text("inventory.price.previous"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(
                        previousUnitPrice.map {
                            "\(LifeFormat.currency($0))/\(displayUnit)"
                        } ?? "—"
                    )
                    .monospacedDigit()
                }
                .font(.caption)

                if entry == nil {
                    Text(model.text("inventory.review.notEntered"))
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if entry?.unitPrice ?? 0 <= 0 {
                    Text(model.text("inventory.price.required"))
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var displayUnit: String {
        item.unit.isEmpty
            ? model.text("inventory.unit.default")
            : item.unit
    }
}
