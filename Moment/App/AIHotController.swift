import Combine
import Foundation

@MainActor
final class AIHotController: ObservableObject {
    @Published var channel: AIHotChannel = .selected {
        didSet {
            guard channel != oldValue else { return }
            channelDidChange()
        }
    }

    @Published var window: AIHotWindow = .last24Hours {
        didSet {
            guard window != oldValue else { return }
            selectedFilterDidChange()
        }
    }

    /// `nil` means all categories.
    @Published var category: AIHotCategory? {
        didSet {
            guard category != oldValue else { return }
            selectedFilterDidChange()
        }
    }

    @Published var searchText = "" {
        didSet {
            guard searchText != oldValue else { return }
            searchDidChange()
        }
    }

    /// `nil` selects the latest report.
    @Published var selectedDailyDate: String? {
        didSet {
            guard selectedDailyDate != oldValue, channel == .daily else { return }
            cancelSearchAndLoad()
            _ = startDailyLoad(forceArchiveRefresh: false)
        }
    }

    @Published private(set) var items: [AIHotItem] = []
    @Published private(set) var hotTopics: [AIHotHotTopic] = []
    @Published private(set) var dailyReport: AIHotDailyReport?
    @Published private(set) var dailyEntries: [AIHotDailyEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var retryAllowedAt: Date?
    @Published private(set) var hasMore = false

    var canLoadMore: Bool {
        channel == .selected
            && hasMore
            && nextCursor != nil
            && !isLoading
            && !isLoadingMore
            && !isRetryBlocked
    }

    var canRefresh: Bool {
        !isLoading && !isLoadingMore && !isRetryBlocked
    }

    var isSearchTooShort: Bool {
        let search = normalizedSearch
        return !search.isEmpty && search.unicodeScalars.count < 2
    }

    private var isRetryBlocked: Bool {
        guard let retryAllowedAt else { return false }
        return retryAllowedAt > Date()
    }

    private let service: any AIHotServing
    private var nextCursor: String?
    private var loadedChannels: Set<AIHotChannel> = []
    private var loadedDailyDates: Set<String> = []
    private var loadGeneration = 0
    private var loadTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var retryReleaseTask: Task<Void, Never>?

    init(service: any AIHotServing = AIHotClient()) {
        self.service = service
    }

    func loadIfNeeded() async {
        let task: Task<Void, Never>?
        switch channel {
        case .selected, .hotTopics:
            guard !loadedChannels.contains(channel) else { return }
            task = startCurrentChannelLoad(force: false)
        case .daily:
            let key = selectedDailyDate ?? "latest"
            guard !loadedDailyDates.contains(key) || dailyEntries.isEmpty else { return }
            task = startDailyLoad(forceArchiveRefresh: dailyEntries.isEmpty)
        }
        await task?.value
    }

    func refresh() async {
        guard canRefresh else { return }
        await startCurrentChannelLoad(force: true)?.value
    }

    func loadMore() async {
        guard canLoadMore, let nextCursor else { return }
        await startItemsLoad(cursor: nextCursor, appending: true)?.value
    }

    func selectDaily(date: String) async {
        if selectedDailyDate == date {
            if !loadedDailyDates.contains(date) {
                await startDailyLoad(forceArchiveRefresh: false)?.value
            }
            return
        }
        selectedDailyDate = date
        await loadTask?.value
    }

    func selectLatestDaily() async {
        if selectedDailyDate == nil {
            if !loadedDailyDates.contains("latest") {
                await startDailyLoad(forceArchiveRefresh: false)?.value
            }
            return
        }
        selectedDailyDate = nil
        await loadTask?.value
    }

    func clearError() {
        errorMessage = nil
    }

    private var normalizedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func channelDidChange() {
        cancelSearchAndLoad()
        _ = startCurrentChannelLoad(force: false)
    }

    private func selectedFilterDidChange() {
        nextCursor = nil
        hasMore = false
        guard channel == .selected else { return }
        cancelSearchAndLoad()
        if !isSearchTooShort {
            _ = startItemsLoad(cursor: nil, appending: false)
        }
    }

    private func searchDidChange() {
        nextCursor = nil
        hasMore = false
        guard channel == .selected else { return }
        cancelSearchAndLoad()

        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self, !self.isSearchTooShort else { return }
            await self.startItemsLoad(cursor: nil, appending: false)?.value
        }
    }

    private func cancelSearchAndLoad() {
        searchTask?.cancel()
        searchTask = nil
        loadTask?.cancel()
        loadTask = nil
        loadGeneration += 1
        isLoading = false
        isLoadingMore = false
    }

    private func startCurrentChannelLoad(force: Bool) -> Task<Void, Never>? {
        guard !isRetryBlocked else { return nil }

        switch channel {
        case .selected:
            return startItemsLoad(cursor: nil, appending: false)
        case .hotTopics:
            return startHotTopicsLoad()
        case .daily:
            return startDailyLoad(forceArchiveRefresh: force)
        }
    }

