import { randomUUID } from 'node:crypto'
import {
  WebContentsView,
  type BrowserWindow,
  type Rectangle,
  type WebContents
} from 'electron'
import {
  type BrowserBounds,
  type BrowserState,
  type BrowserTab
} from '../../shared/contracts.js'
import { isSafeWebUrl, isZhihuUrl } from '../../shared/browser.js'
import {
  ZHIHU_DARK_CSS,
  ZHIHU_READING_CSS
} from '../../shared/zhihu-style.js'

type ManagedTab = {
  state: BrowserTab
  view: WebContentsView | null
  insertedCssKey: string | null
}

type BrowserTabManagerOptions = {
  window: BrowserWindow
  darkMode: boolean
  onChanged: (state: BrowserState) => void
  onWebContentsCreated: (contents: WebContents) => void
}

export class BrowserTabManager {
  private readonly window: BrowserWindow
  private readonly onChanged: (state: BrowserState) => void
  private readonly onWebContentsCreated: (contents: WebContents) => void
  private tabs: ManagedTab[] = []
  private activeId: string | null = null
  private visible = false
  private darkMode: boolean
  private bounds: Rectangle = { x: 0, y: 0, width: 0, height: 0 }
  private attachedView: WebContentsView | null = null

  constructor(options: BrowserTabManagerOptions) {
    this.window = options.window
    this.darkMode = options.darkMode
    this.onChanged = options.onChanged
    this.onWebContentsCreated = options.onWebContentsCreated
    this.create()
  }

  state(): BrowserState {
    return {
      tabs: this.tabs.map(({ state }) => ({ ...state })),
      activeId: this.activeId,
      visible: this.visible
    }
  }

  create(): BrowserState {
    const id = randomUUID()
    this.tabs.push({
      state: {
        id,
        url: '',
        title: '',
        isHome: true,
        loading: false,
        canGoBack: false,
        canGoForward: false
      },
      view: null,
      insertedCssKey: null
    })
    this.activeId = id
    this.attachActive()
    return this.publish()
  }

  close(id: string): BrowserState {
    const index = this.tabs.findIndex((tab) => tab.state.id === id)
    if (index === -1) throw new Error('Browser tab not found')

    const [closed] = this.tabs.splice(index, 1)
    if (closed) this.disposeTab(closed)

    if (this.tabs.length === 0) return this.create()

    if (this.activeId === id) {
      const nextIndex = Math.min(index, this.tabs.length - 1)
      this.activeId = this.tabs[nextIndex]?.state.id ?? null
    }
    this.attachActive()
    return this.publish()
  }

  activate(id: string): BrowserState {
    this.requireTab(id)
    this.activeId = id
    this.attachActive()
    return this.publish()
  }

  navigate(id: string, url: string): BrowserState {
    if (!isSafeWebUrl(url)) throw new Error('Only HTTP and HTTPS URLs are allowed')
    const tab = this.requireTab(id)
    const view = this.ensureView(tab)
    tab.state = { ...tab.state, url, isHome: false, loading: true }
    if (id === this.activeId) this.attachActive()
    void view.webContents.loadURL(url)
    return this.publish()
  }

  back(id: string): BrowserState {
    const tab = this.requireTab(id)
    if (tab.view?.webContents.navigationHistory.canGoBack()) {
      tab.view.webContents.navigationHistory.goBack()
    }
    return this.state()
  }

  forward(id: string): BrowserState {
    const tab = this.requireTab(id)
    if (tab.view?.webContents.navigationHistory.canGoForward()) {
      tab.view.webContents.navigationHistory.goForward()
    }
    return this.state()
  }

  reload(id: string): BrowserState {
    this.requireTab(id).view?.webContents.reload()
    return this.state()
  }

  home(id: string): BrowserState {
    const tab = this.requireTab(id)
    tab.state = {
      ...tab.state,
      url: '',
      title: '',
      isHome: true,
      loading: false,
      canGoBack: false,
      canGoForward: false
    }
    if (id === this.activeId) this.attachActive()
    return this.publish()
  }

  setBounds(bounds: BrowserBounds): BrowserBounds {
    this.bounds = { ...bounds }
    if (this.attachedView) this.attachedView.setBounds(this.bounds)
    return { ...bounds }
  }

