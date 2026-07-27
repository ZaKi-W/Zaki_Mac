import Charts
import SwiftUI

struct DashboardWorkspace: View {
    @ObservedObject var model: AppModel

    private var metrics: LifeMetrics {
        model.life.metrics()
    }

    private var financialAllocation: [FinancialAllocationSlice] {
        metrics.financialAllocation.filter { $0.value > 0 }
    }

    private var expenseDueBuckets: [ExpenseDueBucket] {
        metrics.recurringDueBuckets.sorted { $0.index < $1.index }
    }

    private var hasUpcomingExpenses: Bool {
        expenseDueBuckets.contains { $0.amount > 0 }
    }

    private var openTodos: [TodoRecord] {
        model.todos.filter { !$0.isCompleted }
    }

    private var completedTodoCount: Int {
        model.todos.filter(\.isCompleted).count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                inventoryReviewAction

                if model.notificationState == .denied {
                    LifeActionCard(
                        title: model.text("dashboard.notifications.off"),
                        message: model.text("dashboard.notifications.off.body"),
                        systemImage: "bell.slash.fill",
                        tint: .red,
                        buttonTitle: model.text("settings.openSystemSettings")
                    ) {
                        model.openNotificationSettings()
                    }
                }

                LifeSectionHeader(title: model.text("dashboard.overview"))
                primaryMetricsPanel
                healthGauges

                LifeSectionHeader(title: model.text("dashboard.charts"))
                chartGrid

                LifeSectionHeader(title: model.text("dashboard.actions"))
                actionSummaries
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle(model.text("dashboard.title"))
    }

    private var primaryMetricsPanel: some View {
        LifeCard {
            HStack(spacing: 0) {
                primaryMetricButton(
                    title: model.text("dashboard.financial.current"),
                    value: LifeFormat.currency(metrics.financialCurrentValue),
                    systemImage: "banknote.fill",
                    tint: .blue,
                    workspace: .assets
                )

                Divider()
                    .frame(height: 72)

                primaryMetricButton(
                    title: model.text("dashboard.financial.unrealized"),
                    value: LifeFormat.currency(
                        metrics.financialUnrealizedGainLoss
                    ),
                    systemImage: metrics.financialUnrealizedGainLoss >= 0
                        ? "arrow.up.right"
                        : "arrow.down.right",
                    tint: metrics.financialUnrealizedGainLoss >= 0
                        ? .green
                        : .red,
                    workspace: .assets
                )

                Divider()
                    .frame(height: 72)

                primaryMetricButton(
                    title: model.text("dashboard.expenses.monthly"),
                    value: LifeFormat.currency(metrics.recurringMonthlyAmount),
                    systemImage: "repeat",
                    tint: .orange,
                    workspace: .expenses
                )

                Divider()
                    .frame(height: 72)

                primaryMetricButton(
                    title: model.text("dashboard.expenses.next30"),
                    value: LifeFormat.currency(
                        metrics.recurringDueWithin30Days
                    ),
                    systemImage: "calendar.badge.clock",
                    tint: .orange,
                    workspace: .expenses
                )
            }
        }
    }

    private var healthGauges: some View {
        LifeCardGrid(minimumCardWidth: 220) {
            dashboardButton(workspace: .inventory) {
                LifeRingGaugeCard(
                    title: model.text("dashboard.gauge.review"),
                    numerator: metrics.inventoryReviewStatus.reviewedItemCount,
                    denominator: metrics.inventoryReviewStatus.totalItemCount,
                    systemImage: "checklist",
                    tint: .blue
                )
            }

            dashboardButton(workspace: .inventory) {
                LifeRingGaugeCard(
                    title: model.text("dashboard.gauge.inventoryHealth"),
                    numerator: metrics.healthyInventoryItemCount,
                    denominator: metrics.activeInventoryItemCount,
                    systemImage: "shippingbox.and.arrow.backward.fill",
                    tint: .green
                )
            }

            dashboardButton(workspace: .assets) {
                LifeRingGaugeCard(
                    title: model.text("dashboard.gauge.priceFreshness"),
                    numerator: metrics.freshFinancialPriceCount,
                    denominator: metrics.heldFinancialAssetCount,
                    systemImage: "clock.arrow.circlepath",
                    tint: .blue
                )
            }
        }
    }

