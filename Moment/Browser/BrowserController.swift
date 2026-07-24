import AppKit
import Foundation
import WebKit

@MainActor
final class BrowserController: ObservableObject {
    @Published private(set) var tabs: [BrowserTabModel] = []
    @Published var activeID: UUID?
    @Published var focusAddressToken = 0
    private var darkModeEnabled = false

    var activeTab: BrowserTabModel? {
        tabs.first { $0.id == activeID }
    }

    init() {
        createTab()
    }

    @discardableResult
    func createTab(url: URL? = nil) -> BrowserTabModel {
        let tab = BrowserTabModel()
        tab.setDarkMode(darkModeEnabled)
        tab.onOpenNewTab = { [weak self] url in
            self?.createTab(url: url)
        }
        tabs.append(tab)
        activeID = tab.id
        if let url {
            tab.load(url)
        } else {
            focusAddressToken += 1
        }
        return tab
    }

    func closeActiveTab() {
        guard let activeID else { return }
        closeTab(activeID)
    }

    func closeTab(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].stop()
        tabs.remove(at: index)
        if tabs.isEmpty {
            createTab()
        } else if activeID == id {
            self.activeID = tabs[min(index, tabs.count - 1)].id
        }
    }

    func activate(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeID = id
    }

    func navigate(_ input: String, language: AppLanguage) {
        guard
            let activeTab,
            let url = URLResolver.resolve(input, language: language)
        else {
            return
        }
        activeTab.load(url)
    }

    func setDarkMode(_ enabled: Bool) {
        darkModeEnabled = enabled
        for tab in tabs {
            tab.setDarkMode(enabled)
        }
    }
}

@MainActor
final class BrowserTabModel: NSObject, ObservableObject, Identifiable {
    let id = UUID()
    let webView: WKWebView

    @Published private(set) var url: URL?
    @Published private(set) var title = ""
    @Published private(set) var isLoading = false
    @Published private(set) var progress = 0.0
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false

    var onOpenNewTab: ((URL) -> Void)?
    private var darkMode = false
    private var observations: [NSKeyValueObservation] = []

