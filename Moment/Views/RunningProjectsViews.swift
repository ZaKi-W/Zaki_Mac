import AppKit
import SwiftUI

struct RunningProjectsWorkspace: View {
    @ObservedObject var model: AppModel
    @ObservedObject var controller: RunningProjectsController

    @State private var searchText = ""
    @State private var showsOtherListeners = false
    @State private var pendingStop: RunningService?

    private var projectServices: [RunningService] {
        filteredServices.filter(\.isProject)
    }

    private var otherServices: [RunningService] {
        filteredServices.filter { !$0.isProject }
    }

    private var filteredServices: [RunningService] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return controller.services }

        return controller.services.filter { service in
            let searchableText = [
                service.displayName,
                service.processName,
                service.command,
                service.displayPath,
                service.processID.description,
                service.endpoints.map(\.displayAddress).joined(separator: " ")
            ]
            .compactMap { $0 }
            .joined(separator: " ")
            return searchableText.localizedCaseInsensitiveContains(query)
        }
    }

    private var listeningPortCount: Int {
        Set(controller.services.flatMap { $0.endpoints.map(\.port) }).count
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            summaryBar
            Divider()

            if controller.services.isEmpty && controller.isRefreshing {
                loadingState
            } else if controller.services.isEmpty {
                emptyState
            } else if filteredServices.isEmpty {
                noSearchResultsState
            } else {
                serviceList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(model.text("running.title"))
        .searchable(
            text: $searchText,
            placement: .toolbar,
            prompt: model.text("running.search")
        )
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await controller.refresh() }
                } label: {
                    if controller.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label(
                            model.text("running.refresh"),
                            systemImage: "arrow.clockwise"
                        )
                    }
                }
                .disabled(controller.isRefreshing)
                .help(model.text("running.refresh"))
            }
        }
        .alert(
            model.text("running.stop.confirm.title"),
            isPresented: Binding(
                get: { pendingStop != nil },
                set: { if !$0 { pendingStop = nil } }
            ),
            presenting: pendingStop
        ) { service in
            Button(model.text("common.cancel"), role: .cancel) {
                pendingStop = nil
            }
            Button(model.text("running.stop"), role: .destructive) {
                pendingStop = nil
                Task { await controller.stop(service) }
            }
        } message: { service in
            Text(
                "\(model.text("running.stop.confirm.body")) "
                    + "\(service.displayName) (PID \(service.processID))"
            )
        }
        .task {
            await controller.refresh()
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    break
                }
                await controller.refresh()
            }
        }
    }

    private var summaryBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                summaryItem(
                    value: controller.services.filter(\.isProject).count,
                    label: model.text("running.summary.projects"),
                    systemImage: "hammer"
                )

                Divider()
                    .frame(height: 24)

                summaryItem(
                    value: listeningPortCount,
                    label: model.text("running.summary.ports"),
                    systemImage: "network"
                )

                Spacer(minLength: 12)

                if let lastUpdatedAt = controller.lastUpdatedAt {
                    Text(lastUpdatedAt, style: .time)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                        .help(model.text("running.updated"))
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 48)

            if let errorMessage = controller.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(model.text("running.error"))
                        .fontWeight(.medium)
                    Text(errorMessage)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button(model.text("running.refresh")) {
                        Task { await controller.refresh() }
                    }
                    .buttonStyle(.borderless)
                }
                .font(.callout)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.08))
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func summaryItem(
        value: Int,
        label: String,
        systemImage: String
    ) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.accentColor)
            Text(value, format: .number)
                .fontWeight(.semibold)
                .monospacedDigit()
            Text(label)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }

    private var serviceList: some View {
        List {
            if !projectServices.isEmpty {
                Section(model.text("running.section.projects")) {
                    ForEach(projectServices) { service in
                        RunningServiceRow(
                            model: model,
                            service: service,
                            isStopping: controller.stoppingProcessIDs.contains(
                                service.processID
                            ),
                            openInDefaultBrowser: openInDefaultBrowser,
                            revealInFinder: revealInFinder,
                            requestStop: { pendingStop = $0 }
                        )
                    }
                }
            }

            if showsOtherListeners || isSearching {
                if !otherServices.isEmpty {
                    Section(model.text("running.section.other")) {
                        ForEach(otherServices) { service in
                            RunningServiceRow(
                                model: model,
                                service: service,
                                isStopping: controller.stoppingProcessIDs.contains(
                                    service.processID
                                ),
                                openInDefaultBrowser: openInDefaultBrowser,
                                revealInFinder: revealInFinder,
                                requestStop: { pendingStop = $0 }
                            )
                        }
                    }
                }
            } else if !otherServices.isEmpty {
                Section {
                    Button {
                        withAnimation(.snappy) {
                            showsOtherListeners = true
                        }
                    } label: {
                        HStack {
                            Label(
                                model.text("running.showOther"),
                                systemImage: "chevron.down.circle"
                            )
                            Spacer()
                            Text(otherServices.count, format: .number)
                                .foregroundStyle(.tertiary)
                                .monospacedDigit()
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.inset)
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text(model.text("running.scanning"))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                model.text("running.empty.title"),
                systemImage: "network.slash"
            )
        } description: {
            Text(model.text("running.empty.body"))
        } actions: {
            Button(model.text("running.refresh")) {
                Task { await controller.refresh() }
            }
        }
    }

    private var noSearchResultsState: some View {
        ContentUnavailableView.search(text: searchText)
    }

    private func openInDefaultBrowser(_ endpoint: ListeningEndpoint) {
        guard let url = endpoint.localWebURL else { return }
        NSWorkspace.shared.open(url)
    }

    private func revealInFinder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([
            URL(fileURLWithPath: path)
        ])
    }
}

