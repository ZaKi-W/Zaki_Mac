import Foundation

// MARK: - Life data

struct LifeData: Codable, Equatable, Sendable {
    var householdItems: [HouseholdItem]
    var inventoryCounts: [InventoryCount]
    var inventoryPriceRecords: [InventoryPriceRecord]
    var inventoryReviewSessions: [InventoryReviewSession]
    var inventoryReviewSettings: InventoryReviewSettings
    var durableAssets: [DurableAsset]
    var financialAssets: [FinancialAsset]
    var assetTransactions: [AssetTransaction]
    var assetPriceSnapshots: [AssetPriceSnapshot]
    var recurringExpenses: [RecurringExpense]

    static let empty = LifeData()

    init(
        householdItems: [HouseholdItem] = [],
        inventoryCounts: [InventoryCount] = [],
        inventoryPriceRecords: [InventoryPriceRecord] = [],
        inventoryReviewSessions: [InventoryReviewSession] = [],
        inventoryReviewSettings: InventoryReviewSettings = .default,
        durableAssets: [DurableAsset] = [],
        financialAssets: [FinancialAsset] = [],
        assetTransactions: [AssetTransaction] = [],
        assetPriceSnapshots: [AssetPriceSnapshot] = [],
        recurringExpenses: [RecurringExpense] = []
    ) {
        self.householdItems = householdItems
        self.inventoryCounts = inventoryCounts
        self.inventoryPriceRecords = inventoryPriceRecords
        self.inventoryReviewSessions = inventoryReviewSessions
        self.inventoryReviewSettings = inventoryReviewSettings
        self.durableAssets = durableAssets
        self.financialAssets = financialAssets
        self.assetTransactions = assetTransactions
        self.assetPriceSnapshots = assetPriceSnapshots
        self.recurringExpenses = recurringExpenses
    }

    private enum CodingKeys: String, CodingKey {
        case householdItems
        case inventoryCounts
        case inventoryPriceRecords
        case inventoryReviewSessions
        case inventoryReviewSettings
        case durableAssets
        case financialAssets
        case assetTransactions
        case assetPriceSnapshots
        case recurringExpenses
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        householdItems = try container.decodeIfPresent(
            [HouseholdItem].self,
            forKey: .householdItems
        ) ?? []
        inventoryCounts = try container.decodeIfPresent(
            [InventoryCount].self,
            forKey: .inventoryCounts
        ) ?? []
        inventoryPriceRecords = try container.decodeIfPresent(
            [InventoryPriceRecord].self,
            forKey: .inventoryPriceRecords
        ) ?? []
        inventoryReviewSessions = try container.decodeIfPresent(
            [InventoryReviewSession].self,
            forKey: .inventoryReviewSessions
        ) ?? []
        inventoryReviewSettings = try container.decodeIfPresent(
            InventoryReviewSettings.self,
            forKey: .inventoryReviewSettings
        ) ?? .default
        durableAssets = try container.decodeIfPresent(
            [DurableAsset].self,
            forKey: .durableAssets
        ) ?? []
        financialAssets = try container.decodeIfPresent(
            [FinancialAsset].self,
            forKey: .financialAssets
        ) ?? []
        assetTransactions = try container.decodeIfPresent(
            [AssetTransaction].self,
            forKey: .assetTransactions
        ) ?? []
        assetPriceSnapshots = try container.decodeIfPresent(
            [AssetPriceSnapshot].self,
            forKey: .assetPriceSnapshots
        ) ?? []
        recurringExpenses = try container.decodeIfPresent(
            [RecurringExpense].self,
            forKey: .recurringExpenses
        ) ?? []
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(householdItems, forKey: .householdItems)
        try container.encode(inventoryCounts, forKey: .inventoryCounts)
        try container.encode(inventoryPriceRecords, forKey: .inventoryPriceRecords)
        try container.encode(
            inventoryReviewSessions,
            forKey: .inventoryReviewSessions
        )
        try container.encode(
            inventoryReviewSettings,
            forKey: .inventoryReviewSettings
        )
        try container.encode(durableAssets, forKey: .durableAssets)
        try container.encode(financialAssets, forKey: .financialAssets)
        try container.encode(assetTransactions, forKey: .assetTransactions)
        try container.encode(assetPriceSnapshots, forKey: .assetPriceSnapshots)
        try container.encode(recurringExpenses, forKey: .recurringExpenses)
    }
}

// MARK: - Household inventory

struct HouseholdItem: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var storageLocation: String
    var unit: String
    var lowStockThreshold: Decimal
    var nearestExpirationDate: Date?
    var isArchived: Bool
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        storageLocation: String = "",
        unit: String = "",
        lowStockThreshold: Decimal = 0,
        nearestExpirationDate: Date? = nil,
        isArchived: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.storageLocation = storageLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        self.unit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        self.lowStockThreshold = max(lowStockThreshold, 0)
        self.nearestExpirationDate = nearestExpirationDate
        self.isArchived = isArchived
        self.createdAt = createdAt
    }
}

