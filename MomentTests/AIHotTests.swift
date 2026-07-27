import Foundation
import XCTest
@testable import Moment

final class AIHotClientTests: XCTestCase {
    override func tearDown() {
        AIHotStubURLProtocol.handler = nil
        super.tearDown()
    }

    func testItemsURLUsesV1QueryAndEncodesSearch() throws {
        let query = AIHotItemsQuery(
            category: .paper,
            window: .last7Days,
            search: "  大模型 + RAG  ",
            limit: 25,
            cursor: "next page"
        )

        let url = try AIHotClient.makeItemsURL(query: query)
        let components = try XCTUnwrap(
            URLComponents(url: url, resolvingAgainstBaseURL: false)
        )
        let values = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map {
                ($0.name, $0.value)
            }
        )

        XCTAssertEqual(components.path, "/api/v1/items")
        XCTAssertEqual(values["mode"]!, "selected")
        XCTAssertEqual(values["window"]!, "7d")
        XCTAssertEqual(values["by"]!, "timeline")
        XCTAssertEqual(values["category"]!, "paper")
        XCTAssertEqual(values["q"]!, "大模型 + RAG")
        XCTAssertEqual(values["limit"]!, "25")
        XCTAssertEqual(values["cursor"]!, "next page")
    }

    func testItemsDecodeUnknownCategoryAndISO8601Variants() async throws {
        AIHotStubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(Self.itemsJSON.utf8))
        }
        let client = AIHotClient(
            baseURL: URL(string: "https://example.test")!,
            session: makeStubSession()
        )

        let response = try await client.items(query: AIHotItemsQuery())
        let item = try XCTUnwrap(response.items.first)

        XCTAssertEqual(item.category?.rawValue, "future-category")
        XCTAssertNotNil(item.publishedAt)
        XCTAssertEqual(
            item.discoveredAt,
            ISO8601DateFormatter().date(from: "2026-07-27T02:00:00Z")
        )
        XCTAssertEqual(item.score, 91.5)
    }

    func testETagIsRevalidatedAnd304UsesSessionCache() async throws {
        let clock = AIHotTestClock(
            Date(timeIntervalSince1970: 1_000)
        )
        var requestCount = 0
        AIHotStubURLProtocol.handler = { request in
            requestCount += 1
            if requestCount == 1 {
                XCTAssertNil(request.value(forHTTPHeaderField: "If-None-Match"))
                let response = HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: [
                        "Content-Type": "application/json",
                        "Cache-Control": "public, s-maxage=60",
                        "ETag": "\"items-v1\""
                    ]
                )!
                return (response, Data(Self.itemsJSON.utf8))
            }

            XCTAssertEqual(
                request.value(forHTTPHeaderField: "If-None-Match"),
                "\"items-v1\""
            )
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 304,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Cache-Control": "public, s-maxage=60",
                    "ETag": "\"items-v1\""
                ]
            )!
            return (response, Data())
        }
        let client = AIHotClient(
            baseURL: URL(string: "https://example.test")!,
            session: makeStubSession(),
            now: { clock.current() }
        )

        let first = try await client.items(query: AIHotItemsQuery())
        clock.advance(by: 61)
        let second = try await client.items(query: AIHotItemsQuery())

        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(second, first)
    }

    func testRetryAfterIsExposedForRateLimitProblem() async throws {
        AIHotStubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 429,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": "application/problem+json",
                    "Retry-After": "45",
                    "X-Request-Id": "request-header"
                ]
            )!
            let problem = """
            {
              "type": "about:blank",
              "title": "Too Many Requests",
              "status": 429,
              "detail": "Please slow down.",
              "code": "rate_limited"
            }
            """
            return (response, Data(problem.utf8))
        }
        let client = AIHotClient(
            baseURL: URL(string: "https://example.test")!,
            session: makeStubSession()
        )

        do {
            _ = try await client.hotTopics()
            XCTFail("Expected a rate-limit error")
        } catch let error as AIHotClientError {
            XCTAssertEqual(error.problem?.status, 429)
            XCTAssertEqual(error.problem?.requestId, "request-header")
            XCTAssertEqual(error.retryAfter, 45)
        }
    }

    func testInvalidBaseURLIsRejectedBeforeRequest() async {
        let client = AIHotClient(
            baseURL: URL(string: "ftp://example.test")!,
            session: makeStubSession()
        )

        do {
            _ = try await client.hotTopics()
            XCTFail("Expected an invalid base URL error")
        } catch let error as AIHotClientError {
            guard case .invalidBaseURL = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeStubSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AIHotStubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static let itemsJSON = """
    {
      "schemaVersion": 1,
      "query": {
        "mode": "selected",
        "category": null,
        "window": "24h",
        "q": null,
        "by": "timeline",
        "ordering": "timelineDesc"
      },
      "items": [
        {
          "id": "item-1",
          "title": "AI HOT test item",
          "originalTitle": null,
          "summary": "A short summary.",
          "source": { "name": "Example Source" },
          "links": {
            "aihot": "https://aihot.virxact.com/items/item-1",
            "original": "https://example.com/item-1"
          },
          "publishedAt": "2026-07-27T01:00:00.123Z",
          "discoveredAt": "2026-07-27T02:00:00Z",
          "category": "future-category",
          "score": 91.5,
          "selected": true,
          "attribution": {
            "name": "AI HOT",
            "url": "https://aihot.virxact.com"
          }
        }
      ],
      "page": {
        "count": 1,
        "hasMore": false,
        "nextCursor": null
      }
    }
    """
}

@MainActor
final class AIHotControllerTests: XCTestCase {
    func testPaginationDeduplicatesAndFilterChangeRestartsFirstPage() async {
        let service = AIHotFakeService()
        let controller = AIHotController(service: service)

        await controller.loadIfNeeded()
        XCTAssertEqual(controller.items.map(\.id), ["first"])
        XCTAssertTrue(controller.canLoadMore)

        await controller.loadMore()
        XCTAssertEqual(controller.items.map(\.id), ["first", "second"])
        XCTAssertFalse(controller.hasMore)

        controller.window = .last7Days
        for _ in 0..<20 {
            await Task.yield()
            if await service.queryCount() >= 3, !controller.isLoading {
                break
            }
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(controller.items.map(\.id), ["week"])
        let queries = await service.queries()
        XCTAssertEqual(queries.last?.window, .last7Days)
        XCTAssertNil(queries.last?.cursor)
    }
}

private actor AIHotFakeService: AIHotServing {
    private var recordedQueries: [AIHotItemsQuery] = []

    func items(query: AIHotItemsQuery) async throws -> AIHotItemsResponse {
        recordedQueries.append(query)

        if query.window == .last7Days {
            return response(items: [item(id: "week")])
        }
        if query.cursor == "next" {
            return response(items: [item(id: "first"), item(id: "second")])
        }
        return response(
            items: [item(id: "first")],
            hasMore: true,
            nextCursor: "next"
        )
    }

    func hotTopics() async throws -> AIHotHotTopicsResponse {
        AIHotHotTopicsResponse(schemaVersion: 1, count: 0, items: [])
    }

    func latestDaily() async throws -> AIHotDailyResponse {
        throw AIHotClientError.invalidResponse
    }

    func dailies(limit: Int) async throws -> AIHotDailiesResponse {
        AIHotDailiesResponse(schemaVersion: 1, count: 0, items: [])
    }

    func daily(date: String) async throws -> AIHotDailyResponse {
        throw AIHotClientError.invalidResponse
    }

    func queries() -> [AIHotItemsQuery] {
        recordedQueries
    }

    func queryCount() -> Int {
        recordedQueries.count
    }

    private func item(id: String) -> AIHotItem {
        AIHotItem(
            id: id,
            title: id,
            originalTitle: nil,
            summary: nil,
            source: AIHotSource(name: "Source"),
            links: AIHotLinks(
                aihot: "https://aihot.virxact.com/items/\(id)",
                original: "https://example.com/\(id)"
            ),
            publishedAt: nil,
            discoveredAt: Date(timeIntervalSince1970: 1_000),
            category: nil,
            score: nil,
            selected: true,
            attribution: nil
        )
    }

    private func response(
        items: [AIHotItem],
        hasMore: Bool = false,
        nextCursor: String? = nil
    ) -> AIHotItemsResponse {
        AIHotItemsResponse(
            schemaVersion: 1,
            items: items,
            page: AIHotPage(
                count: items.count,
                hasMore: hasMore,
                nextCursor: nextCursor
            )
        )
    }
}

private final class AIHotStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler:
        ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(
                self,
                didFailWithError: URLError(.resourceUnavailable)
            )
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class AIHotTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) {
        self.value = value
    }

    func current() -> Date {
        lock.withLock { value }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock {
            value = value.addingTimeInterval(interval)
        }
    }
}
