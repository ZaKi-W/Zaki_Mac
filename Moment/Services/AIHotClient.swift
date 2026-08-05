import Foundation

protocol AIHotServing: Sendable {
    func items(query: AIHotItemsQuery) async throws -> AIHotItemsResponse
    func hotTopics() async throws -> AIHotHotTopicsResponse
    func latestDaily() async throws -> AIHotDailyResponse
    func dailies(limit: Int) async throws -> AIHotDailiesResponse
    func daily(date: String) async throws -> AIHotDailyResponse
}

enum AIHotClientError: Error, LocalizedError, Sendable {
    case invalidBaseURL
    case invalidSearch
    case invalidLimit
    case invalidDate
    case invalidResponse
    case notModifiedWithoutCache
    case decodingFailure(String)
    case transport(String)
    case problem(AIHotProblem, retryAfter: TimeInterval?)

    var problem: AIHotProblem? {
        guard case let .problem(problem, _) = self else { return nil }
        return problem
    }

    var retryAfter: TimeInterval? {
        guard case let .problem(_, retryAfter) = self else { return nil }
        return retryAfter
    }

    var isInvalidCursor: Bool {
        problem?.code == "invalid_cursor"
    }

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "AI HOT service address is invalid."
        case .invalidSearch:
            "Search must contain between 2 and 200 characters."
        case .invalidLimit:
            "The requested result limit is invalid."
        case .invalidDate:
            "The daily report date is invalid."
        case .invalidResponse:
            "AI HOT returned an invalid response."
        case .notModifiedWithoutCache:
            "AI HOT returned no changes, but no cached response is available."
        case let .decodingFailure(message):
            "AI HOT data could not be read. \(message)"
        case let .transport(message):
            "AI HOT could not be reached. \(message)"
        case let .problem(problem, _):
            problem.detail ?? problem.title ?? "AI HOT returned an error."
        }
    }
}