enum InventoryCountSource: Codable, Equatable, Sendable {
    case manual
    case weeklyReview(sessionID: String)

    var reviewSessionID: String? {
        guard case let .weeklyReview(sessionID) = self else { return nil }
        return sessionID
    }
}

struct InventoryCount: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var itemID: String
    var quantity: Decimal
    var recordedAt: Date
    var source: InventoryCountSource

    init(
        id: String = UUID().uuidString,
        itemID: String,
        quantity: Decimal,
        recordedAt: Date = .now,
        source: InventoryCountSource = .manual
    ) {
        self.id = id
        self.itemID = itemID
        self.quantity = max(quantity, 0)
        self.recordedAt = recordedAt
        self.source = source
    }
}

struct InventoryPriceRecord: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var itemID: String
    var unitPrice: Decimal
    var purchasedAt: Date
    var createdAt: Date
    var stockIncrease: Decimal?

    init(
        id: String = UUID().uuidString,
        itemID: String,
        unitPrice: Decimal,
        purchasedAt: Date,
        createdAt: Date = .now,
        stockIncrease: Decimal? = nil
    ) {
        self.id = id
        self.itemID = itemID
        self.unitPrice = unitPrice
        self.purchasedAt = purchasedAt
        self.createdAt = createdAt
        self.stockIncrease = stockIncrease
    }
}

enum InventoryPriceComparison: Equatable, Sendable {
    case insufficientHistory
    case historicalLow
    case cheaper(percentage: Decimal)
    case equal
    case moreExpensive(percentage: Decimal)
}

struct InventoryPriceSummary: Equatable, Sendable {
    var latest: InventoryPriceRecord
    var lowest: Decimal
    var averageUnitPrice: Decimal
    var comparison: InventoryPriceComparison
}

struct InventoryReviewEntry: Equatable, Sendable {
    var quantity: Decimal
    var unitPrice: Decimal
}

struct InventoryReviewSettings: Codable, Equatable, Sendable {
    var isEnabled: Bool
    /// Calendar weekday where Sunday is 1 and Saturday is 7.
    var weekday: Int
    var hour: Int
    var minute: Int

    static let `default` = InventoryReviewSettings(
        isEnabled: true,
        weekday: 1,
        hour: 20,
        minute: 0
    )

    init(
        isEnabled: Bool = true,
        weekday: Int = 1,
        hour: Int = 20,
        minute: Int = 0
    ) {
        self.isEnabled = isEnabled
        self.weekday = min(max(weekday, 1), 7)
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    func scheduledDate(
        inWeekContaining date: Date,
        calendar: Calendar = .current
    ) -> Date? {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else {
            return nil
        }
        var components = DateComponents()
        components.weekday = min(max(weekday, 1), 7)
        components.hour = min(max(hour, 0), 23)
        components.minute = min(max(minute, 0), 59)
        components.second = 0
        guard let scheduledDate = calendar.nextDate(
            after: week.start.addingTimeInterval(-1),
            matching: components,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        ), scheduledDate < week.end else {
            return nil
        }
        return scheduledDate
    }

    func nextScheduledDate(
        onOrAfter date: Date,
        calendar: Calendar = .current
    ) -> Date? {
        if let thisWeek = scheduledDate(inWeekContaining: date, calendar: calendar),
           thisWeek >= date {
            return thisWeek
        }
        guard let nextWeek = calendar.date(
            byAdding: .weekOfYear,
            value: 1,
            to: date
        ) else {
            return nil
        }
        return scheduledDate(inWeekContaining: nextWeek, calendar: calendar)
    }
}

struct InventoryReviewSession: Codable, Identifiable, Equatable, Sendable {
    var id: String
    /// Start of the calendar week represented by this review.
    var scheduledWeekStart: Date
    var completedAt: Date?
    var reviewedItemIDs: Set<String>

    init(
        id: String = UUID().uuidString,
        scheduledWeekStart: Date,
        completedAt: Date? = nil,
        reviewedItemIDs: Set<String> = []
    ) {
        self.id = id
        self.scheduledWeekStart = scheduledWeekStart
        self.completedAt = completedAt
        self.reviewedItemIDs = reviewedItemIDs
    }

    func hasReviewed(itemID: String) -> Bool {
        reviewedItemIDs.contains(itemID)
    }
}

enum InventoryReviewPhase: String, Codable, Equatable, Sendable {
    case disabled
    case scheduled
    case due
    case completed
}

struct InventoryReviewStatus: Codable, Equatable, Sendable {
    var phase: InventoryReviewPhase
    var scheduledAt: Date?
    var completedAt: Date?
    var sessionID: String?
    var reviewedItemCount: Int
    var totalItemCount: Int

