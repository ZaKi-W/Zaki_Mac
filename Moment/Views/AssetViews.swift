import SwiftUI

struct AssetWorkspace: View {
    @ObservedObject var model: AppModel
    @State private var selection: AssetSection = .durable
    @State private var durableEditorItem: DurableAsset?
    @State private var isShowingDurableEditor = false
    @State private var financialEditorItem: FinancialAsset?
    @State private var isShowingFinancialEditor = false
    @State private var transactionAsset: FinancialAsset?
    @State private var priceAsset: FinancialAsset?

    var body: some View {
        VStack(spacing: 0) {
            Picker(model.text("assets.section"), selection: $selection) {
                ForEach(AssetSection.allCases) { section in
                    Text(model.text(section.localizationKey)).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)
            .padding(.top, 12)

            switch selection {
            case .durable:
                DurableAssetContent(
                    model: model,
                    edit: {
                        durableEditorItem = $0
                        isShowingDurableEditor = true
                    },
                    add: {
                        durableEditorItem = nil
                        isShowingDurableEditor = true
                    }
                )
            case .financial:
                FinancialAssetContent(
                    model: model,
                    edit: {
                        financialEditorItem = $0
                        isShowingFinancialEditor = true
                    },
                    add: {
                        financialEditorItem = nil
                        isShowingFinancialEditor = true
                    },
                    transact: { transactionAsset = $0 },
                    updatePrice: { priceAsset = $0 }
                )
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(model.text("assets.title"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    switch selection {
                    case .durable:
                        durableEditorItem = nil
                        isShowingDurableEditor = true
                    case .financial:
                        financialEditorItem = nil
                        isShowingFinancialEditor = true
                    }
                } label: {
                    Label(model.text("assets.add"), systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isShowingDurableEditor) {
            DurableAssetEditorView(model: model, asset: durableEditorItem)
        }
        .sheet(isPresented: $isShowingFinancialEditor) {
            FinancialAssetEditorView(model: model, asset: financialEditorItem)
        }
        .sheet(item: $transactionAsset) { asset in
            AssetTransactionEditorView(model: model, asset: asset)
        }
        .sheet(item: $priceAsset) { asset in
            AssetPriceEditorView(model: model, asset: asset)
        }
    }
}

private enum AssetSection: String, CaseIterable, Identifiable {
    case durable
    case financial

    var id: Self { self }
    var localizationKey: String { "assets.\(rawValue)" }
}

private struct DurableAssetContent: View {
    @ObservedObject var model: AppModel
    let edit: (DurableAsset) -> Void
    let add: () -> Void

    private var assets: [DurableAsset] {
        model.life.durableAssets.filter { !$0.isArchived }
    }

    private var totalPurchasePrice: Decimal {
        assets.reduce(0) { $0 + $1.purchasePrice }
    }

    private var dailyCost: Decimal {
        assets.reduce(0) {
            $0 + $1.dailyCost(asOf: .now, calendar: .current)
        }
    }

    private var expiringWarranties: Int {
        let end = Calendar.current.date(byAdding: .day, value: 30, to: .now)!
        return assets.filter {
            guard let date = $0.warrantyEndDate else { return false }
            return date >= .now && date <= end
        }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                LifeSummarySection(
                    title: model.text("assets.summary"),
                    systemImage: "chart.bar.xaxis"
                ) {
                    LifeCardGrid {
                        LifeMetricCard(
                            title: model.text("assets.durable.total"),
                            value: LifeFormat.currency(totalPurchasePrice),
                            detail: model.text("assets.durable.total.detail"),
                            systemImage: "shippingbox.fill",
                            tint: .blue
                        )
                        LifeMetricCard(
                            title: model.text("assets.durable.dailyCost"),
                            value: LifeFormat.currency(dailyCost),
                            detail: model.text("assets.durable.dailyCost.detail"),
                            systemImage: "calendar",
                            tint: .green
                        )
                        LifeMetricCard(
                            title: model.text("assets.durable.warranty"),
                            value: "\(expiringWarranties)",
                            detail: model.text("assets.durable.warranty.detail"),
                            systemImage: "wrench.and.screwdriver.fill",
                            tint: expiringWarranties > 0 ? .orange : .secondary
                        )
                    }
                }

                if assets.isEmpty {
                    LifeEmptyCard(
                        title: model.text("assets.durable.empty.title"),
                        message: model.text("assets.durable.empty.body"),
                        systemImage: "desktopcomputer",
                        buttonTitle: model.text("assets.durable.add"),
                        action: add
                    )
                } else {
                    LifeSectionHeader(
                        title: model.text("assets.durable.items"),
                        detail: "\(assets.count)",
                        systemImage: "desktopcomputer",
                        showsDivider: true
                    )
                    LifeCardGrid {
                        ForEach(assets.sorted(by: { $0.purchaseDate > $1.purchaseDate })) { asset in
                            DurableAssetCard(
                                model: model,
                                asset: asset,
                                edit: { edit(asset) },
                                archive: { model.archiveDurableAsset(asset) }
                            )
                        }
                    }
                }
            }
            .padding(20)
        }
    }
}

private struct DurableAssetCard: View {
    @ObservedObject var model: AppModel
    let asset: DurableAsset
    let edit: () -> Void
    let archive: () -> Void

    private var warrantyTint: Color {
        guard let warranty = asset.warrantyEndDate else { return .secondary }
        if warranty < .now { return .red }
        if warranty <= Calendar.current.date(byAdding: .day, value: 30, to: .now)! {
            return .orange
        }
        return .green
    }

    var body: some View {
        LifeCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(asset.name)
                            .font(.headline)
                            .lineLimit(1)
                    }
                    Spacer()
                    Menu {
                        Button(model.text("common.edit"), action: edit)
                        Divider()
                        Button(model.text("common.archive"), role: .destructive, action: archive)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

                Text(LifeFormat.currency(asset.purchasePrice))
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .monospacedDigit()

                Text(
                    "\(model.text("assets.durable.dailyCost")) · \(LifeFormat.currency(asset.dailyCost(asOf: .now, calendar: .current)))"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                if let warranty = asset.warrantyEndDate {
                    LifeStatusPill(
                        title: warranty < .now
                            ? model.text("assets.warranty.expired")
                            : "\(model.text("assets.warranty.until")) \(LifeFormat.date(warranty))",
                        systemImage: warranty < .now
                            ? "exclamationmark.circle"
                            : "checkmark.shield",
                        tint: warrantyTint
                    )
                }

                Divider()

                AssetMetadataRow(
                    title: model.text("assets.purchaseDate"),
                    value: LifeFormat.date(asset.purchaseDate)
                )
                AssetMetadataRow(
                    title: model.text("assets.estimatedValue"),
                    value: asset.currentEstimatedValue.map(LifeFormat.currency) ?? "—"
                )
                if asset.currentEstimatedValue != nil {
                    AssetMetadataRow(
                        title: model.text("assets.valuationUpdated"),
                        value: LifeFormat.date(asset.valuationUpdatedAt)
                    )
                }
            }
        }
        .contextMenu {
            Button(model.text("common.edit"), action: edit)
            Divider()
            Button(model.text("common.archive"), role: .destructive, action: archive)
        }
    }
}

private struct FinancialAssetContent: View {
    @ObservedObject var model: AppModel
    let edit: (FinancialAsset) -> Void
    let add: () -> Void
    let transact: (FinancialAsset) -> Void
    let updatePrice: (FinancialAsset) -> Void

    private var assets: [FinancialAsset] {
        model.life.financialAssets.filter { !$0.isArchived }
    }

    private var positions: [String: FinancialPosition] {
        Dictionary(
            uniqueKeysWithValues: assets.compactMap { asset in
                guard let value = try? model.life.financialPosition(
                    for: asset.id,
                    asOf: .now,
                    staleAfterDays: 7,
                    calendar: .current
                ) else {
                    return nil
                }
                return (asset.id, value)
            }
        )
    }

    private var totalValue: Decimal {
        positions.values.reduce(0) { $0 + ($1.currentValue ?? 0) }
    }

    private var unrealizedProfit: Decimal {
        positions.values.reduce(0) { $0 + ($1.unrealizedGainLoss ?? 0) }
    }

    private var staleCount: Int {
        positions.values.filter(\.isPriceStale).count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                LifeSummarySection(
                    title: model.text("assets.summary"),
                    systemImage: "chart.bar.xaxis"
                ) {
                    LifeCardGrid {
                        LifeMetricCard(
                            title: model.text("assets.financial.currentValue"),
                            value: LifeFormat.currency(totalValue),
                            detail: model.text("assets.financial.currentValue.detail"),
                            systemImage: "chart.line.uptrend.xyaxis",
                            tint: .blue
                        )
                        LifeMetricCard(
                            title: model.text("assets.financial.unrealized"),
                            value: LifeFormat.currency(unrealizedProfit),
                            detail: model.text("assets.financial.unrealized.detail"),
                            systemImage: unrealizedProfit >= 0
                                ? "arrow.up.right"
                                : "arrow.down.right",
                            tint: unrealizedProfit >= 0 ? .green : .red
                        )
                        LifeMetricCard(
                            title: model.text("assets.financial.stale"),
                            value: "\(staleCount)",
                            detail: model.text("assets.financial.stale.detail"),
                            systemImage: "clock.badge.exclamationmark",
                            tint: staleCount > 0 ? .orange : .secondary
                        )
                    }
                }

                if assets.isEmpty {
                    LifeEmptyCard(
                        title: model.text("assets.financial.empty.title"),
                        message: model.text("assets.financial.empty.body"),
                        systemImage: "banknote",
                        buttonTitle: model.text("assets.financial.add"),
                        action: add
                    )
                } else {
                    LifeSectionHeader(
                        title: model.text("assets.financial.items"),
                        detail: "\(assets.count)",
                        systemImage: "chart.line.uptrend.xyaxis",
                        showsDivider: true
                    )
                    LifeCardGrid {
                        ForEach(assets.sorted(by: {
                            $0.name.localizedStandardCompare($1.name) == .orderedAscending
                        })) { asset in
                            FinancialAssetCard(
                                model: model,
                                asset: asset,
                                position: positions[asset.id],
                                edit: { edit(asset) },
                                transact: { transact(asset) },
                                updatePrice: { updatePrice(asset) },
                                archive: { model.archiveFinancialAsset(asset) }
                            )
                        }
                    }
                }
            }
            .padding(20)
        }
    }
}

