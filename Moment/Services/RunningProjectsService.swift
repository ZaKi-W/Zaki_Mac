import Combine
import Darwin
import Foundation

struct ListeningEndpoint: Identifiable, Hashable, Sendable {
    let address: String
    let port: Int

    var id: String { "\(address):\(port)" }

    var displayAddress: String {
        "\(address):\(port)"
    }

    var localWebURL: URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = browserHost
        components.port = port
        return components.url
    }

    private var browserHost: String {
        switch address {
        case "*", "0.0.0.0", "::", "[::]", "::1", "[::1]":
            "127.0.0.1"
        default:
            if address.hasPrefix("["), address.hasSuffix("]") {
                String(address.dropFirst().dropLast())
            } else {
                address
            }
        }
    }
}

struct RunningService: Identifiable, Hashable, Sendable {
    let processID: Int32
    let userID: UInt32?
    let processName: String
    let command: String?
    let workingDirectory: String?
    let projectRoot: String?
    let endpoints: [ListeningEndpoint]

    var id: Int32 { processID }

    var isProject: Bool {
        projectRoot != nil
    }

    var canStop: Bool {
        guard
            userID == UInt32(getuid()),
            processID != ProcessInfo.processInfo.processIdentifier
        else {
            return false
        }

        return isProject || isRecognizedDevelopmentProcess
    }

    var displayName: String {
        guard let path = projectRoot ?? workingDirectory else {
            return processName
        }
        let name = URL(fileURLWithPath: path).lastPathComponent
        return name.isEmpty ? processName : name
    }

    var displayPath: String? {
        projectRoot ?? workingDirectory
    }

    var primaryWebEndpoint: ListeningEndpoint? {
        guard isLikelyWebService else { return nil }
        return endpoints.min { $0.port < $1.port }
    }

    private var isLikelyWebService: Bool {
        let excludedPorts: Set<Int> = [22, 25, 53, 110, 143, 445, 993, 995, 3_306, 5_432, 6_379]
        guard endpoints.contains(where: { !excludedPorts.contains($0.port) }) else {
            return false
        }

        let signature = "\(processName) \(command ?? "")".lowercased()
        let webSignatures = [
            "node", "vite", "next", "nuxt", "webpack", "bun", "deno",
            "python", "uvicorn", "flask", "django", "ruby", "rails",
            "php", "java", "dotnet"
        ]
        return isProject || webSignatures.contains(where: signature.contains)
    }

    private var isRecognizedDevelopmentProcess: Bool {
        let signature = "\(processName) \(command ?? "")".lowercased()
        let developmentSignatures = [
            "node", "npm", "npx", "pnpm", "yarn", "vite", "next", "nuxt",
            "webpack", "bun", "deno", "http-server", "uvicorn", "gunicorn",
            "flask", "django", "rails", "puma", "artisan serve", "php -s",
            "cargo run", "go run", "gradle", "mvn", "dotnet watch"
        ]
        return developmentSignatures.contains(where: signature.contains)
    }
}

enum RunningProjectsScannerError: LocalizedError {
    case commandUnavailable
    case scanFailed

    var errorDescription: String? {
        switch self {
        case .commandUnavailable:
            "The system port scanner is unavailable."
        case .scanFailed:
            "Listening ports could not be read."
        }
    }
}

struct RunningProjectsScanner: Sendable {
    func scan() async throws -> [RunningService] {
        try await Task.detached(priority: .utility) {
            try Self.scanSynchronously()
        }.value
    }

    private struct ServiceBuilder {
        let processID: Int32
        var userID: UInt32?
        var processName = "Process"
        var endpoints: Set<ListeningEndpoint> = []
    }

    private static let projectMarkers = [
        ".git", "package.json", "Package.swift", "pyproject.toml",
        "requirements.txt", "Cargo.toml", "go.mod", "pom.xml",
        "build.gradle", "build.gradle.kts", "Gemfile", "composer.json"
    ]