    var isDue: Bool { phase == .due }
    var isCompleted: Bool { phase == .completed }
}

enum InventoryExpiryStatus: String, Codable, Equatable, Sendable {
    case none
    case fresh
    case expiring
    case expired
}

extension LifeData {
    @discardableResult
    mutating func appendInventoryUpdate(
        id: String = UUID().uuidString,
        itemID: String,
        quantity: Decimal,
        unitPrice: Decimal,
        recordedAt: Date = .now,
        source: InventoryCountSource = .manual
    ) -> Bool {
        guard quantity >= 0,
              unitPrice > 0,
              householdItems.contains(where: {
                  $0.id == itemID && !$0.isArchived
              }) else {
            return false
        }

        inventoryCounts.append(
            InventoryCount(
                id: id,
                itemID: itemID,
                quantity: quantity,
                recordedAt: recordedAt,
                source: source
            )
        )
        inventoryPriceRecords.append(
            InventoryPriceRecord(
                id: id,
                itemID: itemID,
                unitPrice: unitPrice,
                purchasedAt: recordedAt,
                createdAt: recordedAt,
                stockIncrease: nil
            )
        )
        return true
    }

    @discardableResult
    mutating func correctLatestInventoryPrice(
        itemID: String,
        unitPrice: Decimal
    ) -> Bool {
        guard unitPrice > 0,
              householdItems.contains(where: {
                  $0.id == itemID && !$0.isArchived
              }),
              let latest = inventoryPriceHistory(for: itemID).last,
              let index = inventoryPriceRecords.firstIndex(where: {
                  $0.id == latest.id
                      && $0.itemID == latest.itemID
                      && $0.purchasedAt == latest.purchasedAt
                      && $0.createdAt == latest.createdAt
              }) else {
            return false
        }

        inventoryPriceRecords[index].unitPrice = unitPrice
        return true
    }

    func inventoryPriceHistory(for itemID: String) -> [InventoryPriceRecord] {
        inventoryPriceRecords
            .filter { $0.itemID == itemID }
            .sorted {
                if $0.purchasedAt != $1.purchasedAt {
                    return $0.purchasedAt < $1.purchasedAt
                }
                if $0.createdAt != $1.createdAt {
                    return $0.createdAt < $1.createdAt
                }
                return $0.id < $1.id
            }
    }

    func inventoryPriceHistory(
        for item: HouseholdItem
    ) -> [InventoryPriceRecord] {
        inventoryPriceHistory(for: item.id)
    }

    func inventoryPriceSummary(
        for itemID: String
    ) -> InventoryPriceSummary? {
        let history = inventoryPriceHistory(for: itemID)
        guard let latest = history.last else { return nil }

        let lowest = history.lazy.map(\.unitPrice).min() ?? latest.unitPrice
        let average = history.reduce(Decimal.zero) {
            $0 + $1.unitPrice
        } / Decimal(history.count)
        guard history.count > 1 else {
            return InventoryPriceSummary(
                latest: latest,
                lowest: lowest,
                averageUnitPrice: average,
                comparison: .insufficientHistory
            )
        }

        let earlierRecords = history.dropLast()
        let earlierLowest = earlierRecords.lazy.map(\.unitPrice).min()
            ?? latest.unitPrice
        let earlierAverage = earlierRecords.reduce(Decimal.zero) {
            $0 + $1.unitPrice
        } / Decimal(earlierRecords.count)
        let comparison: InventoryPriceComparison
        if latest.unitPrice <= earlierLowest {
            comparison = .historicalLow
        } else if latest.unitPrice < earlierAverage {
            comparison = .cheaper(
                percentage: Self.inventoryPricePercentage(
                    difference: earlierAverage - latest.unitPrice,
                    baseline: earlierAverage
                )
            )
        } else if latest.unitPrice > earlierAverage {
            comparison = .moreExpensive(
                percentage: Self.inventoryPricePercentage(
                    difference: latest.unitPrice - earlierAverage,
                    baseline: earlierAverage
                )
            )
        } else {
            comparison = .equal
        }

        return InventoryPriceSummary(
            latest: latest,
            lowest: lowest,
            averageUnitPrice: average,
            comparison: comparison
        )
    }

    func inventoryPriceSummary(
        for item: HouseholdItem
    ) -> InventoryPriceSummary? {
        inventoryPriceSummary(for: item.id)
    }

    private static func inventoryPricePercentage(
        difference: Decimal,
        baseline: Decimal
    ) -> Decimal {
        guard baseline != 0 else {
            return difference == 0 ? 0 : 100
        }
        let percentage = abs(difference / baseline) * 100
        return max(percentage, 0)
    }

    func latestInventoryCount(for itemID: String) -> InventoryCount? {
        inventoryCounts
            .filter { $0.itemID == itemID }
            .max {
                if $0.recordedAt == $1.recordedAt {
                    return $0.id < $1.id
                }
                return $0.recordedAt < $1.recordedAt
            }
    }

    func latestInventoryCount(for item: HouseholdItem) -> InventoryCount? {
        latestInventoryCount(for: item.id)
    }

    func currentQuantity(for itemID: String) -> Decimal? {
        latestInventoryCount(for: itemID)?.quantity
    }