private struct FinancialAssetCard: View {
    @ObservedObject var model: AppModel
    let asset: FinancialAsset
    let position: FinancialPosition?
    let edit: () -> Void
    let transact: () -> Void
    let updatePrice: () -> Void
    let archive: () -> Void

    var body: some View {
        LifeCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(asset.name)
                                .font(.headline)
                                .lineLimit(1)
                            if !asset.code.isEmpty {
                                Text(asset.code)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(model.text("assets.type.\(asset.type.rawValue)"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu {
                        Button(model.text("assets.transaction.add"), action: transact)
                        Button(model.text("assets.price.update"), action: updatePrice)
                        Button(model.text("common.edit"), action: edit)
                        Divider()
                        Button(model.text("common.archive"), role: .destructive, action: archive)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

                Text(position.flatMap(\.currentValue).map(LifeFormat.currency) ?? "—")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .monospacedDigit()

                if let position {
                    HStack(spacing: 8) {
                        LifeStatusPill(
                            title: "\(model.text("assets.unrealized.short")) \(LifeFormat.currency(position.unrealizedGainLoss ?? 0))",
                            systemImage: (position.unrealizedGainLoss ?? 0) >= 0
                                ? "arrow.up.right"
                                : "arrow.down.right",
                            tint: (position.unrealizedGainLoss ?? 0) >= 0 ? .green : .red
                        )
                        if position.isPriceStale {
                            LifeStatusPill(
                                title: model.text("assets.price.stale"),
                                systemImage: "clock",
                                tint: .orange
                            )
                        }
                    }

                    Divider()

                    AssetMetadataRow(
                        title: model.text("assets.quantity"),
                        value: position.quantity.formatted(
                            .number.precision(.fractionLength(0...4))
                        )
                    )
                    AssetMetadataRow(
                        title: model.text("assets.averageCost"),
                        value: position.averageUnitCost.map(LifeFormat.currency) ?? "—"
                    )
                    AssetMetadataRow(
                        title: model.text("assets.latestPrice"),
                        value: position.currentUnitPrice.map(LifeFormat.currency) ?? "—"
                    )
                    AssetMetadataRow(
                        title: model.text("assets.realized"),
                        value: LifeFormat.currency(position.realizedGainLoss)
                    )
                }

                HStack {
                    Button(model.text("assets.transaction.add"), action: transact)
                        .buttonStyle(.bordered)
                    Button(model.text("assets.price.update"), action: updatePrice)
                        .buttonStyle(.bordered)
                }
            }
        }
        .contextMenu {
            Button(model.text("assets.transaction.add"), action: transact)
            Button(model.text("assets.price.update"), action: updatePrice)
            Button(model.text("common.edit"), action: edit)
            Divider()
            Button(model.text("common.archive"), role: .destructive, action: archive)
        }
    }
}

private struct AssetMetadataRow: View {
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

private struct DurableAssetEditorView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let asset: DurableAsset?

    @State private var name: String
    @State private var purchaseDate: Date
    @State private var purchasePrice: Decimal
    @State private var hasEstimatedValue: Bool
    @State private var estimatedValue: Decimal
    @State private var hasWarranty: Bool
    @State private var warrantyEndDate: Date
    @State private var notes: String

    init(model: AppModel, asset: DurableAsset?) {
        self.model = model
        self.asset = asset
        _name = State(initialValue: asset?.name ?? "")
        _purchaseDate = State(initialValue: asset?.purchaseDate ?? .now)
        _purchasePrice = State(initialValue: asset?.purchasePrice ?? 0)
        _hasEstimatedValue = State(initialValue: asset?.currentEstimatedValue != nil)
        _estimatedValue = State(initialValue: asset?.currentEstimatedValue ?? 0)
        _hasWarranty = State(initialValue: asset?.warrantyEndDate != nil)
        _warrantyEndDate = State(initialValue: asset?.warrantyEndDate ?? .now)
        _notes = State(initialValue: asset?.notes ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section(model.text("assets.editor.details")) {
                    TextField(model.text("assets.field.name"), text: $name)
                    DatePicker(
                        model.text("assets.purchaseDate"),
                        selection: $purchaseDate,
                        displayedComponents: .date
                    )
                    TextField(
                        model.text("assets.purchasePrice"),
                        value: $purchasePrice,
                        format: .number
                    )
                }

                Section(model.text("assets.valuation")) {
                    Toggle(model.text("assets.estimatedValue"), isOn: $hasEstimatedValue)
                    if hasEstimatedValue {
                        TextField(
                            model.text("assets.estimatedValue"),
                            value: $estimatedValue,
                            format: .number
                        )
                    }
                }

                Section(model.text("assets.warranty")) {
                    Toggle(model.text("assets.warranty.enable"), isOn: $hasWarranty)
                    if hasWarranty {
                        DatePicker(
                            model.text("assets.warranty.end"),
                            selection: $warrantyEndDate,
                            displayedComponents: .date
                        )
                    }
                }

                Section(model.text("common.notes")) {
                    TextEditor(text: $notes)
                        .frame(minHeight: 70)
                }
            }
            .formStyle(.grouped)

            Divider()

            LifeSheetFooter(
                cancelTitle: model.text("common.cancel"),
                saveTitle: asset == nil
                    ? model.text("common.create")
                    : model.text("common.save"),
                saveDisabled: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || purchasePrice < 0
                    || estimatedValue < 0,
                cancel: { dismiss() }
            ) {
                model.saveDurableAsset(
                    DurableAsset(
                        id: asset?.id ?? UUID().uuidString,
                        name: name,
                        purchaseDate: purchaseDate,
                        purchasePrice: purchasePrice,
                        currency: "CNY",
                        currentEstimatedValue: hasEstimatedValue ? estimatedValue : nil,
                        valuationUpdatedAt: hasEstimatedValue ? .now : nil,
                        warrantyEndDate: hasWarranty ? warrantyEndDate : nil,
                        notes: notes,
                        isArchived: false,
                        createdAt: asset?.createdAt ?? .now
                    )
                )
                dismiss()
            }
        }
        .frame(width: 540, height: 560)
    }
}

private struct FinancialAssetEditorView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let asset: FinancialAsset?
    @State private var name: String
    @State private var code: String
    @State private var type: FinancialAssetType