actor AIHotClient: AIHotServing {
    static let productionBaseURL = URL(string: "https://aihot.virxact.com")!

    private struct CacheEntry: Sendable {
        let payload: Data
        var etag: String?
        var validatedAt: Date
        var minimumInterval: TimeInterval
    }

    private enum CachePolicy: Sendable {
        case revalidateAfter(TimeInterval)
        case immutable

        var minimumInterval: TimeInterval {
            switch self {
            case let .revalidateAfter(interval):
                interval
            case .immutable:
                .infinity
            }
        }
    }

    private let baseURL: URL
    private let session: URLSession
    private let userAgent: String
    private let now: @Sendable () -> Date
    private var responseCache: [URL: CacheEntry] = [:]

    init(
        baseURL: URL = AIHotClient.productionBaseURL,
        session: URLSession? = nil,
        userAgent: String = "Zaki/1.0 (macOS; AI HOT read-only client)",
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.baseURL = baseURL
        self.session = session ?? URLSession(configuration: .ephemeral)
        self.userAgent = userAgent
        self.now = now
    }

    func items(query: AIHotItemsQuery) async throws -> AIHotItemsResponse {
        let url = try Self.makeItemsURL(baseURL: baseURL, query: query)
        return try await request(url, policy: .revalidateAfter(60))
    }

    func hotTopics() async throws -> AIHotHotTopicsResponse {
        let url = try Self.makeURL(baseURL: baseURL, path: "/api/v1/hot-topics")
        return try await request(url, policy: .revalidateAfter(300))
    }

    func latestDaily() async throws -> AIHotDailyResponse {
        let url = try Self.makeURL(baseURL: baseURL, path: "/api/v1/dailies/latest")
        return try await request(url, policy: .revalidateAfter(3_600))
    }

    func dailies(limit: Int = 30) async throws -> AIHotDailiesResponse {
        guard (1...180).contains(limit) else {
            throw AIHotClientError.invalidLimit
        }
        let url = try Self.makeURL(
            baseURL: baseURL,
            path: "/api/v1/dailies",
            queryItems: [URLQueryItem(name: "limit", value: String(limit))]
        )
        return try await request(url, policy: .revalidateAfter(3_600))
    }

    func daily(date: String) async throws -> AIHotDailyResponse {
        guard Self.isValidDailyDate(date) else {
            throw AIHotClientError.invalidDate
        }
        let url = try Self.makeURL(
            baseURL: baseURL,
            path: "/api/v1/dailies/\(date)"
        )
        return try await request(url, policy: .immutable)
    }

    func clearSessionCache() {
        responseCache.removeAll()
    }

    static func makeItemsURL(
        baseURL: URL = AIHotClient.productionBaseURL,
        query: AIHotItemsQuery
    ) throws -> URL {
        guard (1...100).contains(query.limit) else {
            throw AIHotClientError.invalidLimit
        }

        var queryItems = [
            URLQueryItem(name: "mode", value: query.mode.rawValue),
            URLQueryItem(name: "window", value: query.window.rawValue),
            URLQueryItem(name: "by", value: query.ordering.rawValue),
            URLQueryItem(name: "limit", value: String(query.limit))
        ]

        if let category = query.category {
            queryItems.append(URLQueryItem(name: "category", value: category.rawValue))
        }

        if let search = query.normalizedSearch {
            guard (2...200).contains(search.unicodeScalars.count) else {
                throw AIHotClientError.invalidSearch
            }
            queryItems.append(URLQueryItem(name: "q", value: search))
        }

        if let cursor = query.cursor, !cursor.isEmpty {
            queryItems.append(URLQueryItem(name: "cursor", value: cursor))
        }

        return try makeURL(
            baseURL: baseURL,
            path: "/api/v1/items",
            queryItems: queryItems
        )
    }

    static func makeURL(
        baseURL: URL,
        path: String,
        queryItems: [URLQueryItem] = []
    ) throws -> URL {
        guard
            var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
            let scheme = components.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            components.host != nil
        else {
            throw AIHotClientError.invalidBaseURL
        }

        let basePath = components.path.hasSuffix("/")
            ? String(components.path.dropLast())
            : components.path
        components.path = basePath + path
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else {
            throw AIHotClientError.invalidBaseURL
        }
        return url
    }

    private func request<Response: Decodable & Sendable>(
        _ url: URL,
        policy: CachePolicy
    ) async throws -> Response {
        let requestDate = now()
        if let cached = responseCache[url] {
            let minimumInterval = max(policy.minimumInterval, cached.minimumInterval)
            if requestDate.timeIntervalSince(cached.validatedAt) < minimumInterval {
                return try Self.decode(Response.self, from: cached.payload)
            }
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let etag = responseCache[url]?.etag {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError {
            throw AIHotClientError.transport(error.localizedDescription)
        } catch {
            throw AIHotClientError.transport(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIHotClientError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let decoded = try Self.decode(Response.self, from: data)
            responseCache[url] = CacheEntry(
                payload: data,
                etag: httpResponse.value(forHTTPHeaderField: "ETag"),
                validatedAt: requestDate,
                minimumInterval: max(
                    policy.minimumInterval,
                    Self.sharedCacheMinimumInterval(from: httpResponse) ?? 0
                )
            )
            return decoded

        case 304:
            guard var cached = responseCache[url] else {
                throw AIHotClientError.notModifiedWithoutCache
            }
            cached.validatedAt = requestDate
            cached.etag = httpResponse.value(forHTTPHeaderField: "ETag") ?? cached.etag
            cached.minimumInterval = max(
                policy.minimumInterval,
                Self.sharedCacheMinimumInterval(from: httpResponse) ?? cached.minimumInterval
            )
            responseCache[url] = cached
            return try Self.decode(Response.self, from: cached.payload)

        default:
            let decodedProblem = try? Self.decode(AIHotProblem.self, from: data)
            let problem = AIHotProblem(
                type: decodedProblem?.type,
                title: decodedProblem?.title ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode),
                status: decodedProblem?.status ?? httpResponse.statusCode,
                detail: decodedProblem?.detail,
                code: decodedProblem?.code,
                requestId: decodedProblem?.requestId
                    ?? httpResponse.value(forHTTPHeaderField: "X-Request-Id")
            )
            let retryAfter = [429, 503].contains(httpResponse.statusCode)
                ? Self.retryAfterInterval(from: httpResponse, relativeTo: requestDate)
                : nil
            throw AIHotClientError.problem(problem, retryAfter: retryAfter)
        }
    }

    private static func decode<Response: Decodable>(
        _ type: Response.Type,
        from data: Data
    ) throws -> Response {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = parseISO8601(value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid ISO-8601 date: \(value)"
                )
            }
            return date
        }

        do {
            return try decoder.decode(type, from: data)
        } catch let error as AIHotClientError {
            throw error
        } catch {
            throw AIHotClientError.decodingFailure(error.localizedDescription)
        }
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: value) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private static func isValidDailyDate(_ value: String) -> Bool {
        guard value.count == 10 else { return false }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: value) != nil
    }

    private static func sharedCacheMinimumInterval(
        from response: HTTPURLResponse
    ) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Cache-Control") else {
            return nil
        }

        for directive in value.split(separator: ",") {
            let parts = directive
                .trimmingCharacters(in: .whitespaces)
                .split(separator: "=", maxSplits: 1)
            guard
                parts.count == 2,
                parts[0].lowercased() == "s-maxage",
                let seconds = TimeInterval(
                    parts[1].trimmingCharacters(
                        in: CharacterSet(charactersIn: "\"")
                    )
                ),
                seconds.isFinite
            else {
                continue
            }
            return seconds
        }
        return nil
    }

    private static func retryAfterInterval(
        from response: HTTPURLResponse,
        relativeTo date: Date
    ) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else {
            return nil
        }
        if let seconds = TimeInterval(value.trimmingCharacters(in: .whitespaces)),
           seconds.isFinite {
            return max(0, seconds)
        }

        let formats = [
            "EEE',' dd MMM yyyy HH':'mm':'ss z",
            "EEEE',' dd-MMM-yy HH':'mm':'ss z",
            "EEE MMM d HH':'mm':'ss yyyy"
        ]
        for format in formats {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let retryDate = formatter.date(from: value) {
                return max(0, retryDate.timeIntervalSince(date))
            }
        }
        return nil
    }
}