    func currentQuantity(for item: HouseholdItem) -> Decimal? {
        currentQuantity(for: item.id)
    }

    func isLowStock(_ item: HouseholdItem) -> Bool {
        guard !item.isArchived, let quantity = currentQuantity(for: item) else {
            return false
        }
        return quantity <= item.lowStockThreshold
    }

    func lowStockItems() -> [HouseholdItem] {
        householdItems.filter(isLowStock)
    }

    func expirationStatus(
        for item: HouseholdItem,
        asOf date: Date = .now,
        warningDays: Int = 30,
        calendar: Calendar = .current
    ) -> InventoryExpiryStatus {
        guard !item.isArchived, let expirationDate = item.nearestExpirationDate else {
            return .none
        }
        let today = calendar.startOfDay(for: date)
        let expirationDay = calendar.startOfDay(for: expirationDate)
        if expirationDay < today {
            return .expired
        }
        let deadline = calendar.date(
            byAdding: .day,
            value: max(0, warningDays),
            to: today
        ) ?? today
        return expirationDay <= deadline ? .expiring : .fresh
    }

    func itemsExpiring(
        withinDays days: Int = 30,
        from date: Date = .now,
        calendar: Calendar = .current
    ) -> [HouseholdItem] {
        householdItems.filter {
            expirationStatus(
                for: $0,
                asOf: date,
                warningDays: days,
                calendar: calendar
            ) == .expiring
        }
    }

    func inventoryReviewSession(
        forWeekContaining date: Date,
        calendar: Calendar = .current
    ) -> InventoryReviewSession? {
        guard let targetWeek = calendar.dateInterval(of: .weekOfYear, for: date) else {
            return nil
        }
        return inventoryReviewSessions
            .filter {
                guard let sessionWeek = calendar.dateInterval(
                    of: .weekOfYear,
                    for: $0.scheduledWeekStart
                ) else {
                    return false
                }
                return sessionWeek.start == targetWeek.start
            }
            .max {
                let lhsDate = $0.completedAt ?? $0.scheduledWeekStart
                let rhsDate = $1.completedAt ?? $1.scheduledWeekStart
                if lhsDate == rhsDate {
                    return $0.id < $1.id
                }
                return lhsDate < rhsDate
            }
    }

    func inventoryReviewStatus(
        at date: Date = .now,
        calendar: Calendar = .current
    ) -> InventoryReviewStatus {
        let activeItemCount = householdItems.lazy.filter { !$0.isArchived }.count
        guard inventoryReviewSettings.isEnabled else {
            return InventoryReviewStatus(
                phase: .disabled,
                scheduledAt: nil,
                completedAt: nil,
                sessionID: nil,
                reviewedItemCount: 0,
                totalItemCount: activeItemCount
            )
        }

        let scheduledAt = inventoryReviewSettings.scheduledDate(
            inWeekContaining: date,
            calendar: calendar
        )
        let session = inventoryReviewSession(
            forWeekContaining: date,
            calendar: calendar
        )
        let phase: InventoryReviewPhase
        if session?.completedAt != nil {
            phase = .completed
        } else if let scheduledAt, date >= scheduledAt {
            phase = .due
        } else {
            phase = .scheduled
        }
        return InventoryReviewStatus(
            phase: phase,
            scheduledAt: scheduledAt,
            completedAt: session?.completedAt,
            sessionID: session?.id,
            reviewedItemCount: session?.reviewedItemIDs.count ?? 0,
            totalItemCount: activeItemCount
        )
    }
}

// MARK: - Durable assets

struct DurableAsset: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var purchaseDate: Date
    var purchasePrice: Decimal
    var currency: String
    var currentEstimatedValue: Decimal?
    var valuationUpdatedAt: Date?
    var warrantyEndDate: Date?
    var notes: String
    var isArchived: Bool
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        purchaseDate: Date,
        purchasePrice: Decimal,
        currency: String = "CNY",
        currentEstimatedValue: Decimal? = nil,
        valuationUpdatedAt: Date? = nil,
        warrantyEndDate: Date? = nil,
        notes: String = "",
        isArchived: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.purchaseDate = purchaseDate
        self.purchasePrice = max(purchasePrice, 0)
        self.currency = currency.isEmpty ? "CNY" : currency.uppercased()
        self.currentEstimatedValue = currentEstimatedValue.map { max($0, 0) }
        self.valuationUpdatedAt = valuationUpdatedAt
        self.warrantyEndDate = warrantyEndDate
        self.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        self.isArchived = isArchived
        self.createdAt = createdAt
    }

    func holdingDays(
        asOf date: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        let purchaseDay = calendar.startOfDay(for: purchaseDate)
        let currentDay = calendar.startOfDay(for: date)
        let elapsedDays = calendar.dateComponents(
            [.day],
            from: purchaseDay,
            to: currentDay
        ).day ?? 0
        return max(1, elapsedDays)
    }

    func dailyCost(
        asOf date: Date = .now,
        calendar: Calendar = .current
    ) -> Decimal {
        purchasePrice / Decimal(holdingDays(asOf: date, calendar: calendar))
    }
}