    init(model: AppModel, asset: FinancialAsset?) {
        self.model = model
        self.asset = asset
        _name = State(initialValue: asset?.name ?? "")
        _code = State(initialValue: asset?.code ?? "")
        _type = State(initialValue: asset?.type ?? .other)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField(model.text("assets.field.name"), text: $name)
                TextField(model.text("assets.field.code"), text: $code)
                Picker(model.text("assets.field.type"), selection: $type) {
                    ForEach(FinancialAssetType.allCases) { value in
                        Text(model.text("assets.type.\(value.rawValue)")).tag(value)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            LifeSheetFooter(
                cancelTitle: model.text("common.cancel"),
                saveTitle: asset == nil
                    ? model.text("common.create")
                    : model.text("common.save"),
                saveDisabled: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                cancel: { dismiss() }
            ) {
                model.saveFinancialAsset(
                    FinancialAsset(
                        id: asset?.id ?? UUID().uuidString,
                        name: name,
                        code: code,
                        type: type,
                        currency: "CNY",
                        isArchived: false,
                        createdAt: asset?.createdAt ?? .now
                    )
                )
                dismiss()
            }
        }
        .frame(width: 480, height: 310)
    }
}

private struct AssetTransactionEditorView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let asset: FinancialAsset
    @State private var kind: AssetTransactionKind = .buy
    @State private var quantity: Decimal = 0
    @State private var unitPrice: Decimal = 0
    @State private var fee: Decimal = 0
    @State private var tradedAt: Date = .now
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Picker(model.text("assets.transaction.kind"), selection: $kind) {
                    ForEach(AssetTransactionKind.allCases) { value in
                        Text(model.text("assets.transaction.\(value.rawValue)")).tag(value)
                    }
                }
                .pickerStyle(.segmented)

