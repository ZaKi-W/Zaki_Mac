import Foundation

enum AIHotChannel: String, CaseIterable, Identifiable, Sendable {
    case selected
    case hotTopics
    case daily

    var id: Self { self }
}

enum AIHotWindow: String, CaseIterable, Identifiable, Codable, Sendable {
    case last24Hours = "24h"
    case last7Days = "7d"

    var id: Self { self }
}

enum AIHotItemsMode: String, Codable, Sendable {
    case selected
    case all
}

enum AIHotOrdering: String, Codable, Sendable {
    case timeline
    case published
}

/// A forward-compatible category value. The API may add values without an app update.
struct AIHotCategory: RawRepresentable, Codable, Hashable, Identifiable, Sendable {
    let rawValue: String

    var id: String { rawValue }

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static let aiModels = AIHotCategory(rawValue: "ai-models")
    static let aiProducts = AIHotCategory(rawValue: "ai-products")
    static let industry = AIHotCategory(rawValue: "industry")
    static let paper = AIHotCategory(rawValue: "paper")
    static let tip = AIHotCategory(rawValue: "tip")

    static let knownCases: [AIHotCategory] = [
        .aiModels,
        .aiProducts,
        .industry,
        .paper,
        .tip
    ]
}

struct AIHotItemsQuery: Equatable, Sendable {
    var mode: AIHotItemsMode
    var category: AIHotCategory?
    var window: AIHotWindow
    var ordering: AIHotOrdering
    var search: String?
    var limit: Int
    var cursor: String?

    init(
        mode: AIHotItemsMode = .selected,
        category: AIHotCategory? = nil,
        window: AIHotWindow = .last24Hours,
        ordering: AIHotOrdering = .timeline,
        search: String? = nil,
        limit: Int = 50,
        cursor: String? = nil
    ) {
        self.mode = mode
        self.category = category
        self.window = window
        self.ordering = ordering
        self.search = search
        self.limit = limit
        self.cursor = cursor
    }

    var normalizedSearch: String? {
        guard let search else { return nil }
        let value = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    func replacingCursor(_ cursor: String?) -> AIHotItemsQuery {
        var copy = self
        copy.cursor = cursor
        return copy
    }
}

struct AIHotSource: Decodable, Equatable, Sendable {
    let name: String
}

struct AIHotLinks: Decodable, Equatable, Sendable {
    /// Kept as a String at the decoding boundary so one malformed link cannot reject a response.
    let aihot: String
    let original: String

    var aihotURL: URL? { AIHotURLValidator.webURL(from: aihot) }
    var originalURL: URL? { AIHotURLValidator.webURL(from: original) }
    var preferredURL: URL? { aihotURL }
}

struct AIHotAttribution: Decodable, Equatable, Sendable {
    let name: String
    /// Kept as a String at the decoding boundary and validated before use.
    let url: String

    var publicURL: URL? { AIHotURLValidator.webURL(from: url) }
}

struct AIHotItem: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let originalTitle: String?
    let summary: String?
    let source: AIHotSource
    let links: AIHotLinks
    let publishedAt: Date?
    let discoveredAt: Date
    let category: AIHotCategory?
    let score: Double?
    let selected: Bool
    let attribution: AIHotAttribution?
}

struct AIHotPage: Decodable, Equatable, Sendable {
    let count: Int
    let hasMore: Bool
    let nextCursor: String?
}

struct AIHotItemsResponse: Decodable, Equatable, Sendable {
    let schemaVersion: Int
    let items: [AIHotItem]
    let page: AIHotPage
}

struct AIHotHotTopic: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let source: AIHotSource
    let links: AIHotLinks
    let sourceCount: Int
    let signalCount: Int
    let sourceNames: [String]
    let latestAt: Date
}

struct AIHotHotTopicsResponse: Decodable, Equatable, Sendable {
    let schemaVersion: Int
    let count: Int
    let items: [AIHotHotTopic]
}

struct AIHotDailyEntryLinks: Decodable, Equatable, Sendable {
    let aihot: String

    var aihotURL: URL? { AIHotURLValidator.webURL(from: aihot) }
}

struct AIHotDailyEntry: Decodable, Identifiable, Equatable, Sendable {
    var id: String { date }

    let date: String
    let generatedAt: Date
    let leadTitle: String?
    let leadParagraph: String?
    let links: AIHotDailyEntryLinks
    let attribution: AIHotAttribution?
}

struct AIHotDailiesResponse: Decodable, Equatable, Sendable {
    let schemaVersion: Int
    let count: Int
    let items: [AIHotDailyEntry]
}

struct AIHotDailyReportLinks: Decodable, Equatable, Sendable {
    let aihot: String

    var aihotURL: URL? { AIHotURLValidator.webURL(from: aihot) }
}

struct AIHotDailyContentLinks: Decodable, Equatable, Sendable {
    let aihot: String?
    let original: String

    var aihotURL: URL? { AIHotURLValidator.webURL(from: aihot) }
    var originalURL: URL? { AIHotURLValidator.webURL(from: original) }
    var preferredURL: URL? { aihotURL ?? originalURL }
}

struct AIHotDailyLead: Decodable, Equatable, Sendable {
    let title: String
    let leadParagraph: String
}

struct AIHotDailySectionItem: Decodable, Identifiable, Equatable, Sendable {
    var id: String {
        [title, source.name, links.aihot ?? "", links.original].joined(separator: "\u{1F}")
    }

    let title: String
    let summary: String
    let source: AIHotSource
    let links: AIHotDailyContentLinks
    let attribution: AIHotAttribution?
}

struct AIHotDailySection: Decodable, Identifiable, Equatable, Sendable {
    var id: String { label }

    let label: String
    let items: [AIHotDailySectionItem]
}

struct AIHotDailyFlash: Decodable, Identifiable, Equatable, Sendable {
    var id: String {
        [title, source.name, links.aihot ?? "", links.original].joined(separator: "\u{1F}")
    }

    let title: String
    let source: AIHotSource
    let links: AIHotDailyContentLinks
    let publishedAt: Date
    let attribution: AIHotAttribution?
}

struct AIHotDailyReport: Decodable, Equatable, Sendable {
    let date: String
    let generatedAt: Date
    let windowStart: Date
    let windowEnd: Date
    let links: AIHotDailyReportLinks
    let attribution: AIHotAttribution?
    let lead: AIHotDailyLead?
    let sections: [AIHotDailySection]
    let flashes: [AIHotDailyFlash]
}

struct AIHotDailyResponse: Decodable, Equatable, Sendable {
    let schemaVersion: Int
    let report: AIHotDailyReport
}

struct AIHotProblem: Decodable, Equatable, Sendable {
    let type: String?
    let title: String?
    let status: Int?
    let detail: String?
    let code: String?
    let requestId: String?
}

enum AIHotURLValidator {
    static func webURL(from value: String?) -> URL? {
        guard
            let value,
            let url = URL(string: value),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            url.host != nil
        else {
            return nil
        }
        return url
    }
}