  setVisible(visible: boolean): BrowserState {
    this.visible = visible
    this.attachActive()
    return this.publish()
  }

  setDarkMode(darkMode: boolean): void {
    this.darkMode = darkMode
    for (const tab of this.tabs) void this.syncZhihuStyle(tab)
  }

  destroy(): void {
    this.detachCurrent()
    for (const tab of this.tabs) this.disposeTab(tab)
    this.tabs = []
    this.activeId = null
  }

  private ensureView(tab: ManagedTab): WebContentsView {
    if (tab.view) return tab.view

    const view = new WebContentsView({
      webPreferences: {
        partition: 'persist:browser-v2',
        sandbox: true,
        contextIsolation: true,
        nodeIntegration: false,
        allowRunningInsecureContent: false,
        navigateOnDragDrop: false
      }
    })
    view.setBackgroundColor('#fcfbf8')
    tab.view = view
    this.onWebContentsCreated(view.webContents)

    const updateNavigation = (): void => {
      tab.state = {
        ...tab.state,
        canGoBack: view.webContents.navigationHistory.canGoBack(),
        canGoForward: view.webContents.navigationHistory.canGoForward()
      }
    }

    view.webContents.on('did-start-loading', () => {
      tab.state = { ...tab.state, loading: true }
      this.publish()
    })
    view.webContents.on('did-stop-loading', () => {
      updateNavigation()
      tab.state = { ...tab.state, loading: false }
      this.publish()
    })
    view.webContents.on('did-navigate', (_event, url) => {
      if (isSafeWebUrl(url)) {
        tab.state = { ...tab.state, url, isHome: false }
        updateNavigation()
        this.publish()
      }
    })
    view.webContents.on('did-navigate-in-page', (_event, url) => {
      if (isSafeWebUrl(url)) {
        tab.state = { ...tab.state, url, isHome: false }
        updateNavigation()
        this.publish()
      }
    })
    view.webContents.on('page-title-updated', (event, title) => {
      event.preventDefault()
      tab.state = { ...tab.state, title }
      this.publish()
    })
    view.webContents.on('did-finish-load', () => {
      updateNavigation()
      void this.syncZhihuStyle(tab)
      this.publish()
    })
    view.webContents.on('will-navigate', (event, url) => {
      if (!isSafeWebUrl(url)) event.preventDefault()
    })
    view.webContents.setWindowOpenHandler(({ url }) => {
      if (isSafeWebUrl(url)) void view.webContents.loadURL(url)
      return { action: 'deny' }
    })

    return view
  }

  private async syncZhihuStyle(tab: ManagedTab): Promise<void> {
    const contents = tab.view?.webContents
    if (!contents || contents.isDestroyed()) return

    if (tab.insertedCssKey) {
      await contents.removeInsertedCSS(tab.insertedCssKey)
      tab.insertedCssKey = null
    }
    if (!isZhihuUrl(contents.getURL())) return

    const css = this.darkMode ? ZHIHU_DARK_CSS : ZHIHU_READING_CSS
    tab.insertedCssKey = await contents.insertCSS(css)
  }

  private attachActive(): void {
    this.detachCurrent()
    if (!this.visible || !this.activeId) return

    const active = this.tabs.find((tab) => tab.state.id === this.activeId)
    if (!active?.view || active.state.isHome) return
    this.window.contentView.addChildView(active.view)
    active.view.setBounds(this.bounds)
    this.attachedView = active.view
  }

  private detachCurrent(): void {
    if (!this.attachedView) return
    this.window.contentView.removeChildView(this.attachedView)
    this.attachedView = null
  }

  private disposeTab(tab: ManagedTab): void {
    if (this.attachedView === tab.view) this.detachCurrent()
    if (tab.view && !tab.view.webContents.isDestroyed()) {
      tab.view.webContents.close()
    }
    tab.view = null
    tab.insertedCssKey = null
  }

  private requireTab(id: string): ManagedTab {
    const tab = this.tabs.find((candidate) => candidate.state.id === id)
    if (!tab) throw new Error('Browser tab not found')
    return tab
  }

  private publish(): BrowserState {
    const state = this.state()
    this.onChanged(state)
    return state
  }
}