    private static func scanSynchronously() throws -> [RunningService] {
        guard FileManager.default.isExecutableFile(atPath: "/usr/sbin/lsof") else {
            throw RunningProjectsScannerError.commandUnavailable
        }

        let output = try run(
            executable: "/usr/sbin/lsof",
            arguments: ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpcun"],
            acceptsNonzeroExit: true
        )
        let builders = parseListeners(output)
        guard !builders.isEmpty else { return [] }

        let processIDs = builders.keys.sorted()
        let workingDirectories = readWorkingDirectories(processIDs)
        let commands = readCommands(processIDs)

        return builders.values.map { builder in
            let workingDirectory = workingDirectories[builder.processID]
            return RunningService(
                processID: builder.processID,
                userID: builder.userID,
                processName: builder.processName,
                command: commands[builder.processID],
                workingDirectory: workingDirectory,
                projectRoot: workingDirectory.flatMap(findProjectRoot),
                endpoints: builder.endpoints.sorted {
                    if $0.port == $1.port { return $0.address < $1.address }
                    return $0.port < $1.port
                }
            )
        }
        .sorted {
            if $0.isProject != $1.isProject { return $0.isProject }
            let comparison = $0.displayName.localizedCaseInsensitiveCompare($1.displayName)
            if comparison != .orderedSame { return comparison == .orderedAscending }
            return $0.processID < $1.processID
        }
    }

    private static func parseListeners(_ output: String) -> [Int32: ServiceBuilder] {
        var builders: [Int32: ServiceBuilder] = [:]
        var currentProcessID: Int32?

        for line in output.split(whereSeparator: \Character.isNewline) {
            guard let field = line.first else { continue }
            let value = String(line.dropFirst())

            switch field {
            case "p":
                guard let processID = Int32(value) else {
                    currentProcessID = nil
                    continue
                }
                currentProcessID = processID
                if builders[processID] == nil {
                    builders[processID] = ServiceBuilder(processID: processID)
                }
            case "c":
                guard let currentProcessID else { continue }
                builders[currentProcessID]?.processName = value
            case "u":
                guard let currentProcessID else { continue }
                builders[currentProcessID]?.userID = UInt32(value)
            case "n":
                guard
                    let currentProcessID,
                    let endpoint = parseEndpoint(value)
                else {
                    continue
                }
                builders[currentProcessID]?.endpoints.insert(endpoint)
            default:
                continue
            }
        }

        return builders.filter { !$0.value.endpoints.isEmpty }
    }

    private static func parseEndpoint(_ value: String) -> ListeningEndpoint? {
        guard let separator = value.lastIndex(of: ":") else { return nil }
        let address = String(value[..<separator])
        let portText = value[value.index(after: separator)...]
        guard let port = Int(portText), (1...65_535).contains(port) else {
            return nil
        }
        return ListeningEndpoint(address: address, port: port)
    }

    private static func readWorkingDirectories(
        _ processIDs: [Int32]
    ) -> [Int32: String] {
        var result: [Int32: String] = [:]

        for batch in processIDs.chunked(maxCount: 100) {
            let ids = batch.map(String.init).joined(separator: ",")
            guard let output = try? run(
                executable: "/usr/sbin/lsof",
                arguments: ["-a", "-p", ids, "-d", "cwd", "-Fpn"],
                acceptsNonzeroExit: true
            ) else {
                continue
            }

            var currentProcessID: Int32?
            for line in output.split(whereSeparator: \Character.isNewline) {
                guard let field = line.first else { continue }
                let value = String(line.dropFirst())
                if field == "p" {
                    currentProcessID = Int32(value)
                } else if field == "n", let currentProcessID {
                    result[currentProcessID] = value
                }
            }
        }

        return result
    }