    var isHome: Bool { url == nil }
    var displayTitle: String {
        if isHome { return "Start Page" }
        return title.isEmpty ? (url?.host() ?? "Website") : title
    }

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsMagnification = true
        webView.allowsLinkPreview = true
        observeWebView()
    }

    func load(_ url: URL) {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            NSWorkspace.shared.open(url)
            return
        }
        self.url = url
        webView.load(URLRequest(url: url))
    }

    func goHome() {
        webView.stopLoading()
        url = nil
        title = ""
        isLoading = false
        progress = 0
        refreshNavigationState()
    }

    func goBack() {
        if webView.canGoBack { webView.goBack() }
    }

    func goForward() {
        if webView.canGoForward { webView.goForward() }
    }

    func reload() {
        if isHome {
            return
        }
        webView.reload()
    }

    func stop() {
        webView.stopLoading()
    }

    func setDarkMode(_ enabled: Bool) {
        darkMode = enabled
        applyWebsiteAppearance()
    }

    private func observeWebView() {
        observations = [
            webView.observe(\.title, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in
                    self?.title = view.title ?? ""
                }
            },
            webView.observe(\.url, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in
                    if let url = view.url,
                       ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                        self?.url = url
                    }
                }
            },
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in
                    self?.progress = view.estimatedProgress
                }
            },
            webView.observe(\.isLoading, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in
                    self?.isLoading = view.isLoading
                }
            }
        ]
    }

    private func refreshNavigationState() {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }

    private func applyWebsiteAppearance() {
        let enabled = darkMode ? "true" : "false"
        let isZhihu = url?.host()?.lowercased().hasSuffix("zhihu.com") == true
        let zhihuReadingStyle = isZhihu
            ? """
              .AppHeader, .CornerButtons, .Question-sideColumn,
              .GlobalSideBar, .Pc-card, .Banner-link { display: none !important; }
              .Question-mainColumn, .Topstory-mainColumn {
                width: min(760px, calc(100vw - 48px)) !important;
                margin: 28px auto !important;
              }
              """
            : ""

        webView.evaluateJavaScript(
            """
            (() => {
              const root = document.documentElement;
              if (!root || !document.head) return;

              const darkStyleID = 'moment-dark-style';
              const existingDarkStyle = document.getElementById(darkStyleID);

              if (!\(enabled)) {
                existingDarkStyle?.remove();
                root.removeAttribute('data-moment-dark');
              } else {
                const visibleBackground = (element) => {
                  if (!element) return null;
                  const match = getComputedStyle(element).backgroundColor.match(
                    /rgba?\\((\\d+)[, ]+(\\d+)[, ]+(\\d+)(?:[, /]+([\\d.]+))?\\)/
                  );
                  if (!match || (match[4] !== undefined && Number(match[4]) < 0.05)) {
                    return null;
                  }
                  return [Number(match[1]), Number(match[2]), Number(match[3])];
                };
                const rgb = visibleBackground(document.body)
                  || visibleBackground(root)
                  || [255, 255, 255];
                const luminance = (
                  0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]
                ) / 255;

                let style = existingDarkStyle;
                if (!style) {
                  style = document.createElement('style');
                  style.id = darkStyleID;
                  document.head.appendChild(style);
                }

                style.textContent = luminance > 0.48
                  ? `
                    :root {
                      color-scheme: dark !important;
                      background: #f5f5f5 !important;
                      filter: invert(1) hue-rotate(180deg) !important;
                    }
                    img, picture, video, canvas, iframe {
                      filter: invert(1) hue-rotate(180deg) !important;
                    }
                  `
                  : `
                    :root {
                      color-scheme: dark !important;
                      background: #17191c !important;
                    }
                  `;
                root.setAttribute('data-moment-dark', 'true');
              }

              const readingStyleID = 'moment-reading-style';
              const readingCSS = \(String(reflecting: zhihuReadingStyle));
              let readingStyle = document.getElementById(readingStyleID);
              if (readingCSS) {
                if (!readingStyle) {
                  readingStyle = document.createElement('style');
                  readingStyle.id = readingStyleID;
                  document.head.appendChild(readingStyle);
                }
                readingStyle.textContent = readingCSS;
              } else {
                readingStyle?.remove();
              }
            })();
            """
        )
    }

    private func downloadDestination(suggestedFilename: String) -> URL {
        let downloads = FileManager.default.urls(
            for: .downloadsDirectory,
            in: .userDomainMask
        )[0]
        let candidate = downloads.appending(path: suggestedFilename)
        guard FileManager.default.fileExists(atPath: candidate.path) else {
            return candidate
        }
        let base = candidate.deletingPathExtension().lastPathComponent
        let ext = candidate.pathExtension
        for index in 2...999 {
            let name = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            let alternative = downloads.appending(path: name)
            if !FileManager.default.fileExists(atPath: alternative.path) {
                return alternative
            }
        }
        return downloads.appending(path: "\(UUID().uuidString)-\(suggestedFilename)")
    }
}

extension BrowserTabModel: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        guard let destination = navigationAction.request.url else {
            return .cancel
        }
        let scheme = destination.scheme?.lowercased() ?? ""
        if scheme == "http" || scheme == "https" || scheme == "about" {
            return navigationAction.shouldPerformDownload ? .download : .allow
        }
        NSWorkspace.shared.open(destination)
        return .cancel
    }

    func webView(
        _ webView: WKWebView,
        navigationAction: WKNavigationAction,
        didBecome download: WKDownload
    ) {
        download.delegate = self
    }

    func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        refreshNavigationState()
        applyWebsiteAppearance()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation?) {
        refreshNavigationState()
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation?,
        withError error: Error
    ) {
        refreshNavigationState()
    }
}

extension BrowserTabModel: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            onOpenNewTab?(url)
        }
        return nil
    }
}

extension BrowserTabModel: WKDownloadDelegate {
    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String
    ) async -> URL? {
        downloadDestination(suggestedFilename: suggestedFilename)
    }
}