enum WarrantyStatus: String, Codable, Equatable, Sendable {
    case none
    case active
    case expiring
    case expired
}

extension DurableAsset {
    func warrantyStatus(
        asOf date: Date = .now,
        warningDays: Int = 30,
        calendar: Calendar = .current
    ) -> WarrantyStatus {
        guard let warrantyEndDate else { return .none }
        let today = calendar.startOfDay(for: date)
        let warrantyDay = calendar.startOfDay(for: warrantyEndDate)
        if warrantyDay < today {
            return .expired
        }
        let deadline = calendar.date(
            byAdding: .day,
            value: max(0, warningDays),
            to: today
        ) ?? today
        return warrantyDay <= deadline ? .expiring : .active
    }
}

// MARK: - Financial assets

enum FinancialAssetType: String, Codable, CaseIterable, Identifiable, Sendable {
    case stock
    case fund
    case deposit
    case cash
    case cryptocurrency
    case other

    var id: Self { self }
}

struct FinancialAsset: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var code: String
    var type: FinancialAssetType
    var currency: String
    var isArchived: Bool
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        code: String = "",
        type: FinancialAssetType,
        currency: String = "CNY",
        isArchived: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        self.type = type
        self.currency = currency.isEmpty ? "CNY" : currency.uppercased()
        self.isArchived = isArchived
        self.createdAt = createdAt
    }
}

enum AssetTransactionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case buy
    case sell

    var id: Self { self }
}

struct AssetTransaction: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var assetID: String
    var kind: AssetTransactionKind
    var quantity: Decimal
    var unitPrice: Decimal
    var fee: Decimal
    var tradedAt: Date

    init(
        id: String = UUID().uuidString,
        assetID: String,
        kind: AssetTransactionKind,
        quantity: Decimal,
        unitPrice: Decimal,
        fee: Decimal = 0,
        tradedAt: Date = .now
    ) {
        self.id = id
        self.assetID = assetID
        self.kind = kind
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.fee = fee
        self.tradedAt = tradedAt
    }
}

struct AssetPriceSnapshot: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var assetID: String
    var unitPrice: Decimal
    var recordedAt: Date

    init(
        id: String = UUID().uuidString,
        assetID: String,
        unitPrice: Decimal,
        recordedAt: Date = .now
    ) {
        self.id = id
        self.assetID = assetID
        self.unitPrice = unitPrice
        self.recordedAt = recordedAt
    }
}

enum FinancialCalculationError: Error, Equatable, Sendable {
    case nonPositiveQuantity(transactionID: String)
    case negativeUnitPrice(transactionID: String)
    case negativeFee(transactionID: String)
    case oversold(
        assetID: String,
        transactionID: String,
        available: Decimal,
        attempted: Decimal
    )
}

struct FinancialPosition: Codable, Equatable, Sendable {
    var assetID: String
    var quantity: Decimal
    var remainingCostBasis: Decimal
    var averageUnitCost: Decimal?
    var currentUnitPrice: Decimal?
    var currentValue: Decimal?
    var realizedGainLoss: Decimal
    var unrealizedGainLoss: Decimal?
    var priceUpdatedAt: Date?
    var isPriceStale: Bool
}

extension LifeData {
    func latestPriceSnapshot(
        for assetID: String,
        asOf date: Date = .now
    ) -> AssetPriceSnapshot? {
        assetPriceSnapshots
            .filter { $0.assetID == assetID && $0.recordedAt <= date }
            .max {
                if $0.recordedAt == $1.recordedAt {
                    return $0.id < $1.id
                }
                return $0.recordedAt < $1.recordedAt
            }
    }

