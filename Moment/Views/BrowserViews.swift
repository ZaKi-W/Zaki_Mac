import SwiftUI

struct BrowserWorkspace: View {
    @ObservedObject var model: AppModel
    @ObservedObject var controller: BrowserController

    var body: some View {
        VStack(spacing: 0) {
            BrowserTabStrip(controller: controller)
            Divider()
            if let tab = controller.activeTab {
                BrowserDetail(
                    model: model,
                    controller: controller,
                    tab: tab
                )
                .id(tab.id)
            }
        }
        .navigationTitle(model.text("sidebar.browser"))
    }
}

private struct BrowserTabStrip: View {
    @ObservedObject var controller: BrowserController

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 3) {
                ForEach(controller.tabs) { tab in
                    BrowserTabButton(
                        tab: tab,
                        active: tab.id == controller.activeID,
                        activate: { controller.activate(tab.id) },
                        close: { controller.closeTab(tab.id) }
                    )
                }
                Button {
                    controller.createTab()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 26, height: 24)
                }
                .buttonStyle(HoverIconButtonStyle(kind: .accent, size: 26))
                .help("New Tab")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
        }
        .background(.bar)
    }
}

private struct BrowserTabButton: View {
    @ObservedObject var tab: BrowserTabModel
    let active: Bool
    let activate: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            if tab.isLoading {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Image(systemName: tab.isHome ? "sparkle" : "globe")
                    .foregroundStyle(.secondary)
            }
            Text(tab.displayTitle)
                .lineLimit(1)
                .frame(maxWidth: 130, alignment: .leading)
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(HoverIconButtonStyle(size: 22))
        }
        .font(.caption)
        .padding(.leading, 9)
        .padding(.trailing, 6)
        .frame(width: 180, height: 28)
        .background(
            active ? AnyShapeStyle(.background) : AnyShapeStyle(.clear),
            in: RoundedRectangle(cornerRadius: 6)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    active ? Color(nsColor: .separatorColor) : Color.clear,
                    lineWidth: 0.5
                )
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: activate)
    }
}

private struct BrowserDetail: View {
    @ObservedObject var model: AppModel
    @ObservedObject var controller: BrowserController
    @ObservedObject var tab: BrowserTabModel
    @State private var address = ""
    @FocusState private var addressFocused: Bool

    var body: some View {
        Group {
            if tab.isHome {
                BrowserStartPage(
                    model: model,
                    navigate: { tab.load($0) }
                )
            } else {
                WebViewContainer(tab: tab)
            }
        }
        .overlay(alignment: .top) {
            if tab.isLoading {
                ProgressView(value: tab.progress)
                    .progressViewStyle(.linear)
                    .controlSize(.mini)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button(action: tab.goBack) {
                    Image(systemName: "chevron.left")
                }
                .disabled(!tab.canGoBack)
                .help(model.text("browser.back"))

                Button(action: tab.goForward) {
                    Image(systemName: "chevron.right")
                }
                .disabled(!tab.canGoForward)
                .help(model.text("browser.forward"))

                Button(action: tab.reload) {
                    Image(systemName: tab.isLoading ? "xmark" : "arrow.clockwise")
                }
                .help(model.text("browser.reload"))

                Button(action: tab.goHome) {
                    Image(systemName: "house")
                }
                .help(model.text("browser.home"))
            }

            ToolbarItem(placement: .principal) {
                TextField(
                    model.text("browser.address"),
                    text: $address
                )
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 280, idealWidth: 460, maxWidth: 620)
                .focused($addressFocused)
                .onSubmit {
                    controller.navigate(address, language: model.preferences.language)
                    addressFocused = false
                }
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    model.addBookmarkForActivePage()
                } label: {
                    Image(
                        systemName: model.isBookmarked(tab.url)
                            ? "star.fill"
                            : "star"
                    )
                }
                .disabled(tab.isHome)
                .help(
                    model.text(
                        model.isBookmarked(tab.url)
                            ? "browser.unbookmark"
                            : "browser.bookmark"
                    )
                )

                Toggle(
                    isOn: Binding(
                        get: { model.preferences.browserDarkMode },
                        set: { model.updateBrowserDarkMode($0) }
                    )
                ) {
                    Image(
                        systemName: model.preferences.browserDarkMode
                            ? "sun.max"
                            : "moon"
                    )
                }
                .toggleStyle(.button)
                .help(model.text("browser.dark"))
            }
        }
        .onAppear {
            address = tab.url?.absoluteString ?? ""
        }
        .onChange(of: tab.url) { _, newValue in
            if !addressFocused {
                address = newValue?.absoluteString ?? ""
            }
        }
        .onChange(of: controller.focusAddressToken) { _, _ in
            addressFocused = true
        }
    }
}

private struct BrowserStartPage: View {
    @ObservedObject var model: AppModel
    let navigate: (URL) -> Void

    private let quickSites: [(String, String, String)] = [
        ("百度", "https://www.baidu.com", "magnifyingglass"),
        ("Google", "https://www.google.com", "g.circle"),
        ("GitHub", "https://github.com", "chevron.left.forwardslash.chevron.right"),
        ("哔哩哔哩", "https://www.bilibili.com", "play.rectangle"),
        ("知乎", "https://www.zhihu.com", "text.book.closed"),
        ("微博", "https://weibo.com", "bubble.left.and.bubble.right"),
        ("YouTube", "https://www.youtube.com", "play.square"),
        ("X", "https://x.com", "at")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.text("browser.start"))
                        .font(.largeTitle.weight(.semibold))
                    Text(Date.now.formatted(date: .complete, time: .omitted))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(model.text("browser.favorites"))
                        .font(.headline)
                    LazyVGrid(
                        columns: [
                            GridItem(.adaptive(minimum: 130, maximum: 170), spacing: 12)
                        ],
                        spacing: 12
                    ) {
                        ForEach(quickSites, id: \.1) { name, address, symbol in
                            Button {
                                if let url = URL(string: address) {
                                    navigate(url)
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 14) {
                                    Image(systemName: symbol)
                                        .font(.title2)
                                        .symbolRenderingMode(.hierarchical)
                                    Text(name)
                                        .fontWeight(.medium)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .background(.quaternary.opacity(0.55))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !model.bookmarks.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.text("browser.bookmarks"))
                            .font(.headline)
                        ForEach(model.bookmarks) { bookmark in
                            HStack {
                                Button {
                                    navigate(bookmark.url)
                                } label: {
                                    Label(bookmark.title, systemImage: "bookmark")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                Button {
                                    model.removeBookmark(bookmark)
                                } label: {
                                    Image(systemName: "xmark")
                                }
                                .buttonStyle(HoverIconButtonStyle(kind: .destructive, size: 24))
                            }
                            .padding(.vertical, 5)
                        }
                    }
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(42)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