    private var chartGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(minimum: 300), spacing: 12, alignment: .top),
                GridItem(.flexible(minimum: 300), spacing: 12, alignment: .top)
            ],
            alignment: .leading,
            spacing: 12
        ) {
            dashboardButton(workspace: .assets) {
                financialAllocationChart
            }

            dashboardButton(workspace: .expenses) {
                expenseForecastChart
            }
        }
    }

    private var financialAllocationChart: some View {
        let title = model.text("dashboard.chart.allocation")

        return LifeChartCard(
            title: title,
            systemImage: "chart.pie.fill"
        ) {
            if financialAllocation.isEmpty {
                LifeChartEmptyState(
                    title: model.text("dashboard.chart.allocation.empty"),
                    systemImage: "chart.pie"
                )
            } else {
                Chart {
                    ForEach(financialAllocation, id: \.type) { slice in
                        SectorMark(
                            angle: .value(
                                title,
                                slice.value.lifeDoubleValue
                            ),
                            innerRadius: .ratio(0.62),
                            angularInset: 1.5
                        )
                        .cornerRadius(2)
                        .foregroundStyle(
                            by: .value(
                                model.text("dashboard.chart.assetType"),
                                financialTypeTitle(slice.type)
                            )
                        )
                        .accessibilityLabel(financialTypeTitle(slice.type))
                        .accessibilityValue(
                            LifeFormat.currency(slice.value)
                        )
                    }
                }
                .chartForegroundStyleScale(
                    domain: financialAllocation.map {
                        financialTypeTitle($0.type)
                    },
                    range: allocationColors
                )
                .chartLegend(
                    position: .trailing,
                    alignment: .center,
                    spacing: 8
                )
                .accessibilityLabel(title)
            }
        }
    }

    private var expenseForecastChart: some View {
        let title = model.text("dashboard.chart.expenseForecast")

        return LifeChartCard(
            title: title,
            systemImage: "chart.bar.fill"
        ) {
            if !hasUpcomingExpenses {
                LifeChartEmptyState(
                    title: model.text("dashboard.chart.expenseForecast.empty"),
                    systemImage: "calendar.badge.checkmark"
                )
            } else {
                Chart {
                    ForEach(expenseDueBuckets, id: \.index) { bucket in
                        BarMark(
                            x: .value(
                                model.text("dashboard.chart.period"),
                                bucketLabel(bucket)
                            ),
                            y: .value(
                                model.text("dashboard.chart.amount"),
                                bucket.amount.lifeDoubleValue
                            )
                        )
                        .foregroundStyle(Color.orange)
                        .cornerRadius(3)
                        .accessibilityLabel(bucketAccessibilityLabel(bucket))
                        .accessibilityValue(
                            LifeFormat.currency(bucket.amount)
                        )
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .font(.caption2)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine()
                            .foregroundStyle(Color.secondary.opacity(0.18))
                        AxisValueLabel()
                            .font(.caption2)
                    }
                }
                .accessibilityLabel(title)
            }
        }
    }

    private var actionSummaries: some View {
        LifeCardGrid {
            dashboardButton(workspace: .todos) {
                LifeMetricCard(
                    title: model.text("dashboard.todos"),
                    value: "\(openTodos.count)",
                    detail: todoDetail,
                    systemImage: "checklist",
                    tint: openTodos.isEmpty ? .green : .blue
                )
            }

            dashboardButton(workspace: .inventory) {
                LifeMetricCard(
                    title: model.text("dashboard.inventory"),
                    value: "\(metrics.lowStockItemCount)",
                    detail: "\(metrics.expiringItemCount) \(model.text("dashboard.inventory.expiring"))",
                    systemImage: "shippingbox.fill",
                    tint: metrics.lowStockItemCount > 0 ? .orange : .green
                )
            }

            dashboardButton(workspace: .assets) {
                LifeMetricCard(
                    title: model.text("dashboard.durable"),
                    value: LifeFormat.currency(metrics.durablePurchaseTotal),
                    detail: durableDetail,
                    systemImage: "desktopcomputer",
                    tint: metrics.expiringWarrantyCount > 0 ? .orange : .blue
                )
            }
        }
    }

    private var inventoryReviewAction: some View {
        let status = metrics.inventoryReviewStatus
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
            message = status.scheduledAt.map {
                "\(model.text("dashboard.review.scheduled.body")) \(LifeFormat.date($0))"
            } ?? model.text("dashboard.review.scheduled.body")
            image = "calendar"
            tint = .blue
        case .due:
            title = model.text("dashboard.review.due")
            message = model.text("dashboard.review.due.body")
            image = "calendar.badge.exclamationmark"
            tint = .orange
        case .completed:
            title = model.text("dashboard.review.completed")
            message = status.completedAt.map {
                "\(model.text("dashboard.review.completed.body")) \(LifeFormat.date($0))"
            } ?? model.text("dashboard.review.completed.body")
            image = "checkmark.seal.fill"
            tint = .green
        }

        return LifeActionCard(
            title: title,
            message: message,
            systemImage: image,
            tint: tint,
            buttonTitle: status.isCompleted
                ? model.text("dashboard.review.again")
                : model.text("dashboard.review.start")
        ) {
            model.workspace = .inventory
            model.showingInventoryReview = true
        }
    }

    private var durableDetail: String {
        let daily = LifeFormat.currency(metrics.durableDailyCost)
        return "\(model.text("dashboard.durable.daily")) \(daily) · \(metrics.expiringWarrantyCount) \(model.text("dashboard.durable.warranty"))"
    }

    private var todoDetail: String {
        "\(completedTodoCount) \(model.text("dashboard.todos.completed"))"
    }

    private var allocationColors: [Color] {
        [
            .blue,
            .green,
            .orange,
            .red,
            .blue.opacity(0.55),
            Color.secondary
        ]
    }

    private func primaryMetricButton(
        title: String,
        value: String,
        systemImage: String,
        tint: Color,
        workspace: Workspace
    ) -> some View {
        Button {
            model.workspace = workspace
        } label: {
            LifePrimaryMetric(
                title: title,
                value: value,
                systemImage: systemImage,
                tint: tint
            )
            .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .help(model.text("dashboard.accessibility.open"))
        .accessibilityHint(model.text("dashboard.accessibility.open"))
    }

    private func dashboardButton<Content: View>(
        workspace: Workspace,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button {
            model.workspace = workspace
        } label: {
            content()
        }
        .buttonStyle(.plain)
        .help(model.text("dashboard.accessibility.open"))
        .accessibilityHint(model.text("dashboard.accessibility.open"))
    }

    private func financialTypeTitle(_ type: FinancialAssetType) -> String {
        model.text("assets.type.\(type.rawValue)")
    }

    private func bucketLabel(_ bucket: ExpenseDueBucket) -> String {
        bucket.startDate.formatted(
            .dateTime.month(.twoDigits).day(.twoDigits)
        )
    }

    private func bucketAccessibilityLabel(
        _ bucket: ExpenseDueBucket
    ) -> String {
        "\(LifeFormat.date(bucket.startDate)) – \(LifeFormat.date(bucket.endDate))"
    }
}