    func financialPosition(
        for assetID: String,
        asOf date: Date = .now,
        staleAfterDays: Int = 7,
        calendar: Calendar = .current
    ) throws -> FinancialPosition {
        let transactions = assetTransactions
            .filter { $0.assetID == assetID && $0.tradedAt <= date }
            .sorted {
                if $0.tradedAt == $1.tradedAt {
                    return $0.id < $1.id
                }
                return $0.tradedAt < $1.tradedAt
            }
        var quantity: Decimal = 0
        var costBasis: Decimal = 0
        var realizedGainLoss: Decimal = 0

        for transaction in transactions {
            guard transaction.quantity > 0 else {
                throw FinancialCalculationError.nonPositiveQuantity(
                    transactionID: transaction.id
                )
            }
            guard transaction.unitPrice >= 0 else {
                throw FinancialCalculationError.negativeUnitPrice(
                    transactionID: transaction.id
                )
            }
            guard transaction.fee >= 0 else {
                throw FinancialCalculationError.negativeFee(
                    transactionID: transaction.id
                )
            }

            switch transaction.kind {
            case .buy:
                quantity += transaction.quantity
                costBasis += transaction.quantity * transaction.unitPrice
                    + transaction.fee
            case .sell:
                guard transaction.quantity <= quantity else {
                    throw FinancialCalculationError.oversold(
                        assetID: assetID,
                        transactionID: transaction.id,
                        available: quantity,
                        attempted: transaction.quantity
                    )
                }
                let averageCost = quantity > 0 ? costBasis / quantity : 0
                let removedCost = averageCost * transaction.quantity
                let proceeds = transaction.quantity * transaction.unitPrice
                    - transaction.fee
                realizedGainLoss += proceeds - removedCost
                quantity -= transaction.quantity
                costBasis -= removedCost
                if quantity == 0 {
                    costBasis = 0
                }
            }
        }

        let latestPrice = latestPriceSnapshot(for: assetID, asOf: date)
        let currentValue = latestPrice.map { quantity * $0.unitPrice }
        let staleCutoff = calendar.date(
            byAdding: .day,
            value: -max(0, staleAfterDays),
            to: date
        ) ?? date
        let isPriceStale = quantity > 0
            && (latestPrice == nil || latestPrice!.recordedAt < staleCutoff)

        return FinancialPosition(
            assetID: assetID,
            quantity: quantity,
            remainingCostBasis: costBasis,
            averageUnitCost: quantity > 0 ? costBasis / quantity : nil,
            currentUnitPrice: latestPrice?.unitPrice,
            currentValue: currentValue,
            realizedGainLoss: realizedGainLoss,
            unrealizedGainLoss: currentValue.map { $0 - costBasis },
            priceUpdatedAt: latestPrice?.recordedAt,
            isPriceStale: isPriceStale
        )
    }

    func financialPosition(
        for asset: FinancialAsset,
        asOf date: Date = .now,
        staleAfterDays: Int = 7,
        calendar: Calendar = .current
    ) throws -> FinancialPosition {
        try financialPosition(
            for: asset.id,
            asOf: date,
            staleAfterDays: staleAfterDays,
            calendar: calendar
        )
    }
}

// MARK: - Recurring expenses

enum BillingCycleUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case day
    case week
    case month
    case year

    var id: Self { self }
}

struct BillingCycle: Codable, Equatable, Sendable {
    var unit: BillingCycleUnit
    var interval: Int

    init(unit: BillingCycleUnit, interval: Int = 1) {
        self.unit = unit
        self.interval = max(1, interval)
    }

    func nextDate(
        onOrAfter date: Date,
        anchoredAt anchorDate: Date,
        calendar: Calendar = .current
    ) -> Date? {
        occurrenceDate(
            relativeTo: date,
            anchoredAt: anchorDate,
            inclusive: true,
            calendar: calendar
        )
    }

    func nextDate(
        after date: Date,
        anchoredAt anchorDate: Date,
        calendar: Calendar = .current
    ) -> Date? {
        occurrenceDate(
            relativeTo: date,
            anchoredAt: anchorDate,
            inclusive: false,
            calendar: calendar
        )
    }

    var annualMultiplier: Decimal {
        let safeInterval = Decimal(max(1, interval))
        switch unit {
        case .day:
            return 365 / safeInterval
        case .week:
            return 52 / safeInterval
        case .month:
            return 12 / safeInterval
        case .year:
            return 1 / safeInterval
        }
    }

    private func occurrenceDate(
        relativeTo date: Date,
        anchoredAt anchorDate: Date,
        inclusive: Bool,
        calendar: Calendar
    ) -> Date? {
        if date < anchorDate || (inclusive && date == anchorDate) {
            return anchorDate
        }

        let safeInterval = max(1, interval)
        let estimatedUnits: Int
        let component: Calendar.Component
        switch unit {
        case .day:
            estimatedUnits = calendar.dateComponents(
                [.day],
                from: anchorDate,
                to: date
            ).day ?? 0
            component = .day
        case .week:
            estimatedUnits = calendar.dateComponents(
                [.day],
                from: anchorDate,
                to: date
            ).day.map { $0 / 7 } ?? 0
            component = .weekOfYear
        case .month:
            estimatedUnits = calendar.dateComponents(
                [.month],
                from: anchorDate,
                to: date
            ).month ?? 0
            component = .month
        case .year:
            estimatedUnits = calendar.dateComponents(
                [.year],
                from: anchorDate,
                to: date
            ).year ?? 0
            component = .year
        }

        var occurrence = max(0, estimatedUnits / safeInterval)
        guard var candidate = calendar.date(
            byAdding: component,
            value: occurrence * safeInterval,
            to: anchorDate
        ) else {
            return nil
        }

        while candidate < date || (!inclusive && candidate == date) {
            occurrence += 1
            guard let next = calendar.date(
                byAdding: component,
                value: occurrence * safeInterval,
                to: anchorDate
            ) else {
                return nil
            }
            candidate = next
        }

        while occurrence > 0 {
            guard let previous = calendar.date(
                byAdding: component,
                value: (occurrence - 1) * safeInterval,
                to: anchorDate
            ) else {
                break
            }
            let previousQualifies = inclusive ? previous >= date : previous > date
            guard previousQualifies else { break }
            occurrence -= 1
            candidate = previous
        }
        return candidate
    }
}

