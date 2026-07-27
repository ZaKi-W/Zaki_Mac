import XCTest
@testable import Moment

final class MomentTests: XCTestCase {
    func testReminderSettlementAndBoundary() {
        let start = Date(timeIntervalSince1970: 1_000)
        var repeating = ReminderRecord(
            content: "Stretch",
            intervalSeconds: 60,
            repeats: true,
            isEnabled: true,
            createdAt: start
        )
        repeating.settle(at: start.addingTimeInterval(60))
        XCTAssertTrue(repeating.isEnabled)
        XCTAssertEqual(
            repeating.nextTriggerAt,
            start.addingTimeInterval(120)
        )

        var once = ReminderRecord(
            content: "Drink water",
            intervalSeconds: 59,
            repeats: false,
            isEnabled: true,
            createdAt: start
        )
        once.settle(at: start.addingTimeInterval(59))
        XCTAssertFalse(once.isEnabled)
        XCTAssertNotNil(once.completedAt)
        XCTAssertNil(once.nextTriggerAt)
    }

    func testURLResolutionAndNormalization() {
        XCTAssertEqual(
            URLResolver.resolve("example.com/path", language: .en)?.absoluteString,
            "https://example.com/path"
        )
        XCTAssertEqual(
            URLResolver.resolve("localhost:5173", language: .zh)?.absoluteString,
            "http://localhost:5173"
        )
        XCTAssertEqual(
            URLResolver.normalized(URL(string: "https://www.Example.com/")!),
            "https://example.com"
        )
        XCTAssertTrue(
            URLResolver.resolve("片刻", language: .zh)?.absoluteString
                .hasPrefix("https://www.bing.com/search?q=") == true
        )
    }

    func testShortcutConversion() {
        let shortcut = ShortcutParser.parse("CommandOrControl+Shift+H")
        XCTAssertEqual(shortcut?.storageValue, "Command+Shift+H")
        XCTAssertEqual(shortcut?.displayValue, "⌘⇧H")
    }

