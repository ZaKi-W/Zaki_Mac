import SwiftUI

struct AIHotWorkspace: View {
    @ObservedObject var model: AppModel
    @ObservedObject var controller: AIHotController

    var body: some View {
        VStack(spacing: 0) {
            channelPicker
            Divider()

            Group {
                switch controller.channel {
                case .selected:
                    AIHotSelectedView(model: model, controller: controller)
                case .hotTopics:
                    AIHotTopicsView(model: model, controller: controller)
                case .daily:
                    AIHotDailyView(model: model, controller: controller)
                }
            }
        }
        .navigationTitle(model.text("sidebar.aiHot"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        await controller.refresh()
                    }
                } label: {
                    if controller.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label(
                            model.text("aihot.refresh"),
                            systemImage: "arrow.clockwise"
                        )
                    }
                }
                .disabled(!controller.canRefresh)
                .help(
                    model.text(
                        controller.canRefresh
                            ? "aihot.refresh"
                            : "aihot.refresh.wait"
                    )
                )
            }
        }
        .task {
            await controller.loadIfNeeded()
        }
        .environment(\.locale, model.locale)
    }

    private var channelPicker: some View {
        Picker(model.text("aihot.channel.label"), selection: $controller.channel) {
            Text(model.text("aihot.channel.selected"))
                .tag(AIHotChannel.selected)
            Text(model.text("aihot.channel.hotTopics"))
                .tag(AIHotChannel.hotTopics)
            Text(model.text("aihot.channel.daily"))
                .tag(AIHotChannel.daily)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 440)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}