struct RecurringExpense: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var amount: Decimal
    var currency: String
    var cycle: BillingCycle
    var anchorDate: Date
    var endDate: Date?
    var autoRenews: Bool
    var reminderEnabled: Bool
    var reminderLeadDays: Int
    var isEnabled: Bool
    var notes: String
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        amount: Decimal,
        currency: String = "CNY",
        cycle: BillingCycle,
        anchorDate: Date,
        endDate: Date? = nil,
        autoRenews: Bool = true,
        reminderEnabled: Bool = true,
        reminderLeadDays: Int = 3,
        isEnabled: Bool = true,
        notes: String = "",
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.amount = max(amount, 0)
        self.currency = currency.isEmpty ? "CNY" : currency.uppercased()
        self.cycle = cycle
        self.anchorDate = anchorDate
        self.endDate = endDate
        self.autoRenews = autoRenews
        self.reminderEnabled = reminderEnabled
        self.reminderLeadDays = max(0, reminderLeadDays)
        self.isEnabled = isEnabled
        self.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = createdAt
    }

    var annualEquivalent: Decimal {
        amount * cycle.annualMultiplier
    }

    var monthlyEquivalent: Decimal {
        annualEquivalent / 12
    }

    func nextDueDate(
        onOrAfter date: Date,
        calendar: Calendar = .current
    ) -> Date? {
        guard isEnabled,
              let dueDate = cycle.nextDate(
                onOrAfter: date,
                anchoredAt: anchorDate,
                calendar: calendar
              ),
              endDate.map({ dueDate <= $0 }) ?? true else {
            return nil
        }
        return dueDate
    }

    func nextDueDate(
        after date: Date,
        calendar: Calendar = .current
    ) -> Date? {
        guard isEnabled,
              let dueDate = cycle.nextDate(
                after: date,
                anchoredAt: anchorDate,
                calendar: calendar
              ),
              endDate.map({ dueDate <= $0 }) ?? true else {
            return nil
        }
        return dueDate
    }

    func remainingOccurrences(
        onOrAfter date: Date = .now,
        calendar: Calendar = .current
    ) -> Int? {
        guard let endDate else { return nil }
        guard var occurrence = nextDueDate(
            onOrAfter: date,
            calendar: calendar
        ) else {
            return 0
        }
        var count = 0
        while occurrence <= endDate {
            count += 1
            guard let next = cycle.nextDate(
                after: occurrence,
                anchoredAt: anchorDate,
                calendar: calendar
            ) else {
                break
            }
            occurrence = next
        }
        return count
    }

    func amountDue(
        from startDate: Date,
        through endDate: Date,
        calendar: Calendar = .current
    ) -> Decimal {
        guard startDate <= endDate,
              var occurrence = nextDueDate(
                onOrAfter: startDate,
                calendar: calendar
              ) else {
            return 0
        }
        var total: Decimal = 0
        while occurrence <= endDate {
            total += amount
            guard let next = nextDueDate(
                after: occurrence,
                calendar: calendar
            ) else {
                break
            }
            occurrence = next
        }
        return total
    }
}

// MARK: - Dashboard metrics

struct FinancialAllocationSlice: Identifiable, Equatable, Sendable {
    var type: FinancialAssetType
    var value: Decimal

    var id: String { type.rawValue }
}

struct ExpenseDueBucket: Identifiable, Equatable, Sendable {
    var index: Int
    var startDate: Date
    var endDate: Date
    var amount: Decimal

    var id: Int { index }
}

struct LifeMetrics: Equatable, Sendable {
    var inventoryReviewStatus: InventoryReviewStatus
    var activeInventoryItemCount: Int
    var healthyInventoryItemCount: Int
    var lowStockItemCount: Int
    var expiringItemCount: Int
    var heldFinancialAssetCount: Int
    var freshFinancialPriceCount: Int
    var financialCurrentValue: Decimal
    var financialUnrealizedGainLoss: Decimal
    var staleFinancialPriceCount: Int
    var financialAllocation: [FinancialAllocationSlice]
    var durablePurchaseTotal: Decimal
    var durableDailyCost: Decimal
    var expiringWarrantyCount: Int
    var recurringMonthlyAmount: Decimal
    var recurringAnnualAmount: Decimal
    var recurringDueWithin30Days: Decimal
    var recurringDueBuckets: [ExpenseDueBucket]
}