    private static func readCommands(_ processIDs: [Int32]) -> [Int32: String] {
        var result: [Int32: String] = [:]

        for batch in processIDs.chunked(maxCount: 100) {
            let ids = batch.map(String.init).joined(separator: ",")
            guard let output = try? run(
                executable: "/bin/ps",
                arguments: ["-p", ids, "-o", "pid=", "-o", "command="],
                acceptsNonzeroExit: true
            ) else {
                continue
            }

            for line in output.split(whereSeparator: \Character.isNewline) {
                let trimmed = line.drop(while: \Character.isWhitespace)
                guard let separator = trimmed.firstIndex(where: \Character.isWhitespace) else {
                    continue
                }
                guard let processID = Int32(trimmed[..<separator]) else { continue }
                let command = trimmed[separator...]
                    .drop(while: \Character.isWhitespace)
                if !command.isEmpty {
                    result[processID] = String(command)
                }
            }
        }

        return result
    }

    private static func findProjectRoot(from workingDirectory: String) -> String? {
        let fileManager = FileManager.default
        var candidate = URL(fileURLWithPath: workingDirectory).standardizedFileURL

        while candidate.path != "/" {
            if projectMarkers.contains(where: {
                fileManager.fileExists(atPath: candidate.appending(path: $0).path)
            }) {
                return candidate.path
            }

            if let entries = try? fileManager.contentsOfDirectory(
                at: candidate,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ), entries.contains(where: {
                ["xcodeproj", "xcworkspace"].contains($0.pathExtension.lowercased())
            }) {
                return candidate.path
            }

            let parent = candidate.deletingLastPathComponent()
            guard parent != candidate else { break }
            candidate = parent
        }

        return nil
    }

    private static func run(
        executable: String,
        arguments: [String],
        acceptsNonzeroExit: Bool = false
    ) throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw RunningProjectsScannerError.commandUnavailable
        }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard acceptsNonzeroExit || process.terminationStatus == 0 else {
            throw RunningProjectsScannerError.scanFailed
        }
        return String(decoding: data, as: UTF8.self)
    }
}

private enum RunningServiceStopError: LocalizedError {
    case notAllowed
    case permissionDenied
    case signalFailed(Int32)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .notAllowed:
            "This service cannot be stopped from Moment."
        case .permissionDenied:
            "Moment does not have permission to stop this service."
        case let .signalFailed(code):
            "The stop signal could not be sent (error \(code))."
        case .timedOut:
            "The service did not exit after receiving the stop signal."
        }
    }
}

private enum RunningServiceStopper {
    static func stop(processID: Int32) async throws {
        if kill(processID, SIGTERM) != 0 {
            let code = errno
            if code == ESRCH { return }
            if code == EPERM { throw RunningServiceStopError.permissionDenied }
            throw RunningServiceStopError.signalFailed(code)
        }

        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(250))
            if kill(processID, 0) != 0, errno == ESRCH {
                return
            }
        }

        throw RunningServiceStopError.timedOut
    }
}

@MainActor
final class RunningProjectsController: ObservableObject {
    @Published private(set) var services: [RunningService] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastUpdatedAt: Date?
    @Published private(set) var errorMessage: String?
    @Published private(set) var stoppingProcessIDs: Set<Int32> = []

    private let scanner: RunningProjectsScanner

    init(scanner: RunningProjectsScanner = RunningProjectsScanner()) {
        self.scanner = scanner
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            services = try await scanner.scan()
            lastUpdatedAt = .now
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop(_ service: RunningService) async {
        guard service.canStop else {
            errorMessage = RunningServiceStopError.notAllowed.localizedDescription
            return
        }
        guard stoppingProcessIDs.insert(service.processID).inserted else { return }
        defer { stoppingProcessIDs.remove(service.processID) }

        errorMessage = nil
        var stopErrorMessage: String?
        do {
            try await RunningServiceStopper.stop(processID: service.processID)
        } catch {
            stopErrorMessage = error.localizedDescription
        }

        await refresh()
        if let stopErrorMessage {
            errorMessage = stopErrorMessage
        }
    }
}

private extension Array {
    func chunked(maxCount: Int) -> [[Element]] {
        guard maxCount > 0 else { return [] }
        return stride(from: 0, to: count, by: maxCount).map {
            Array(self[$0..<Swift.min($0 + maxCount, count)])
        }
    }
}