private struct AIHotSelectedView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var controller: AIHotController

    private var normalizedSearch: String {
        controller.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            filters
            Divider()

            if controller.items.isEmpty && controller.isLoading {
                AIHotLoadingState(model: model)
            } else if controller.items.isEmpty, let error = controller.errorMessage {
                AIHotErrorState(
                    model: model,
                    message: error,
                    retryAllowedAt: controller.retryAllowedAt,
                    canRetry: controller.canRefresh,
                    retry: retry,
                    dismiss: controller.clearError
                )
            } else if controller.items.isEmpty {
                AIHotEmptyState(
                    model: model,
                    titleKey: "aihot.empty.selected.title",
                    bodyKey: "aihot.empty.selected.body",
                    systemImage: "newspaper"
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if let error = controller.errorMessage {
                            AIHotErrorBanner(
                                model: model,
                                message: error,
                                retryAllowedAt: controller.retryAllowedAt,
                                canRetry: controller.canRefresh,
                                retry: retry,
                                dismiss: controller.clearError
                            )
                        }

                        LifeSectionHeader(
                            title: model.text("aihot.selected.title"),
                            detail: controller.items.count.formatted()
                        )

                        ForEach(controller.items) { item in
                            AIHotItemCard(
                                model: model,
                                item: item,
                                open: openInBrowser
                            )
                        }

                        if controller.hasMore {
                            HStack {
                                Spacer()
                                Button {
                                    Task {
                                        await controller.loadMore()
                                    }
                                } label: {
                                    if controller.isLoadingMore {
                                        HStack(spacing: 7) {
                                            ProgressView()
                                                .controlSize(.small)
                                            Text(model.text("aihot.loadingMore"))
                                        }
                                    } else {
                                        Text(model.text("aihot.loadMore"))
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(!controller.canLoadMore)
                                Spacer()
                            }
                            .padding(.vertical, 6)
                        }
                    }
                    .padding(20)
                }
                .refreshable {
                    await controller.refresh()
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Picker(
                    model.text("aihot.filters.window"),
                    selection: $controller.window
                ) {
                    Text(model.text("aihot.window.24h"))
                        .tag(AIHotWindow.last24Hours)
                    Text(model.text("aihot.window.7d"))
                        .tag(AIHotWindow.last7Days)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 160)

                Picker(
                    model.text("aihot.filters.category"),
                    selection: $controller.category
                ) {
                    Text(model.text("aihot.category.all"))
                        .tag(nil as AIHotCategory?)
                    ForEach(AIHotCategory.knownCases) { category in
                        Text(categoryLabel(category))
                            .tag(Optional(category))
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 150)

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(
                        model.text("aihot.search.placeholder"),
                        text: $controller.searchText
                    )
                    .textFieldStyle(.plain)

                    if !controller.searchText.isEmpty {
                        Button {
                            controller.searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help(model.text("aihot.search.clear"))
                    }
                }
                .padding(.horizontal, 9)
                .frame(minWidth: 190, maxWidth: 340)
                .frame(height: 28)
                .background(
                    Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            Color(nsColor: .separatorColor).opacity(0.7),
                            lineWidth: 0.5
                        )
                }
            }

            if !normalizedSearch.isEmpty
                && normalizedSearch.unicodeScalars.count < 2 {
                Label(
                    model.text("aihot.search.minimum"),
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private func categoryLabel(_ category: AIHotCategory) -> String {
        let known = Set(AIHotCategory.knownCases.map(\.rawValue))
        guard known.contains(category.rawValue) else {
            return category.rawValue
        }
        return model.text("aihot.category.\(category.rawValue)")
    }

    private func openInBrowser(_ url: URL?) {
        guard let url, url.isAIHotWebURL else { return }
        model.browser.createTab(url: url)
        model.workspace = .browser
    }

    private func retry() {
        Task {
            await controller.refresh()
        }
    }
}

private struct AIHotTopicsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var controller: AIHotController

    var body: some View {
        Group {
            if controller.hotTopics.isEmpty && controller.isLoading {
                AIHotLoadingState(model: model)
            } else if controller.hotTopics.isEmpty, let error = controller.errorMessage {
                AIHotErrorState(
                    model: model,
                    message: error,
                    retryAllowedAt: controller.retryAllowedAt,
                    canRetry: controller.canRefresh,
                    retry: retry,
                    dismiss: controller.clearError
                )
            } else if controller.hotTopics.isEmpty {
                AIHotEmptyState(
                    model: model,
                    titleKey: "aihot.empty.hotTopics.title",
                    bodyKey: "aihot.empty.hotTopics.body",
                    systemImage: "flame"
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if let error = controller.errorMessage {
                            AIHotErrorBanner(
                                model: model,
                                message: error,
                                retryAllowedAt: controller.retryAllowedAt,
                                canRetry: controller.canRefresh,
                                retry: retry,
                                dismiss: controller.clearError
                            )
                        }

                        LifeSectionHeader(
                            title: model.text("aihot.hotTopics.title"),
                            detail: controller.hotTopics.count.formatted()
                        )

                        ForEach(
                            Array(controller.hotTopics.enumerated()),
                            id: \.element.id
                        ) { index, topic in
                            AIHotTopicCard(
                                model: model,
                                topic: topic,
                                rank: index + 1,
                                open: openInBrowser
                            )
                        }

                        AIHotAttributionView(
                            model: model,
                            attribution: nil,
                            open: openInBrowser
                        )
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 4)
                    }
                    .padding(20)
                }
                .refreshable {
                    await controller.refresh()
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func openInBrowser(_ url: URL?) {
        guard let url, url.isAIHotWebURL else { return }
        model.browser.createTab(url: url)
        model.workspace = .browser
    }

    private func retry() {
        Task {
            await controller.refresh()
        }
    }
}

private struct AIHotDailyView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var controller: AIHotController

    var body: some View {
        Group {
            if controller.dailyReport == nil && controller.isLoading {
                AIHotLoadingState(model: model)
            } else if controller.dailyReport == nil, let error = controller.errorMessage {
                AIHotErrorState(
                    model: model,
                    message: error,
                    retryAllowedAt: controller.retryAllowedAt,
                    canRetry: controller.canRefresh,
                    retry: retry,
                    dismiss: controller.clearError
                )
            } else if let report = controller.dailyReport {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if let error = controller.errorMessage {
                            AIHotErrorBanner(
                                model: model,
                                message: error,
                                retryAllowedAt: controller.retryAllowedAt,
                                canRetry: controller.canRefresh,
                                retry: retry,
                                dismiss: controller.clearError
                            )
                        }

                        dailyHeader(report)

                        if let lead = report.lead {
                            LifeCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    Label(
                                        model.text("aihot.daily.lead"),
                                        systemImage: "sparkles"
                                    )
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.accentColor)

                                    Text(lead.title)
                                        .font(.title2.weight(.semibold))
                                        .textSelection(.enabled)

                                    Text(lead.leadParagraph)
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                        .lineSpacing(3)
                                        .textSelection(.enabled)
                                }
                            }
                        }

                        ForEach(report.sections) { section in
                            VStack(alignment: .leading, spacing: 10) {
                                LifeSectionHeader(
                                    title: section.label,
                                    detail: section.items.count.formatted()
                                )

                                ForEach(section.items) { item in
                                    AIHotDailyStoryCard(
                                        model: model,
                                        item: item,
                                        open: openInBrowser
                                    )
                                }
                            }
                        }

                        if !report.flashes.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                LifeSectionHeader(
                                    title: model.text("aihot.daily.flashes"),
                                    detail: report.flashes.count.formatted(),
                                    systemImage: "bolt"
                                )

                                LifeCard {
                                    VStack(alignment: .leading, spacing: 0) {
                                        ForEach(
                                            Array(report.flashes.enumerated()),
                                            id: \.element.id
                                        ) { index, flash in
                                            if index > 0 {
                                                Divider()
                                            }
                                            AIHotDailyFlashRow(
                                                model: model,
                                                flash: flash,
                                                open: openInBrowser
                                            )
                                            .padding(.vertical, 10)
                                        }
                                    }
                                }
                            }
                        }

                        AIHotAttributionView(
                            model: model,
                            attribution: report.attribution,
                            open: openInBrowser
                        )
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 4)
                    }
                    .padding(20)
                }
                .refreshable {
                    await controller.refresh()
                }
            } else {
                AIHotEmptyState(
                    model: model,
                    titleKey: "aihot.empty.daily.title",
                    bodyKey: "aihot.empty.daily.body",
                    systemImage: "doc.text"
                )
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func dailyHeader(_ report: AIHotDailyReport) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.text("aihot.daily.title"))
                    .font(.title2.weight(.semibold))
                HStack(spacing: 8) {
                    Text(report.date)
                        .font(.callout.weight(.medium))
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(model.text("aihot.daily.generated"))
                        .foregroundStyle(.secondary)
                    Text(
                        report.generatedAt.formatted(
                            .dateTime
                                .hour()
                                .minute()
                                .locale(model.locale)
                        )
                    )
                    .foregroundStyle(.secondary)
                }
                .font(.caption)
            }

            Spacer()

            if let canonical = report.links.aihotURL {
                Button {
                    openInBrowser(canonical)
                } label: {
                    Label(
                        model.text("aihot.open.aihot"),
                        systemImage: "safari"
                    )
                }
                .buttonStyle(.bordered)
            }

            Menu {
                if controller.dailyEntries.isEmpty {
                    Text(model.text("aihot.daily.archive.empty"))
                } else {
                    ForEach(controller.dailyEntries.prefix(30)) { entry in
                        Button {
                            Task {
                                await controller.selectDaily(date: entry.date)
                            }
                        } label: {
                            HStack {
                                Text(entry.date)
                                if controller.selectedDailyDate == entry.date {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                Label(
                    model.text("aihot.daily.archive"),
                    systemImage: "calendar"
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private func openInBrowser(_ url: URL?) {
        guard let url, url.isAIHotWebURL else { return }
        model.browser.createTab(url: url)
        model.workspace = .browser
    }

    private func retry() {
        Task {
            await controller.refresh()
        }
    }
}

private struct AIHotItemCard: View {
    @ObservedObject var model: AppModel
    let item: AIHotItem
    let open: (URL?) -> Void

    var body: some View {
        LifeCard {
            VStack(alignment: .leading, spacing: 11) {
                Button {
                    open(item.links.preferredURL)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.title)
                            .font(.headline)
                            .multilineTextAlignment(.leading)
                            .textSelection(.enabled)
                        Image(systemName: "arrow.up.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(item.links.preferredURL == nil)

                if let summary = item.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                        .textSelection(.enabled)
                }

                HStack(spacing: 12) {
                    Label(item.source.name, systemImage: "dot.radiowaves.left.and.right")

                    if let publishedAt = item.publishedAt {
                        Label(
                            publishedAt.formatted(
                                .dateTime
                                    .month(.abbreviated)
                                    .day()
                                    .hour()
                                    .minute()
                                    .locale(model.locale)
                            ),
                            systemImage: "clock"
                        )
                    }

                    if let category = item.category {
                        Label(
                            categoryLabel(category),
                            systemImage: "tag"
                        )
                    }

                    if let score = item.score {
                        Label(
                            "\(model.text("aihot.score")) \(score.formatted(.number.precision(.fractionLength(0...1))))",
                            systemImage: "sparkles"
                        )
                    }

                    Spacer(minLength: 4)

                    if item.links.originalURL != nil {
                        Button {
                            open(item.links.originalURL)
                        } label: {
                            Label(
                                model.text("aihot.original"),
                                systemImage: "arrow.up.right.square"
                            )
                        }
                        .buttonStyle(.link)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Divider()

                AIHotAttributionView(
                    model: model,
                    attribution: item.attribution,
                    open: open
                )
            }
        }
    }

    private func categoryLabel(_ category: AIHotCategory) -> String {
        let known = Set(AIHotCategory.knownCases.map(\.rawValue))
        guard known.contains(category.rawValue) else {
            return category.rawValue
        }
        return model.text("aihot.category.\(category.rawValue)")
    }
}

private struct AIHotTopicCard: View {
    @ObservedObject var model: AppModel
    let topic: AIHotHotTopic
    let rank: Int
    let open: (URL?) -> Void

    var body: some View {
        LifeCard {
            HStack(alignment: .top, spacing: 14) {
                Text(rank, format: .number)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(rank <= 3 ? Color.orange : Color.secondary)
                    .frame(width: 30, height: 30)
                    .background(
                        (rank <= 3 ? Color.orange : Color.secondary).opacity(0.1),
                        in: Circle()
                    )

                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        open(topic.links.preferredURL)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(topic.title)
                                .font(.headline)
                                .multilineTextAlignment(.leading)
                                .textSelection(.enabled)
                            Image(systemName: "arrow.up.right")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(topic.links.preferredURL == nil)

                    HStack(spacing: 12) {
                        Label(
                            "\(model.text("aihot.hot.sourceCount")) \(topic.sourceCount)",
                            systemImage: "person.2"
                        )
                        Label(
                            topic.latestAt.formatted(
                                .dateTime
                                    .month(.abbreviated)
                                    .day()
                                    .hour()
                                    .minute()
                                    .locale(model.locale)
                            ),
                            systemImage: "clock"
                        )
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if !topic.sourceNames.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.text("aihot.hot.sources"))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Text(topic.sourceNames.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }

                    HStack {
                        Spacer()
                        if topic.links.originalURL != nil {
                            Button {
                                open(topic.links.originalURL)
                            } label: {
                                Label(
                                    model.text("aihot.original"),
                                    systemImage: "arrow.up.right.square"
                                )
                            }
                            .buttonStyle(.link)
                        }
                    }
                    .font(.caption)

                    Divider()

                    AIHotAttributionView(
                        model: model,
                        attribution: nil,
                        open: open
                    )
                }
            }
        }
    }
}

private struct AIHotDailyStoryCard: View {
    @ObservedObject var model: AppModel
    let item: AIHotDailySectionItem
    let open: (URL?) -> Void

    var body: some View {
        LifeCard {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    open(item.links.preferredURL)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.title)
                            .font(.headline)
                            .multilineTextAlignment(.leading)
                            .textSelection(.enabled)
                        Image(systemName: "arrow.up.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(item.links.preferredURL == nil)

                Text(item.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .textSelection(.enabled)

                HStack {
                    Label(item.source.name, systemImage: "dot.radiowaves.left.and.right")
                    Spacer()
                    if item.links.originalURL != nil {
                        Button {
                            open(item.links.originalURL)
                        } label: {
                            Label(
                                model.text("aihot.original"),
                                systemImage: "arrow.up.right.square"
                            )
                        }
                        .buttonStyle(.link)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Divider()

                AIHotAttributionView(
                    model: model,
                    attribution: item.attribution,
                    open: open
                )
            }
        }
    }
}

private struct AIHotDailyFlashRow: View {
    @ObservedObject var model: AppModel
    let flash: AIHotDailyFlash
    let open: (URL?) -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "bolt.fill")
                .font(.caption)
                .foregroundStyle(.orange)

            Button {
                open(flash.links.preferredURL)
            } label: {
                Text(flash.title)
                    .font(.callout.weight(.medium))
                    .multilineTextAlignment(.leading)
                    .textSelection(.enabled)
            }
            .buttonStyle(.plain)
            .disabled(flash.links.preferredURL == nil)

            Spacer(minLength: 10)

            Text(flash.source.name)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(
                flash.publishedAt.formatted(
                    .dateTime
                        .hour()
                        .minute()
                        .locale(model.locale)
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            if flash.links.originalURL != nil {
                Button {
                    open(flash.links.originalURL)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(model.text("aihot.original"))
            }
        }
    }
}

private struct AIHotAttributionView: View {
    @ObservedObject var model: AppModel
    let attribution: AIHotAttribution?
    let open: (URL?) -> Void

    var body: some View {
        Button {
            open(attribution?.publicURL)
        } label: {
            Label(
                attribution?.name ?? model.text("aihot.attribution.default"),
                systemImage: "checkmark.seal"
            )
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundStyle(.tertiary)
        .disabled(attribution?.publicURL == nil)
    }
}

private struct AIHotLoadingState: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            Text(model.text("aihot.loading"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct AIHotEmptyState: View {
    @ObservedObject var model: AppModel
    let titleKey: String
    let bodyKey: String
    let systemImage: String

    var body: some View {
        ContentUnavailableView {
            Label(model.text(titleKey), systemImage: systemImage)
        } description: {
            Text(model.text(bodyKey))
        }
    }
}

private struct AIHotErrorState: View {
    @ObservedObject var model: AppModel
    let message: String
    let retryAllowedAt: Date?
    let canRetry: Bool
    let retry: () -> Void
    let dismiss: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(
                model.text("aihot.error.title"),
                systemImage: "wifi.exclamationmark"
            )
        } description: {
            VStack(spacing: 6) {
                Text(message)
                if let retryAllowedAt, retryAllowedAt > .now {
                    Text(retryWaitText(retryAllowedAt))
                        .font(.caption)
                }
            }
        } actions: {
            Button(model.text("aihot.retry"), action: retry)
                .buttonStyle(.borderedProminent)
                .disabled(!canRetry)
            Button(model.text("aihot.dismiss"), action: dismiss)
                .buttonStyle(.bordered)
        }
    }

    private func retryWaitText(_ date: Date) -> String {
        let relative = date.formatted(
            .relative(presentation: .named).locale(model.locale)
        )
        return "\(model.text("aihot.refresh.available")) \(relative)"
    }
}

private struct AIHotErrorBanner: View {
    @ObservedObject var model: AppModel
    let message: String
    let retryAllowedAt: Date?
    let canRetry: Bool
    let retry: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 3) {
                Text(model.text("aihot.error.cached"))
                    .font(.callout.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let retryAllowedAt, retryAllowedAt > .now {
                    Text(retryWaitText(retryAllowedAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            Button(model.text("aihot.retry"), action: retry)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!canRetry)

            Button(action: dismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help(model.text("aihot.dismiss"))
        }
        .padding(12)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(Color.orange.opacity(0.25), lineWidth: 0.5)
        }
    }

    private func retryWaitText(_ date: Date) -> String {
        let relative = date.formatted(
            .relative(presentation: .named).locale(model.locale)
        )
        return "\(model.text("aihot.refresh.available")) \(relative)"
    }
}

private extension URL {
    var isAIHotWebURL: Bool {
        guard let scheme = scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && host != nil
    }
}