extension LifeData {
    func metrics(
        asOf date: Date = .now,
        calendar: Calendar = .current
    ) -> LifeMetrics {
        let activeInventoryItems = householdItems.filter { !$0.isArchived }
        let activeDurableAssets = durableAssets.filter { !$0.isArchived }
        let positionedAssets = financialAssets
            .filter { !$0.isArchived }
            .compactMap { asset -> (FinancialAsset, FinancialPosition)? in
                guard let position = try? financialPosition(
                    for: asset,
                    asOf: date,
                    calendar: calendar
                ) else {
                    return nil
                }
                return (asset, position)
            }
        let positions = positionedAssets.map(\.1)
        let heldAssets = positionedAssets.filter { $0.1.quantity > 0 }
        let allocationByType = heldAssets.reduce(
            into: [FinancialAssetType: Decimal]()
        ) { allocation, element in
            guard let value = element.1.currentValue, value > 0 else { return }
            allocation[element.0.type, default: 0] += value
        }
        let financialAllocation: [FinancialAllocationSlice] =
            FinancialAssetType.allCases.compactMap { type in
            guard let value = allocationByType[type], value > 0 else { return nil }
            return FinancialAllocationSlice(type: type, value: value)
        }
        let activeExpenses = recurringExpenses.filter { $0.isEnabled }
        let recurringDueBuckets = makeRecurringDueBuckets(
            expenses: activeExpenses,
            asOf: date,
            calendar: calendar
        )

        return LifeMetrics(
            inventoryReviewStatus: inventoryReviewStatus(
                at: date,
                calendar: calendar
            ),
            activeInventoryItemCount: activeInventoryItems.count,
            healthyInventoryItemCount: activeInventoryItems.lazy.filter {
                guard let quantity = currentQuantity(for: $0) else { return false }
                return quantity > $0.lowStockThreshold
            }.count,
            lowStockItemCount: lowStockItems().count,
            expiringItemCount: itemsExpiring(
                withinDays: 30,
                from: date,
                calendar: calendar
            ).count,
            heldFinancialAssetCount: heldAssets.count,
            freshFinancialPriceCount: heldAssets.lazy.filter {
                $0.1.currentUnitPrice != nil && !$0.1.isPriceStale
            }.count,
            financialCurrentValue: positions.reduce(0) {
                $0 + ($1.currentValue ?? 0)
            },
            financialUnrealizedGainLoss: positions.reduce(0) {
                $0 + ($1.unrealizedGainLoss ?? 0)
            },
            staleFinancialPriceCount: positions.lazy.filter(\.isPriceStale).count,
            financialAllocation: financialAllocation,
            durablePurchaseTotal: activeDurableAssets.reduce(0) {
                $0 + $1.purchasePrice
            },
            durableDailyCost: activeDurableAssets.reduce(0) {
                $0 + $1.dailyCost(asOf: date, calendar: calendar)
            },
            expiringWarrantyCount: activeDurableAssets.lazy.filter {
                $0.warrantyStatus(
                    asOf: date,
                    warningDays: 30,
                    calendar: calendar
                ) == .expiring
            }.count,
            recurringMonthlyAmount: activeExpenses.reduce(0) {
                $0 + $1.monthlyEquivalent
            },
            recurringAnnualAmount: activeExpenses.reduce(0) {
                $0 + $1.annualEquivalent
            },
            recurringDueWithin30Days: recurringDueBuckets.reduce(0) {
                $0 + $1.amount
            },
            recurringDueBuckets: recurringDueBuckets
        )
    }

    private func makeRecurringDueBuckets(
        expenses: [RecurringExpense],
        asOf date: Date,
        calendar: Calendar
    ) -> [ExpenseDueBucket] {
        let referenceDay = calendar.startOfDay(for: date)
        let dayRanges = [0...6, 7...13, 14...20, 21...30]
        var buckets = dayRanges.enumerated().map { index, range in
            ExpenseDueBucket(
                index: index,
                startDate: calendar.date(
                    byAdding: .day,
                    value: range.lowerBound,
                    to: referenceDay
                ) ?? referenceDay,
                endDate: calendar.date(
                    byAdding: .day,
                    value: range.upperBound,
                    to: referenceDay
                ) ?? referenceDay,
                amount: 0
            )
        }
        let finalExclusiveDate = calendar.date(
            byAdding: .day,
            value: 31,
            to: referenceDay
        ) ?? date

        for expense in expenses {
            guard var dueDate = expense.nextDueDate(
                onOrAfter: date,
                calendar: calendar
            ) else {
                continue
            }
            while dueDate < finalExclusiveDate {
                let dueDay = calendar.startOfDay(for: dueDate)
                let dayOffset = calendar.dateComponents(
                    [.day],
                    from: referenceDay,
                    to: dueDay
                ).day ?? -1
                switch dayOffset {
                case 0...6:
                    buckets[0].amount += expense.amount
                case 7...13:
                    buckets[1].amount += expense.amount
                case 14...20:
                    buckets[2].amount += expense.amount
                case 21...30:
                    buckets[3].amount += expense.amount
                default:
                    break
                }
                guard let nextDate = expense.nextDueDate(
                    after: dueDate,
                    calendar: calendar
                ) else {
                    break
                }
                dueDate = nextDate
            }
        }
        return buckets
    }
}