    private func startItemsLoad(
        cursor: String?,
        appending: Bool
    ) -> Task<Void, Never>? {
        guard !isRetryBlocked else { return nil }
        loadTask?.cancel()
        loadGeneration += 1
        let generation = loadGeneration
        let query = AIHotItemsQuery(
            mode: .selected,
            category: category,
            window: window,
            ordering: .timeline,
            search: normalizedSearch.isEmpty ? nil : normalizedSearch,
            limit: 50,
            cursor: cursor
        )

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performItemsLoad(
                query: query,
                appending: appending,
                generation: generation
            )
        }
        loadTask = task
        return task
    }

    private func performItemsLoad(
        query: AIHotItemsQuery,
        appending: Bool,
        generation: Int
    ) async {
        setLoading(true, appending: appending, generation: generation)
        defer { setLoading(false, appending: appending, generation: generation) }

        do {
            let response = try await service.items(query: query)
            try Task.checkCancellation()
            guard generation == loadGeneration else { return }
            applyItems(response, appending: appending)
            loadedChannels.insert(.selected)
            clearRequestError()
        } catch is CancellationError {
            return
        } catch let error as AIHotClientError where appending && error.isInvalidCursor {
            await recoverFromInvalidCursor(query: query, generation: generation)
        } catch {
            handle(error, generation: generation)
        }
    }

    private func recoverFromInvalidCursor(
        query: AIHotItemsQuery,
        generation: Int
    ) async {
        do {
            let response = try await service.items(query: query.replacingCursor(nil))
            try Task.checkCancellation()
            guard generation == loadGeneration else { return }
            applyItems(response, appending: false)
            loadedChannels.insert(.selected)
            clearRequestError()
        } catch is CancellationError {
            return
        } catch {
            handle(error, generation: generation)
        }
    }

    private func applyItems(_ response: AIHotItemsResponse, appending: Bool) {
        if appending {
            var seen = Set(items.map(\.id))
            let newItems = response.items.filter { seen.insert($0.id).inserted }
            items.append(contentsOf: newItems)
        } else {
            var seen = Set<String>()
            items = response.items.filter { seen.insert($0.id).inserted }
        }
        nextCursor = response.page.nextCursor
        hasMore = response.page.hasMore && response.page.nextCursor != nil
    }

    private func startHotTopicsLoad() -> Task<Void, Never>? {
        guard !isRetryBlocked else { return nil }
        loadTask?.cancel()
        loadGeneration += 1
        let generation = loadGeneration

        let task = Task { [weak self] in
            guard let self else { return }
            self.setLoading(true, appending: false, generation: generation)
            defer { self.setLoading(false, appending: false, generation: generation) }

            do {
                let response = try await self.service.hotTopics()
                try Task.checkCancellation()
                guard generation == self.loadGeneration else { return }
                self.hotTopics = response.items
                self.loadedChannels.insert(.hotTopics)
                self.clearRequestError()
            } catch is CancellationError {
                return
            } catch {
                self.handle(error, generation: generation)
            }
        }
        loadTask = task
        return task
    }

    private func startDailyLoad(
        forceArchiveRefresh: Bool
    ) -> Task<Void, Never>? {
        guard !isRetryBlocked else { return nil }
        loadTask?.cancel()
        loadGeneration += 1
        let generation = loadGeneration
        let date = selectedDailyDate

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performDailyLoad(
                date: date,
                forceArchiveRefresh: forceArchiveRefresh,
                generation: generation
            )
        }
        loadTask = task
        return task
    }

    private func performDailyLoad(
        date: String?,
        forceArchiveRefresh: Bool,
        generation: Int
    ) async {
        setLoading(true, appending: false, generation: generation)
        defer { setLoading(false, appending: false, generation: generation) }

        var firstError: Error?
        do {
            let response = if let date {
                try await service.daily(date: date)
            } else {
                try await service.latestDaily()
            }
            try Task.checkCancellation()
            guard generation == loadGeneration else { return }
            dailyReport = response.report
            loadedDailyDates.insert(date ?? "latest")
        } catch is CancellationError {
            return
        } catch {
            firstError = error
            if let clientError = error as? AIHotClientError,
               clientError.retryAfter != nil {
                handle(error, generation: generation)
                return
            }
        }

        if forceArchiveRefresh || dailyEntries.isEmpty {
            do {
                let response = try await service.dailies(limit: 30)
                try Task.checkCancellation()
                guard generation == loadGeneration else { return }
                dailyEntries = response.items
            } catch is CancellationError {
                return
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }

        guard generation == loadGeneration else { return }
        if let firstError {
            handle(firstError, generation: generation)
        } else {
            loadedChannels.insert(.daily)
            clearRequestError()
        }
    }

    private func setLoading(
        _ loading: Bool,
        appending: Bool,
        generation: Int
    ) {
        guard generation == loadGeneration else { return }
        if appending {
            isLoadingMore = loading
        } else {
            isLoading = loading
        }
        if loading {
            errorMessage = nil
        }
    }

    private func handle(_ error: Error, generation: Int) {
        guard generation == loadGeneration else { return }
        if let clientError = error as? AIHotClientError {
            errorMessage = clientError.localizedDescription
            if let retryAfter = clientError.retryAfter {
                let releaseAt = Date().addingTimeInterval(retryAfter)
                retryAllowedAt = releaseAt
                retryReleaseTask?.cancel()
                retryReleaseTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(retryAfter))
                    guard !Task.isCancelled, let self else { return }
                    if self.retryAllowedAt == releaseAt {
                        self.retryAllowedAt = nil
                    }
                }
            }
        } else {
            errorMessage = error.localizedDescription
        }
    }

    private func clearRequestError() {
        errorMessage = nil
        retryAllowedAt = nil
        retryReleaseTask?.cancel()
        retryReleaseTask = nil
    }
}