    func testLegacyMigrationSkipsDamagedRows() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "state.json")
        let json = """
        {
          "version": 2,
          "reminders": [
            {
              "id": "valid",
              "content": "Take a breath",
              "intervalSeconds": 60,
              "repeat": true,
              "enabled": true,
              "createdAt": "2026-07-24T10:00:00.000Z",
              "nextTriggerAt": "2026-07-24T10:01:00.000Z",
              "completedAt": null
            },
            {
              "id": "invalid",
              "content": "",
              "intervalSeconds": 0
            }
          ],
          "bookmarks": [
            {
              "id": "bookmark",
              "title": "Example",
              "url": "https://example.com",
              "createdAt": "2026-07-24T10:00:00.000Z"
            }
          ],
          "settings": {
            "language": "zh",
            "themeMode": "dark",
            "globalShortcut": "CommandOrControl+Shift+H",
            "browserDarkMode": true
          }
        }
        """
        try Data(json.utf8).write(to: source)

        let result = try await LegacyMigrator(sourceURL: source).migrate()
        XCTAssertEqual(result?.data.reminders.map(\.id), ["valid"])
        XCTAssertEqual(result?.data.bookmarks.map(\.id), ["bookmark"])
        XCTAssertEqual(result?.preferences.appearance, .dark)
        XCTAssertEqual(result?.preferences.globalShortcut, "Command+Shift+H")
    }

    func testVersionOneDataLoadsWithEmptyLifeData() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = Data(
            """
            {
              "version": 1,
              "reminders": [],
              "bookmarks": []
            }
            """.utf8
        )

        let decoded = try decoder.decode(PersistedAppData.self, from: data)

        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.life, .empty)
    }

    func testTodoRecordCompletesAndReopens() {
        let completedAt = Date(timeIntervalSince1970: 2_000)
        var todo = TodoRecord(title: "  Buy milk  ")

        XCTAssertEqual(todo.title, "Buy milk")
        XCTAssertFalse(todo.isCompleted)

        todo.rename("  Buy oat milk  ")
        XCTAssertEqual(todo.title, "Buy oat milk")

        todo.setCompleted(true, at: completedAt)
        XCTAssertTrue(todo.isCompleted)
        XCTAssertEqual(todo.completedAt, completedAt)

        todo.setCompleted(false, at: completedAt)
        XCTAssertFalse(todo.isCompleted)
        XCTAssertNil(todo.completedAt)
    }

    func testOlderDataLoadsWithEmptyTodosAndTodosRoundTrip() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let oldData = Data(
            """
            {
              "version": 3,
              "reminders": [],
              "bookmarks": [],
              "life": {}
            }
            """.utf8
        )

        let restoredOldData = try decoder.decode(
            PersistedAppData.self,
            from: oldData
        )
        XCTAssertTrue(restoredOldData.todos.isEmpty)

        let original = PersistedAppData(
            reminders: [],
            bookmarks: [],
            todos: [
                TodoRecord(
                    id: "todo",
                    title: "Ship release",
                    createdAt: Date(timeIntervalSince1970: 3_000)
                )
            ]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let restored = try decoder.decode(
            PersistedAppData.self,
            from: encoder.encode(original)
        )

        XCTAssertEqual(restored, original)
        XCTAssertEqual(restored.version, 4)
    }

    func testVersionTwoDataRoundTripsLifeData() throws {
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let original = PersistedAppData(
            reminders: [],
            bookmarks: [],
            life: LifeData(
                householdItems: [
                    HouseholdItem(
                        id: "soap",
                        name: "Soap",
                        unit: "bars",
                        createdAt: timestamp
                    )
                ],
                inventoryCounts: [
                    InventoryCount(
                        id: "soap-count",
                        itemID: "soap",
                        quantity: 3,
                        recordedAt: timestamp
                    )
                ]
            )
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let restored = try decoder.decode(
            PersistedAppData.self,
            from: encoder.encode(original)
        )

        XCTAssertEqual(restored, original)
    }

    func testInventoryUsesLatestCountAndKeepsSkippedItemsUnchanged() {
        let item = HouseholdItem(
            id: "rice",
            name: "Rice",
            unit: "kg",
            lowStockThreshold: 2
        )
        let earlier = InventoryCount(
            id: "earlier",
            itemID: item.id,
            quantity: 5,
            recordedAt: Date(timeIntervalSince1970: 100)
        )
        let latest = InventoryCount(
            id: "latest",
            itemID: item.id,
            quantity: 2,
            recordedAt: Date(timeIntervalSince1970: 200)
        )
        let life = LifeData(
            householdItems: [item],
            inventoryCounts: [earlier, latest]
        )

        XCTAssertEqual(life.currentQuantity(for: item.id), 2)
        XCTAssertTrue(life.isLowStock(item))
        XCTAssertEqual(life.inventoryCounts.count, 2)
    }

    func testDurableDailyCostAndFinancialPosition() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let purchaseDate = Date(timeIntervalSince1970: 0)
        let tenDaysLater = calendar.date(
            byAdding: .day,
            value: 10,
            to: purchaseDate
        )!
        let durable = DurableAsset(
            name: "Laptop",
            purchaseDate: purchaseDate,
            purchasePrice: 1_000
        )
        XCTAssertEqual(
            durable.dailyCost(asOf: tenDaysLater, calendar: calendar),
            100
        )

        let asset = FinancialAsset(
            id: "fund",
            name: "Index Fund",
            type: .fund
        )
        let life = LifeData(
            financialAssets: [asset],
            assetTransactions: [
                AssetTransaction(
                    id: "buy",
                    assetID: asset.id,
                    kind: .buy,
                    quantity: 10,
                    unitPrice: 100,
                    tradedAt: purchaseDate
                ),
                AssetTransaction(
                    id: "sell",
                    assetID: asset.id,
                    kind: .sell,
                    quantity: 4,
                    unitPrice: 150,
                    tradedAt: Date(timeIntervalSince1970: 1)
                )
            ],
            assetPriceSnapshots: [
                AssetPriceSnapshot(
                    assetID: asset.id,
                    unitPrice: 120,
                    recordedAt: Date(timeIntervalSince1970: 2)
                )
            ]
        )
        let position = try life.financialPosition(
            for: asset,
            asOf: Date(timeIntervalSince1970: 3),
            calendar: calendar
        )

        XCTAssertEqual(position.quantity, 6)
        XCTAssertEqual(position.averageUnitCost, 100)
        XCTAssertEqual(position.currentValue, 720)
        XCTAssertEqual(position.realizedGainLoss, 200)
        XCTAssertEqual(position.unrealizedGainLoss, 120)

        var oversold = life
        oversold.assetTransactions.append(
            AssetTransaction(
                id: "oversell",
                assetID: asset.id,
                kind: .sell,
                quantity: 7,
                unitPrice: 120,
                tradedAt: Date(timeIntervalSince1970: 4)
            )
        )
        XCTAssertThrowsError(
            try oversold.financialPosition(
                for: asset,
                asOf: Date(timeIntervalSince1970: 5),
                calendar: calendar
            )
        )
    }

    func testRecurringExpenseHandlesMonthEndAndQuarterlyAverage() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let anchor = calendar.date(
            from: DateComponents(year: 2026, month: 1, day: 31, hour: 9)
        )!
        let expense = RecurringExpense(
            name: "Property Fee",
            amount: 300,
            cycle: BillingCycle(unit: .month, interval: 3),
            anchorDate: anchor
        )
        let query = calendar.date(
            from: DateComponents(year: 2026, month: 2, day: 1)
        )!

        XCTAssertEqual(expense.monthlyEquivalent, 100)
        XCTAssertEqual(
            expense.nextDueDate(onOrAfter: query, calendar: calendar),
            calendar.date(
                from: DateComponents(year: 2026, month: 4, day: 30, hour: 9)
            )
        )
    }

    func testVersionTwoCategoryFieldsAreIgnoredAndNotReencoded() throws {
        let data = Data(
            """
            {
              "version": 2,
              "reminders": [],
              "bookmarks": [],
              "life": {
                "householdItems": [
                  {
                    "id": "soap",
                    "name": "Soap",
                    "category": "Cleaning",
                    "storageLocation": "Bathroom",
                    "unit": "bars",
                    "lowStockThreshold": 1,
                    "isArchived": false,
                    "createdAt": "2026-01-01T00:00:00Z"
                  }
                ],
                "inventoryCounts": [],
                "inventoryReviewSessions": [],
                "inventoryReviewSettings": {
                  "isEnabled": true,
                  "weekday": 1,
                  "hour": 20,
                  "minute": 0
                },
                "durableAssets": [
                  {
                    "id": "laptop",
                    "name": "Laptop",
                    "category": "Electronics",
                    "purchaseDate": "2026-01-01T00:00:00Z",
                    "purchasePrice": 8000,
                    "currency": "CNY",
                    "notes": "",
                    "isArchived": false,
                    "createdAt": "2026-01-01T00:00:00Z"
                  }
                ],
                "financialAssets": [],
                "assetTransactions": [],
                "assetPriceSnapshots": [],
                "recurringExpenses": [
                  {
                    "id": "subscription",
                    "name": "Subscription",
                    "category": "Software",
                    "amount": 30,
                    "currency": "CNY",
                    "cycle": {
                      "unit": "month",
                      "interval": 1
                    },
                    "anchorDate": "2026-01-01T00:00:00Z",
                    "autoRenews": true,
                    "reminderEnabled": true,
                    "reminderLeadDays": 3,
                    "isEnabled": true,
                    "notes": "",
                    "createdAt": "2026-01-01T00:00:00Z"
                  }
                ]
              }
            }
            """.utf8
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(PersistedAppData.self, from: data)

        XCTAssertEqual(decoded.life.householdItems.first?.name, "Soap")
        XCTAssertEqual(decoded.life.durableAssets.first?.name, "Laptop")
        XCTAssertEqual(decoded.life.recurringExpenses.first?.name, "Subscription")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encodedObject = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: encoder.encode(decoded)
            ) as? [String: Any]
        )
        let life = try XCTUnwrap(encodedObject["life"] as? [String: Any])
        let householdItems = try XCTUnwrap(
            life["householdItems"] as? [[String: Any]]
        )
        let durableAssets = try XCTUnwrap(
            life["durableAssets"] as? [[String: Any]]
        )
        let recurringExpenses = try XCTUnwrap(
            life["recurringExpenses"] as? [[String: Any]]
        )

        XCTAssertNil(householdItems.first?["category"])
        XCTAssertNil(durableAssets.first?["category"])
        XCTAssertNil(recurringExpenses.first?["category"])
    }

    func testLifeMetricsCountsAndFinancialAllocation() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let asOf = calendar.date(
            from: DateComponents(
                year: 2026,
                month: 2,
                day: 1,
                hour: 12
            )
        )!
        let freshPriceDate = calendar.date(
            byAdding: .day,
            value: -7,
            to: asOf
        )!
        let stalePriceDate = calendar.date(
            byAdding: .day,
            value: -8,
            to: asOf
        )!
        let inventoryItems = [
            HouseholdItem(id: "healthy", name: "Healthy", lowStockThreshold: 2),
            HouseholdItem(id: "low", name: "Low", lowStockThreshold: 1),
            HouseholdItem(id: "missing", name: "Missing", lowStockThreshold: 0),
            HouseholdItem(
                id: "archived",
                name: "Archived",
                lowStockThreshold: 0,
                isArchived: true
            )
        ]
        let stock = FinancialAsset(
            id: "stock",
            name: "Stock",
            type: .stock
        )
        let fund = FinancialAsset(
            id: "fund",
            name: "Fund",
            type: .fund
        )
        let cash = FinancialAsset(
            id: "cash",
            name: "Cash",
            type: .cash
        )
        let zeroHolding = FinancialAsset(
            id: "zero",
            name: "Closed Deposit",
            type: .deposit
        )
        let archivedAsset = FinancialAsset(
            id: "archived-asset",
            name: "Archived Asset",
            type: .other,
            isArchived: true
        )
        let life = LifeData(
            householdItems: inventoryItems,
            inventoryCounts: [
                InventoryCount(itemID: "healthy", quantity: 3),
                InventoryCount(itemID: "low", quantity: 1),
                InventoryCount(itemID: "archived", quantity: 100)
            ],
            financialAssets: [
                stock,
                fund,
                cash,
                zeroHolding,
                archivedAsset
            ],
            assetTransactions: [
                AssetTransaction(
                    assetID: stock.id,
                    kind: .buy,
                    quantity: 10,
                    unitPrice: 10,
                    tradedAt: freshPriceDate
                ),
                AssetTransaction(
                    assetID: fund.id,
                    kind: .buy,
                    quantity: 2,
                    unitPrice: 40,
                    tradedAt: stalePriceDate
                ),
                AssetTransaction(
                    assetID: cash.id,
                    kind: .buy,
                    quantity: 100,
                    unitPrice: 1,
                    tradedAt: freshPriceDate
                ),
                AssetTransaction(
                    id: "zero-buy",
                    assetID: zeroHolding.id,
                    kind: .buy,
                    quantity: 10,
                    unitPrice: 1,
                    tradedAt: stalePriceDate
                ),
                AssetTransaction(
                    id: "zero-sell",
                    assetID: zeroHolding.id,
                    kind: .sell,
                    quantity: 10,
                    unitPrice: 1,
                    tradedAt: freshPriceDate
                ),
                AssetTransaction(
                    assetID: archivedAsset.id,
                    kind: .buy,
                    quantity: 1,
                    unitPrice: 1,
                    tradedAt: freshPriceDate
                )
            ],
            assetPriceSnapshots: [
                AssetPriceSnapshot(
                    assetID: stock.id,
                    unitPrice: 20,
                    recordedAt: freshPriceDate
                ),
                AssetPriceSnapshot(
                    assetID: fund.id,
                    unitPrice: 50,
                    recordedAt: stalePriceDate
                ),
                AssetPriceSnapshot(
                    assetID: zeroHolding.id,
                    unitPrice: 99,
                    recordedAt: freshPriceDate
                ),
                AssetPriceSnapshot(
                    assetID: archivedAsset.id,
                    unitPrice: 1000,
                    recordedAt: freshPriceDate
                )
            ]
        )

        let metrics = life.metrics(asOf: asOf, calendar: calendar)

        XCTAssertEqual(metrics.activeInventoryItemCount, 3)
        XCTAssertEqual(metrics.healthyInventoryItemCount, 1)
        XCTAssertEqual(metrics.lowStockItemCount, 1)
        XCTAssertEqual(metrics.heldFinancialAssetCount, 3)
        XCTAssertEqual(metrics.freshFinancialPriceCount, 1)
        XCTAssertEqual(metrics.staleFinancialPriceCount, 2)
        XCTAssertEqual(metrics.financialCurrentValue, 300)
        XCTAssertEqual(
            metrics.financialAllocation,
            [
                FinancialAllocationSlice(type: .stock, value: 200),
                FinancialAllocationSlice(type: .fund, value: 100)
            ]
        )
    }

    func testEmptyLifeMetricsHaveFourZeroExpenseBuckets() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let asOf = calendar.date(
            from: DateComponents(year: 2026, month: 1, day: 28, hour: 9)
        )!

        let metrics = LifeData.empty.metrics(asOf: asOf, calendar: calendar)

        XCTAssertEqual(metrics.activeInventoryItemCount, 0)
        XCTAssertEqual(metrics.healthyInventoryItemCount, 0)
        XCTAssertEqual(metrics.heldFinancialAssetCount, 0)
        XCTAssertEqual(metrics.freshFinancialPriceCount, 0)
        XCTAssertTrue(metrics.financialAllocation.isEmpty)
        XCTAssertEqual(metrics.recurringDueBuckets.map(\.index), [0, 1, 2, 3])
        XCTAssertEqual(metrics.recurringDueBuckets.map(\.amount), [0, 0, 0, 0])
        XCTAssertEqual(metrics.recurringDueWithin30Days, 0)
    }

    func testRecurringDueBucketsIncludeEveryOccurrenceAcrossMonthBoundary() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let asOf = calendar.date(
            from: DateComponents(year: 2026, month: 1, day: 28, hour: 9)
        )!
        let monthlyAnchor = calendar.date(
            from: DateComponents(year: 2026, month: 1, day: 31, hour: 9)
        )!
        let fiveDayAnchor = calendar.date(
            from: DateComponents(year: 2026, month: 1, day: 30, hour: 9)
        )!
        let life = LifeData(
            recurringExpenses: [
                RecurringExpense(
                    name: "Weekly",
                    amount: 10,
                    cycle: BillingCycle(unit: .week),
                    anchorDate: asOf
                ),
                RecurringExpense(
                    name: "Monthly",
                    amount: 100,
                    cycle: BillingCycle(unit: .month),
                    anchorDate: monthlyAnchor
                ),
                RecurringExpense(
                    name: "Every Five Days",
                    amount: 2,
                    cycle: BillingCycle(unit: .day, interval: 5),
                    anchorDate: fiveDayAnchor
                )
            ]
        )

        let metrics = life.metrics(asOf: asOf, calendar: calendar)

        XCTAssertEqual(metrics.recurringDueBuckets.map(\.amount), [112, 14, 12, 24])
        XCTAssertEqual(metrics.recurringDueWithin30Days, 162)
        XCTAssertEqual(
            metrics.recurringDueBuckets.map(\.startDate),
            [0, 7, 14, 21].map {
                calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: asOf))!
            }
        )
        XCTAssertEqual(
            metrics.recurringDueBuckets.map(\.endDate),
            [6, 13, 20, 30].map {
                calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: asOf))!
            }
        )
    }

    func testOlderLifeDataWithMissingFieldsUsesDefaults() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let versionTwoData = Data(
            """
            {
              "version": 2,
              "reminders": [],
              "bookmarks": [],
              "life": {
                "householdItems": []
              }
            }
            """.utf8
        )

        let decoded = try decoder.decode(
            PersistedAppData.self,
            from: versionTwoData
        )

        XCTAssertEqual(decoded.life, .empty)
        XCTAssertEqual(decoded.life.inventoryReviewSettings, .default)
        XCTAssertTrue(decoded.life.inventoryPriceRecords.isEmpty)
    }

    func testVersionThreeInventoryPriceRecordsRoundTrip() throws {
        let purchasedAt = Date(timeIntervalSince1970: 1_000)
        let createdAt = Date(timeIntervalSince1970: 2_000)
        let original = PersistedAppData(
            version: 3,
            reminders: [],
            bookmarks: [],
            life: LifeData(
                inventoryPriceRecords: [
                    InventoryPriceRecord(
                        id: "price",
                        itemID: "soap",
                        unitPrice: 12.5,
                        purchasedAt: purchasedAt,
                        createdAt: createdAt,
                        stockIncrease: 3
                    )
                ]
            )
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let restored = try decoder.decode(
            PersistedAppData.self,
            from: encoder.encode(original)
        )

        XCTAssertEqual(restored, original)
        XCTAssertEqual(restored.version, 3)
        XCTAssertEqual(
            restored.life.inventoryPriceRecords.first?.stockIncrease,
            3
        )
    }

    func testInventoryPriceHistorySortsStableAndSurvivesItemArchival() {
        let firstPurchase = Date(timeIntervalSince1970: 100)
        let secondPurchase = Date(timeIntervalSince1970: 200)
        let firstCreation = Date(timeIntervalSince1970: 300)
        let secondCreation = Date(timeIntervalSince1970: 400)
        let archivedItem = HouseholdItem(
            id: "soap",
            name: "Soap",
            isArchived: true
        )
        let life = LifeData(
            householdItems: [archivedItem],
            inventoryPriceRecords: [
                InventoryPriceRecord(
                    id: "later-purchase",
                    itemID: archivedItem.id,
                    unitPrice: 13,
                    purchasedAt: secondPurchase,
                    createdAt: firstCreation
                ),
                InventoryPriceRecord(
                    id: "same-day-later-creation",
                    itemID: archivedItem.id,
                    unitPrice: 12,
                    purchasedAt: firstPurchase,
                    createdAt: secondCreation
                ),
                InventoryPriceRecord(
                    id: "z-id",
                    itemID: archivedItem.id,
                    unitPrice: 11,
                    purchasedAt: firstPurchase,
                    createdAt: firstCreation
                ),
                InventoryPriceRecord(
                    id: "a-id",
                    itemID: archivedItem.id,
                    unitPrice: 10,
                    purchasedAt: firstPurchase,
                    createdAt: firstCreation
                ),
                InventoryPriceRecord(
                    id: "other-item",
                    itemID: "other",
                    unitPrice: 99,
                    purchasedAt: firstPurchase,
                    createdAt: firstCreation
                )
            ]
        )

        XCTAssertEqual(
            life.inventoryPriceHistory(for: archivedItem).map(\.id),
            [
                "a-id",
                "z-id",
                "same-day-later-creation",
                "later-purchase"
            ]
        )
        XCTAssertEqual(life.inventoryPriceRecords.count, 5)
    }

    func testInventoryPriceSummaryCoversEveryComparisonState() throws {
        func summary(_ prices: [Decimal]) throws -> InventoryPriceSummary {
            let records = prices.enumerated().map { index, price in
                InventoryPriceRecord(
                    id: "price-\(index)",
                    itemID: "item",
                    unitPrice: price,
                    purchasedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                    createdAt: Date(timeIntervalSince1970: TimeInterval(index))
                )
            }
            return try XCTUnwrap(
                LifeData(inventoryPriceRecords: records)
                    .inventoryPriceSummary(for: "item")
            )
        }

        let insufficient = try summary([42])
        XCTAssertEqual(insufficient.comparison, .insufficientHistory)
        XCTAssertEqual(insufficient.lowest, 42)
        XCTAssertEqual(insufficient.averageUnitPrice, 42)

        let historicalLow = try summary([10, 20, 10])
        XCTAssertEqual(historicalLow.comparison, .historicalLow)
        XCTAssertEqual(historicalLow.lowest, 10)

        let cheaper = try summary([10, 20, 12])
        XCTAssertEqual(cheaper.latest.unitPrice, 12)
        XCTAssertEqual(cheaper.lowest, 10)
        XCTAssertEqual(cheaper.averageUnitPrice, 14)
        XCTAssertEqual(cheaper.comparison, .cheaper(percentage: 20))

        let equal = try summary([10, 20, 15])
        XCTAssertEqual(equal.comparison, .equal)
        XCTAssertEqual(equal.averageUnitPrice, 15)

        let moreExpensive = try summary([10, 20, 18])
        XCTAssertEqual(
            moreExpensive.comparison,
            .moreExpensive(percentage: 20)
        )
        XCTAssertEqual(
            try summary([10, 30]).comparison,
            .moreExpensive(percentage: 200)
        )
        XCTAssertNil(
            LifeData.empty.inventoryPriceSummary(for: "missing")
        )
    }

    func testInventoryPriceRecordPreservesInvalidValuesForMutationValidation() throws {
        let original = InventoryPriceRecord(
            id: "invalid",
            itemID: "soap",
            unitPrice: -5,
            purchasedAt: Date(timeIntervalSince1970: 100),
            createdAt: Date(timeIntervalSince1970: 200),
            stockIncrease: -2
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let restored = try decoder.decode(
            InventoryPriceRecord.self,
            from: encoder.encode(original)
        )

        XCTAssertEqual(original.unitPrice, -5)
        XCTAssertEqual(original.stockIncrease, -2)
        XCTAssertEqual(restored, original)
    }

    func testAppendInventoryUpdateWritesCountAndPriceAtomically() {
        let item = HouseholdItem(id: "soap", name: "Soap")
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let source = InventoryCountSource.weeklyReview(sessionID: "review")
        var life = LifeData(householdItems: [item])

        let didAppend = life.appendInventoryUpdate(
            id: "shared-update",
            itemID: item.id,
            quantity: 4,
            unitPrice: 12.5,
            recordedAt: timestamp,
            source: source
        )

        XCTAssertTrue(didAppend)
        XCTAssertEqual(
            life.inventoryCounts,
            [
                InventoryCount(
                    id: "shared-update",
                    itemID: item.id,
                    quantity: 4,
                    recordedAt: timestamp,
                    source: source
                )
            ]
        )
        XCTAssertEqual(
            life.inventoryPriceRecords,
            [
                InventoryPriceRecord(
                    id: "shared-update",
                    itemID: item.id,
                    unitPrice: 12.5,
                    purchasedAt: timestamp,
                    createdAt: timestamp,
                    stockIncrease: nil
                )
            ]
        )
    }

    func testAppendInventoryUpdateRejectsInvalidOrArchivedItemsWithoutMutation() {
        let activeItem = HouseholdItem(id: "active", name: "Active")
        let archivedItem = HouseholdItem(
            id: "archived",
            name: "Archived",
            isArchived: true
        )
        let original = LifeData(
            householdItems: [activeItem, archivedItem],
            inventoryCounts: [
                InventoryCount(itemID: activeItem.id, quantity: 1)
            ],
            inventoryPriceRecords: [
                InventoryPriceRecord(
                    itemID: activeItem.id,
                    unitPrice: 5,
                    purchasedAt: Date(timeIntervalSince1970: 100)
                )
            ]
        )
        var life = original

        XCTAssertFalse(
            life.appendInventoryUpdate(
                itemID: activeItem.id,
                quantity: -1,
                unitPrice: 10
            )
        )
        XCTAssertEqual(life, original)
        XCTAssertFalse(
            life.appendInventoryUpdate(
                itemID: activeItem.id,
                quantity: 2,
                unitPrice: 0
            )
        )
        XCTAssertEqual(life, original)
        XCTAssertFalse(
            life.appendInventoryUpdate(
                itemID: "missing",
                quantity: 2,
                unitPrice: 10
            )
        )
        XCTAssertEqual(life, original)
        XCTAssertFalse(
            life.appendInventoryUpdate(
                itemID: archivedItem.id,
                quantity: 2,
                unitPrice: 10
            )
        )
        XCTAssertEqual(life, original)
    }

    func testCorrectLatestInventoryPriceOnlyChangesNewestRecord() {
        let item = HouseholdItem(id: "soap", name: "Soap")
        let oldDate = Date(timeIntervalSince1970: 100)
        let latestDate = Date(timeIntervalSince1970: 200)
        let oldRecord = InventoryPriceRecord(
            id: "old",
            itemID: item.id,
            unitPrice: 10,
            purchasedAt: oldDate,
            createdAt: oldDate
        )
        let latestRecord = InventoryPriceRecord(
            id: "latest",
            itemID: item.id,
            unitPrice: 12,
            purchasedAt: latestDate,
            createdAt: latestDate,
            stockIncrease: 3
        )
        let counts = [
            InventoryCount(
                id: "latest",
                itemID: item.id,
                quantity: 4,
                recordedAt: latestDate
            )
        ]
        var life = LifeData(
            householdItems: [item],
            inventoryCounts: counts,
            inventoryPriceRecords: [latestRecord, oldRecord]
        )

        XCTAssertTrue(
            life.correctLatestInventoryPrice(
                itemID: item.id,
                unitPrice: 11
            )
        )

        XCTAssertEqual(
            life.inventoryPriceRecords.first(where: { $0.id == oldRecord.id }),
            oldRecord
        )
        var correctedLatest = latestRecord
        correctedLatest.unitPrice = 11
        XCTAssertEqual(
            life.inventoryPriceRecords.first(where: { $0.id == latestRecord.id }),
            correctedLatest
        )
        XCTAssertEqual(life.inventoryCounts, counts)
        XCTAssertEqual(
            life.inventoryPriceSummary(for: item.id)?.latest.id,
            latestRecord.id
        )
    }

    func testCorrectLatestInventoryPriceRejectsInvalidMissingAndArchivedState() {
        let activeItem = HouseholdItem(id: "active", name: "Active")
        let archivedItem = HouseholdItem(
            id: "archived",
            name: "Archived",
            isArchived: true
        )
        let activeRecord = InventoryPriceRecord(
            itemID: activeItem.id,
            unitPrice: 10,
            purchasedAt: Date(timeIntervalSince1970: 100)
        )
        let archivedRecord = InventoryPriceRecord(
            itemID: archivedItem.id,
            unitPrice: 20,
            purchasedAt: Date(timeIntervalSince1970: 200)
        )
        let original = LifeData(
            householdItems: [activeItem, archivedItem],
            inventoryPriceRecords: [activeRecord, archivedRecord]
        )
        var life = original

        XCTAssertFalse(
            life.correctLatestInventoryPrice(
                itemID: activeItem.id,
                unitPrice: 0
            )
        )
        XCTAssertEqual(life, original)
        XCTAssertFalse(
            life.correctLatestInventoryPrice(
                itemID: "missing",
                unitPrice: 1
            )
        )
        XCTAssertEqual(life, original)
        XCTAssertFalse(
            life.correctLatestInventoryPrice(
                itemID: archivedItem.id,
                unitPrice: 1
            )
        )
        XCTAssertEqual(life, original)

        var noHistory = LifeData(householdItems: [activeItem])
        XCTAssertFalse(
            noHistory.correctLatestInventoryPrice(
                itemID: activeItem.id,
                unitPrice: 1
            )
        )
        XCTAssertTrue(noHistory.inventoryPriceRecords.isEmpty)
    }
}
