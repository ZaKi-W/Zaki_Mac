import Foundation

enum LifeMutationError: LocalizedError, Equatable {
    case financialAssetNotFound
    case invalidAmount

    var errorDescription: String? {
        switch self {
        case .financialAssetNotFound:
            "The financial asset no longer exists."
        case .invalidAmount:
            "Enter a valid non-negative amount."
        }
    }
}

@MainActor
extension AppModel {
    @discardableResult
    func saveHouseholdItem(
        _ item: HouseholdItem,
        initialQuantity: Decimal? = nil,
        initialUnitPrice: Decimal? = nil
    ) -> Bool {
        var updated = life
        if let index = updated.householdItems.firstIndex(where: { $0.id == item.id }) {
            updated.householdItems[index] = item
            commitLife(updated)
            return true
        }

        guard
            let initialQuantity,
            initialQuantity >= 0,
            let initialUnitPrice,
            initialUnitPrice > 0
        else {
            return false
        }

        updated.householdItems.append(item)
        guard updated.appendInventoryUpdate(
            itemID: item.id,
            quantity: initialQuantity,
            unitPrice: initialUnitPrice
        ) else {
            return false
        }

        commitLife(updated)
        return true
    }

    @discardableResult
    func recordInventoryCount(
        itemID: String,
        quantity: Decimal,
        unitPrice: Decimal,
        at date: Date = .now
    ) -> Bool {
        var updated = life
        guard updated.appendInventoryUpdate(
            itemID: itemID,
            quantity: quantity,
            unitPrice: unitPrice,
            recordedAt: date
        ) else {
            return false
        }
        commitLife(updated, reschedule: false)
        return true
    }

    @discardableResult
    func correctLatestInventoryPrice(
        itemID: String,
        unitPrice: Decimal
    ) -> Bool {
        var updated = life
        guard updated.correctLatestInventoryPrice(
            itemID: itemID,
            unitPrice: unitPrice
        ) else {
            return false
        }
        commitLife(updated, reschedule: false)
        return true
    }

    func archiveHouseholdItem(_ item: HouseholdItem) {
        var updated = life
        guard let index = updated.householdItems.firstIndex(where: {
            $0.id == item.id
        }) else {
            return
        }
        updated.householdItems[index].isArchived = true
        commitLife(updated)
    }

    func updateInventoryReviewSchedule(
        weekday: Int,
        hour: Int,
        minute: Int,
        isEnabled: Bool
    ) {
        var updated = life
        updated.inventoryReviewSettings = InventoryReviewSettings(
            isEnabled: isEnabled,
            weekday: weekday,
            hour: hour,
            minute: minute
        )
        commitLife(updated)
    }

    func completeInventoryReview(
        _ entries: [String: InventoryReviewEntry],
        at date: Date = .now,
        calendar: Calendar = .current
    ) {
        guard
            !entries.isEmpty,
            let week = calendar.dateInterval(of: .weekOfYear, for: date)
        else {
            return
        }

        let activeIDs = Set(
            life.householdItems
                .filter { !$0.isArchived }
                .map(\.id)
        )
        let validEntries = entries.filter {
            activeIDs.contains($0.key)
                && $0.value.quantity >= 0
                && $0.value.unitPrice > 0
        }
        guard !validEntries.isEmpty else { return }

        let session = InventoryReviewSession(
            scheduledWeekStart: week.start,
            completedAt: date,
            reviewedItemIDs: Set(validEntries.keys)
        )
        var updated = life
        updated.inventoryReviewSessions.append(session)
        for (itemID, entry) in validEntries {
            guard updated.appendInventoryUpdate(
                itemID: itemID,
                quantity: entry.quantity,
                unitPrice: entry.unitPrice,
                recordedAt: date,
                source: .weeklyReview(sessionID: session.id)
            ) else {
                return
            }
        }
        commitLife(updated)
    }

    func saveDurableAsset(_ asset: DurableAsset) {
        var updated = life
        if let index = updated.durableAssets.firstIndex(where: {
            $0.id == asset.id
        }) {
            updated.durableAssets[index] = asset
        } else {
            updated.durableAssets.append(asset)
        }
        commitLife(updated, reschedule: false)
    }

    func archiveDurableAsset(_ asset: DurableAsset) {
        var updated = life
        guard let index = updated.durableAssets.firstIndex(where: {
            $0.id == asset.id
        }) else {
            return
        }
        updated.durableAssets[index].isArchived = true
        commitLife(updated, reschedule: false)
    }

    func saveFinancialAsset(_ asset: FinancialAsset) {
        var updated = life
        if let index = updated.financialAssets.firstIndex(where: {
            $0.id == asset.id
        }) {
            updated.financialAssets[index] = asset
        } else {
            updated.financialAssets.append(asset)
        }
        commitLife(updated, reschedule: false)
    }

    func archiveFinancialAsset(_ asset: FinancialAsset) {
        var updated = life
        guard let index = updated.financialAssets.firstIndex(where: {
            $0.id == asset.id
        }) else {
            return
        }
        updated.financialAssets[index].isArchived = true
        commitLife(updated, reschedule: false)
    }

    func addAssetTransaction(_ transaction: AssetTransaction) throws {
        guard
            life.financialAssets.contains(where: {
                $0.id == transaction.assetID && !$0.isArchived
            })
        else {
            throw LifeMutationError.financialAssetNotFound
        }
        guard
            transaction.quantity > 0,
            transaction.unitPrice >= 0,
            transaction.fee >= 0
        else {
            throw LifeMutationError.invalidAmount
        }

        var updated = life
        updated.assetTransactions.append(transaction)
        _ = try updated.financialPosition(
            for: transaction.assetID,
            asOf: max(.now, transaction.tradedAt)
        )
        commitLife(updated, reschedule: false)
    }

    func recordAssetPrice(
        assetID: String,
        unitPrice: Decimal,
        at date: Date = .now
    ) {
        guard
            unitPrice >= 0,
            life.financialAssets.contains(where: {
                $0.id == assetID && !$0.isArchived
            })
        else {
            return
        }
        var updated = life
        updated.assetPriceSnapshots.append(
            AssetPriceSnapshot(
                assetID: assetID,
                unitPrice: unitPrice,
                recordedAt: date
            )
        )
        commitLife(updated, reschedule: false)
    }

    func saveRecurringExpense(_ expense: RecurringExpense) {
        var updated = life
        if let index = updated.recurringExpenses.firstIndex(where: {
            $0.id == expense.id
        }) {
            updated.recurringExpenses[index] = expense
        } else {
            updated.recurringExpenses.append(expense)
        }
        commitLife(updated)
    }

    func archiveRecurringExpense(_ expense: RecurringExpense) {
        var updated = life
        guard let index = updated.recurringExpenses.firstIndex(where: {
            $0.id == expense.id
        }) else {
            return
        }
        updated.recurringExpenses[index].isEnabled = false
        updated.recurringExpenses[index].reminderEnabled = false
        commitLife(updated)
    }
}
