import Charts
import SwiftUI

struct InventoryItemDetailView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let item: HouseholdItem

    @State private var selectedDate: Date?
    @State private var isShowingCountEditor = false
    @State private var isShowingItemEditor = false
    @State private var correctionRecord: InventoryPriceRecord?

    private var currentItem: HouseholdItem {
        model.life.householdItems.first { $0.id == item.id } ?? item
    }

    private var records: [InventoryPriceRecord] {
        model.life.inventoryPriceHistory(for: item.id)
            .sorted {
                if $0.purchasedAt == $1.purchasedAt {
                    return $0.createdAt < $1.createdAt
                }
                return $0.purchasedAt < $1.purchasedAt
            }
    }

    private var summary: InventoryPriceSummary? {
        model.life.inventoryPriceSummary(for: item.id)
    }

    private var selectedRecord: InventoryPriceRecord? {
        guard let selectedDate else { return nil }
        return records.min {
            abs($0.purchasedAt.timeIntervalSince(selectedDate))
                < abs($1.purchasedAt.timeIntervalSince(selectedDate))
        }
    }

    private var unit: String {
        currentItem.unit.isEmpty
            ? model.text("inventory.unit.default")
            : currentItem.unit
    }

    private var currentQuantity: Decimal? {
        model.life.currentQuantity(for: item.id)
    }

    private var latestCount: InventoryCount? {
        model.life.latestInventoryCount(for: item.id)
    }

    private var isLowStock: Bool {
        currentQuantity.map { $0 <= currentItem.lowStockThreshold } ?? false
    }

    private var isExpiring: Bool {
        guard let expiration = currentItem.nearestExpirationDate else {
            return false
        }
        return expiration >= Calendar.current.startOfDay(for: .now)
            && expiration
                <= Calendar.current.date(byAdding: .day, value: 30, to: .now)!
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(currentItem.name)
                        .font(.title2.weight(.semibold))
                    Text(detailSubtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    isShowingCountEditor = true
                } label: {
                    Label(
                        model.text("inventory.quantityPrice.update"),
                        systemImage: "square.and.pencil"
                    )
                }
                .buttonStyle(.borderedProminent)

                Button {
                    isShowingItemEditor = true
                } label: {
                    Label(model.text("common.edit"), systemImage: "pencil")
                }
                .buttonStyle(.bordered)

                Menu {
                    Button(
                        model.text("common.archive"),
                        role: .destructive
                    ) {
                        model.archiveHouseholdItem(currentItem)
                        dismiss()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(HoverIconButtonStyle(size: 26))
                .help(model.text("common.close"))
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    inventoryOverview

                    if let summary {
                        LifeSectionHeader(
                            title: model.text("inventory.price.history"),
                            detail: "\(records.count)",
                            systemImage: "chart.xyaxis.line",
                            showsDivider: true
                        )

                        LifeCardGrid {
                            LifeMetricCard(
                                title: model.text("inventory.price.latest"),
                                value: priceLabel(summary.latest.unitPrice),
                                detail: LifeFormat.date(summary.latest.purchasedAt),
                                systemImage: "tag.fill",
                                tint: .blue
                            )
                            LifeMetricCard(
                                title: model.text("inventory.price.lowest"),
                                value: priceLabel(summary.lowest),
                                detail: model.text("inventory.price.lowest.detail"),
                                systemImage: "arrow.down.circle.fill",
                                tint: .green
                            )
                            LifeMetricCard(
                                title: model.text("inventory.price.average"),
                                value: priceLabel(summary.averageUnitPrice),
                                detail: model.text("inventory.price.average.detail"),
                                systemImage: "sum",
                                tint: .orange
                            )
                        }

                        LifeCard {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 7) {
                                        Text(model.text("inventory.price.trend"))
                                            .font(.headline)
                                        comparisonPill(summary)
                                    }
                                    Spacer()
                                    if let selectedRecord {
                                        Text(
                                            "\(LifeFormat.date(selectedRecord.purchasedAt)) · \(priceLabel(selectedRecord.unitPrice))"
                                        )
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                    }
                                }

                                InventoryPriceChart(
                                    records: records,
                                    lowestPrice: summary.lowest,
                                    selectedDate: $selectedDate,
                                    unit: unit,
                                    model: model
                                )
                                .frame(height: 270)
                            }
                        }

                        LifeSectionHeader(
                            title: model.text("inventory.price.records"),
                            detail: "\(records.count)",
                            systemImage: "clock.arrow.circlepath",
                            showsDivider: true
                        )

                        LifeCardGrid {
                            ForEach(records.reversed()) { record in
                                InventoryPriceRecordCard(
                                    model: model,
                                    record: record,
                                    unit: unit,
                                    canCorrect: record.id == records.last?.id,
                                    correct: {
                                        correctionRecord = record
                                    }
                                )
                            }
                        }
                    } else {
                        LifeEmptyCard(
                            title: model.text("inventory.price.empty.title"),
                            message: model.text("inventory.price.empty.body"),
                            systemImage: "chart.xyaxis.line",
                            buttonTitle: model.text("inventory.quantityPrice.update")
                        ) {
                            isShowingCountEditor = true
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 820, minHeight: 650)
        .sheet(isPresented: $isShowingCountEditor) {
            InventoryCountEditorView(
                model: model,
                item: currentItem,
                currentQuantity: model.life.currentQuantity(for: item.id) ?? 0,
                currentUnitPrice: summary?.latest.unitPrice ?? 0
            )
        }
        .sheet(isPresented: $isShowingItemEditor) {
            HouseholdItemEditorView(
                model: model,
                item: currentItem,
                isFirstItem: false
            )
        }
        .sheet(item: $correctionRecord) { record in
            LatestInventoryPriceCorrectionView(
                model: model,
                item: currentItem,
                record: record
            )
        }
    }

    private var detailSubtitle: String {
        let details = model.text("inventory.details.title")
        guard !currentItem.storageLocation.isEmpty else { return details }
        return "\(details) · \(currentItem.storageLocation)"
    }

    private var inventoryOverview: some View {
        LifeCard {
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(model.text("inventory.field.quantity"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    Text(
                        currentQuantity.map {
                            LifeFormat.quantity($0, unit: currentItem.unit)
                        } ?? "—"
                    )
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .monospacedDigit()

                    HStack(spacing: 6) {
                        if currentQuantity == nil {
                            LifeStatusPill(
                                title: model.text("inventory.status.notRecorded"),
                                systemImage: "questionmark.circle",
                                tint: .secondary
                            )
                        } else if isLowStock {
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
                }
                .frame(minWidth: 210, alignment: .leading)

                Divider()
                    .frame(minHeight: 112)

                VStack(alignment: .leading, spacing: 8) {
                    InventoryMetadataRow(
                        title: model.text("inventory.field.location"),
                        value: currentItem.storageLocation.isEmpty
                            ? "—"
                            : currentItem.storageLocation
                    )
                    InventoryMetadataRow(
                        title: model.text("inventory.field.lowThreshold"),
                        value: LifeFormat.quantity(
                            currentItem.lowStockThreshold,
                            unit: currentItem.unit
                        )
                    )
                    InventoryMetadataRow(
                        title: model.text("inventory.lastCount"),
                        value: LifeFormat.date(latestCount?.recordedAt)
                    )
                    InventoryMetadataRow(
                        title: model.text("inventory.expiration"),
                        value: LifeFormat.date(currentItem.nearestExpirationDate)
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func comparisonPill(_ summary: InventoryPriceSummary) -> some View {
        switch summary.comparison {
        case .insufficientHistory:
            LifeStatusPill(
                title: model.text("inventory.price.comparison.insufficient"),
                systemImage: "ellipsis",
                tint: .secondary
            )
        case .historicalLow:
            LifeStatusPill(
                title: model.text("inventory.price.comparison.lowest"),
                systemImage: "arrow.down.to.line",
                tint: .green
            )
        case let .cheaper(percentage):
            LifeStatusPill(
                title: "\(percentageLabel(percentage)) \(model.text("inventory.price.comparison.cheaper"))",
                systemImage: "arrow.down.right",
                tint: .green
            )
        case .equal:
            LifeStatusPill(
                title: model.text("inventory.price.comparison.equal"),
                systemImage: "equal",
                tint: .blue
            )
        case let .moreExpensive(percentage):
            LifeStatusPill(
                title: "\(percentageLabel(percentage)) \(model.text("inventory.price.comparison.expensive"))",
                systemImage: "arrow.up.right",
                tint: .orange
            )
        }
    }

    private func priceLabel(_ price: Decimal) -> String {
        "\(LifeFormat.currency(price))/\(unit)"
    }

    private func percentageLabel(_ percentage: Decimal) -> String {
        "\(percentage.formatted(.number.precision(.fractionLength(0...1))))%"
    }
}

private struct InventoryPriceChart: View {
    let records: [InventoryPriceRecord]
    let lowestPrice: Decimal
    @Binding var selectedDate: Date?
    let unit: String
    @ObservedObject var model: AppModel

    private var selectedRecord: InventoryPriceRecord? {
        guard let selectedDate else { return nil }
        return records.min {
            abs($0.purchasedAt.timeIntervalSince(selectedDate))
                < abs($1.purchasedAt.timeIntervalSince(selectedDate))
        }
    }

    var body: some View {
        Chart {
            ForEach(records) { record in
                if records.count == 1 {
                    PointMark(
                        x: .value(model.text("inventory.price.purchaseDate"), record.purchasedAt),
                        y: .value(model.text("inventory.price.unitPrice"), record.unitPrice.lifeDoubleValue)
                    )
                    .foregroundStyle(Color.accentColor)
                    .symbolSize(60)
                } else {
                    LineMark(
                        x: .value(model.text("inventory.price.purchaseDate"), record.purchasedAt),
                        y: .value(model.text("inventory.price.unitPrice"), record.unitPrice.lifeDoubleValue)
                    )
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                    PointMark(
                        x: .value(model.text("inventory.price.purchaseDate"), record.purchasedAt),
                        y: .value(model.text("inventory.price.unitPrice"), record.unitPrice.lifeDoubleValue)
                    )
                    .foregroundStyle(Color.accentColor)
                    .symbolSize(30)
                }
            }

            RuleMark(
                y: .value(
                    model.text("inventory.price.lowest"),
                    lowestPrice.lifeDoubleValue
                )
            )
            .foregroundStyle(Color.green.opacity(0.65))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
            .annotation(position: .top, alignment: .leading) {
                Text(
                    "\(model.text("inventory.price.lowest")) \(LifeFormat.currency(lowestPrice))/\(unit)"
                )
                .font(.caption2)
                .foregroundStyle(.green)
            }

            if let selectedRecord {
                RuleMark(
                    x: .value(
                        model.text("inventory.price.purchaseDate"),
                        selectedRecord.purchasedAt
                    )
                )
                .foregroundStyle(Color.secondary.opacity(0.5))

                PointMark(
                    x: .value(
                        model.text("inventory.price.purchaseDate"),
                        selectedRecord.purchasedAt
                    ),
                    y: .value(
                        model.text("inventory.price.unitPrice"),
                        selectedRecord.unitPrice.lifeDoubleValue
                    )
                )
                .foregroundStyle(Color.orange)
                .symbolSize(72)
                .annotation(
                    position: .top,
                    alignment: .center,
                    spacing: 8
                ) {
                    VStack(spacing: 2) {
                        Text(LifeFormat.date(selectedRecord.purchasedAt))
                        Text(
                            "\(LifeFormat.currency(selectedRecord.unitPrice))/\(unit)"
                        )
                            .fontWeight(.semibold)
                    }
                    .font(.caption2)
                    .monospacedDigit()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(
                                Color(nsColor: .separatorColor),
                                lineWidth: 0.5
                            )
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                    .foregroundStyle(Color(nsColor: .separatorColor).opacity(0.45))
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(
                            Decimal(number).formatted(
                                .currency(code: "CNY")
                                    .precision(.fractionLength(0...2))
                            )
                        )
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) {
                AxisGridLine()
                    .foregroundStyle(Color(nsColor: .separatorColor).opacity(0.25))
                AxisValueLabel(format: .dateTime.month().day())
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartLegend(.hidden)
        .accessibilityLabel(model.text("inventory.price.trend"))
        .accessibilityValue(
            records.last.map {
                "\(LifeFormat.currency($0.unitPrice))/\(unit)"
            } ?? model.text("inventory.price.empty.title")
        )
    }
}

private struct InventoryPriceRecordCard: View {
    @ObservedObject var model: AppModel
    let record: InventoryPriceRecord
    let unit: String
    let canCorrect: Bool
    let correct: () -> Void

    var body: some View {
        LifeCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(LifeFormat.currency(record.unitPrice))/\(unit)")
                            .font(.headline)
                            .monospacedDigit()
                        Text(LifeFormat.date(record.purchasedAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if canCorrect {
                        Menu {
                            Button(
                                model.text("inventory.price.correct"),
                                action: correct
                            )
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .foregroundStyle(.secondary)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                }

                if canCorrect {
                    Button(
                        model.text("inventory.price.correct"),
                        action: correct
                    )
                        .buttonStyle(.bordered)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(LifeFormat.date(record.purchasedAt)), \(LifeFormat.currency(record.unitPrice))/\(unit)"
        )
    }
}

struct LatestInventoryPriceCorrectionView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let item: HouseholdItem
    let record: InventoryPriceRecord

    @State private var unitPrice: Decimal

    init(
        model: AppModel,
        item: HouseholdItem,
        record: InventoryPriceRecord
    ) {
        self.model = model
        self.item = item
        self.record = record
        _unitPrice = State(initialValue: record.unitPrice)
    }

    private var unit: String {
        item.unit.isEmpty ? model.text("inventory.unit.default") : item.unit
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section(model.text("inventory.price.correct")) {
                    LabeledContent(model.text("inventory.price.purchaseDate")) {
                        Text(LifeFormat.date(record.purchasedAt))
                            .foregroundStyle(.secondary)
                    }
                    TextField(
                        "\(model.text("inventory.price.unitPrice")) (CNY/\(unit))",
                        value: $unitPrice,
                        format: .number.precision(.fractionLength(0...2))
                    )
                }
            }
            .formStyle(.grouped)

            Divider()

            LifeSheetFooter(
                cancelTitle: model.text("common.cancel"),
                saveTitle: model.text("common.save"),
                saveDisabled: unitPrice <= 0,
                cancel: { dismiss() }
            ) {
                if model.correctLatestInventoryPrice(
                    itemID: item.id,
                    unitPrice: unitPrice
                ) {
                    dismiss()
                }
            }
        }
        .frame(width: 460, height: 230)
    }
}