                TextField(
                    model.text("assets.quantity"),
                    value: $quantity,
                    format: .number
                )
                TextField(
                    model.text("assets.unitPrice"),
                    value: $unitPrice,
                    format: .number
                )
                TextField(
                    model.text("assets.fee"),
                    value: $fee,
                    format: .number
                )
                DatePicker(
                    model.text("assets.transaction.date"),
                    selection: $tradedAt
                )

                if let errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)

            Divider()

            LifeSheetFooter(
                cancelTitle: model.text("common.cancel"),
                saveTitle: model.text("common.save"),
                saveDisabled: quantity <= 0 || unitPrice < 0 || fee < 0,
                cancel: { dismiss() }
            ) {
                do {
                    try model.addAssetTransaction(
                        AssetTransaction(
                            assetID: asset.id,
                            kind: kind,
                            quantity: quantity,
                            unitPrice: unitPrice,
                            fee: fee,
                            tradedAt: tradedAt
                        )
                    )
                    dismiss()
                } catch {
                    if case FinancialCalculationError.oversold = error {
                        errorMessage = model.text("assets.transaction.oversold")
                    } else {
                        errorMessage = model.text("assets.transaction.invalid")
                    }
                }
            }
        }
        .frame(width: 500, height: 430)
    }
}

private struct AssetPriceEditorView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let asset: FinancialAsset
    @State private var unitPrice: Decimal = 0
    @State private var recordedAt: Date = .now

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField(
                    model.text("assets.unitPrice"),
                    value: $unitPrice,
                    format: .number
                )
                DatePicker(
                    model.text("assets.price.date"),
                    selection: $recordedAt
                )
            }
            .formStyle(.grouped)

            Divider()

            LifeSheetFooter(
                cancelTitle: model.text("common.cancel"),
                saveTitle: model.text("common.save"),
                saveDisabled: unitPrice < 0,
                cancel: { dismiss() }
            ) {
                model.recordAssetPrice(
                    assetID: asset.id,
                    unitPrice: unitPrice,
                    at: recordedAt
                )
                dismiss()
            }
        }
        .frame(width: 440, height: 250)
    }
}