private struct RunningServiceRow: View {
    @ObservedObject var model: AppModel
    let service: RunningService
    let isStopping: Bool
    let openInDefaultBrowser: (ListeningEndpoint) -> Void
    let revealInFinder: (String) -> Void
    let requestStop: (RunningService) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: service.isProject ? "hammer.fill" : "gearshape.2.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(service.isProject ? Color.accentColor : .secondary)
                .frame(width: 34, height: 34)
                .background(
                    service.isProject
                        ? Color.accentColor.opacity(0.12)
                        : Color.secondary.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(service.displayName)
                        .font(.headline)
                        .lineLimit(1)

                    if service.isProject {
                        Text(model.text("running.projectBadge"))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Color.accentColor.opacity(0.1),
                                in: Capsule()
                            )
                    }
                }

                HStack(spacing: 5) {
                    Text(service.processName)
                    Text("·")
                    Text("PID \(service.processID)")
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let path = service.displayPath {
                    Text(path.abbreviatingWithTildeInPath)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(path)
                }

                HStack(spacing: 7) {
                    ForEach(service.endpoints) { endpoint in
                        endpointChip(endpoint)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                if let path = service.displayPath {
                    Button {
                        revealInFinder(path)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .help(model.text("running.reveal"))
                }

                if let endpoint = service.primaryWebEndpoint {
                    Button {
                        openInDefaultBrowser(endpoint)
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .help(model.text("running.open.help"))
                    .accessibilityLabel(model.text("running.open"))
                }

                if service.canStop {
                    Button {
                        requestStop(service)
                    } label: {
                        if isStopping {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label(
                                model.text("running.stop"),
                                systemImage: "stop.circle"
                            )
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
                    .disabled(isStopping)
                    .help(model.text("running.stop.help"))
                }
            }
        }
        .padding(.vertical, 7)
        .contextMenu {
            if let endpoint = service.primaryWebEndpoint {
                Button(model.text("running.open")) {
                    openInDefaultBrowser(endpoint)
                }
            }

            if let path = service.displayPath {
                Button(model.text("running.reveal")) {
                    revealInFinder(path)
                }
            }

            if service.canStop {
                Divider()
                Button(model.text("running.stop"), role: .destructive) {
                    requestStop(service)
                }
                .disabled(isStopping)
            }
        }
        .help(service.command ?? service.processName)
    }

    private func endpointChip(_ endpoint: ListeningEndpoint) -> some View {
        Button {
            copyToPasteboard(endpoint.displayAddress)
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
                Text(endpoint.port, format: .number.grouping(.never))
                    .monospacedDigit()
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Color(nsColor: .quaternaryLabelColor).opacity(0.35),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .help("\(model.text("running.copyAddress")): \(endpoint.displayAddress)")
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

private extension String {
    var abbreviatingWithTildeInPath: String {
        (self as NSString).abbreviatingWithTildeInPath
    }
}
