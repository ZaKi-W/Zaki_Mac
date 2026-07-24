import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'
import {
  app,
  BrowserWindow,
  nativeTheme,
  Notification,
  powerMonitor,
  type Event,
  type Input,
  type WebContents
} from 'electron'
import { IPC, type AppSettings, type Bookmark, type BrowserState, type Reminder } from '../shared/contracts.js'
import {
  isCloseTabShortcut,
  isNewTabShortcut,
  isReloadShortcut
} from '../shared/browser.js'
import { registerIpc } from './ipc.js'
import { BrowserTabManager } from './services/browser-tabs.js'
import { GlobalShortcutService } from './services/global-shortcut.js'
import { ReminderScheduler } from './services/reminder-scheduler.js'
import { StoreService } from './services/store.js'

const currentDirectory = dirname(fileURLToPath(import.meta.url))

let mainWindow: BrowserWindow | null = null
let browserTabs: BrowserTabManager | null = null
let store: StoreService
let reminderScheduler: ReminderScheduler
let shortcutService: GlobalShortcutService
let isQuitting = false
const isDevelopment = !app.isPackaged

function send(channel: string, value: unknown): void {
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.webContents.send(channel, value)
  }
}

function showWindow(view?: 'reminders' | 'browser' | 'settings'): void {
  if (!mainWindow || mainWindow.isDestroyed()) {
    createWindow()
  }
  mainWindow?.show()
  mainWindow?.focus()
  if (view) send(IPC.app.navigate, view)
}

function toggleWindow(): void {
  if (!mainWindow || mainWindow.isDestroyed()) {
    showWindow()
    return
  }
  if (mainWindow.isVisible() && mainWindow.isFocused()) {
    mainWindow.hide()
  } else {
    showWindow()
  }
}

function emitReminders(reminders: Reminder[]): void {
  send(IPC.reminders.changed, reminders)
}

function emitBookmarks(bookmarks: Bookmark[]): void {
  send(IPC.bookmarks.changed, bookmarks)
}

function emitSettings(settings: AppSettings): void {
  send(IPC.settings.changed, settings)
}

function emitBrowser(state: BrowserState): void {
  send(IPC.browser.changed, state)
}

function handleBrowserShortcut(event: Event, input: Input): void {
  if (isReloadShortcut(input)) {
    event.preventDefault()
    const state = browserTabs?.state()
    if (state?.visible && state.activeId) browserTabs?.reload(state.activeId)
    return
  }

  if (!browserTabs?.state().visible) return

  if (isCloseTabShortcut(input)) {
    event.preventDefault()
    const activeId = browserTabs.state().activeId
    if (activeId) browserTabs.close(activeId)
  } else if (isNewTabShortcut(input)) {
    event.preventDefault()
    browserTabs.create()
  }
}

function bindBrowserShortcuts(contents: WebContents): void {
  contents.on('before-input-event', handleBrowserShortcut)
}

function createWindow(): void {
  mainWindow = new BrowserWindow({
    width: 1100,
    height: 720,
    minWidth: 760,
    minHeight: 520,
    show: false,
    title: '提醒',
    titleBarStyle: 'hiddenInset',
    trafficLightPosition: { x: 16, y: 16 },
    backgroundColor: '#f3f2ee',
    vibrancy: process.platform === 'darwin' ? 'sidebar' : undefined,
    visualEffectState: 'active',
    webPreferences: {
      preload: join(currentDirectory, '../preload/index.cjs'),
      contextIsolation: true,
      sandbox: true,
      nodeIntegration: false,
      webviewTag: false,
      navigateOnDragDrop: false
    }
  })

  bindBrowserShortcuts(mainWindow.webContents)

  browserTabs = new BrowserTabManager({
    window: mainWindow,
    darkMode: store.settings.browserDarkMode,
    onChanged: emitBrowser,
    onWebContentsCreated: bindBrowserShortcuts
  })

  mainWindow.on('close', (event) => {
    if (process.platform === 'darwin' && !isQuitting) {
      event.preventDefault()
      mainWindow?.hide()
    }
  })

  mainWindow.on('closed', () => {
    browserTabs?.destroy()
    browserTabs = null
    mainWindow = null
  })

  mainWindow.once('ready-to-show', () => {
    mainWindow?.show()
  })

  if (isDevelopment && process.env.ELECTRON_RENDERER_URL) {
    void mainWindow.loadURL(process.env.ELECTRON_RENDERER_URL)
  } else {
    void mainWindow.loadFile(join(currentDirectory, '../renderer/index.html'))
  }
}

function createNotification(reminder: Reminder): void {
  const notification = new Notification({
    title: '提醒',
    body: reminder.content,
    silent: false
  })
  notification.on('click', () => showWindow('reminders'))
  notification.show()
}

app.whenReady().then(() => {
  app.setAppUserModelId('com.personal-assistant.app')
  app.setName('提醒')

  store = new StoreService(app.getPath('userData'))
  nativeTheme.themeSource = store.settings.themeMode
  reminderScheduler = new ReminderScheduler({
    store,
    notify: createNotification,
    onChanged: emitReminders
  })
  shortcutService = new GlobalShortcutService(store, toggleWindow)

  createWindow()
  const shortcutSettings = shortcutService.start()
  if (shortcutSettings.globalShortcut !== store.settings.globalShortcut) {
    emitSettings(shortcutSettings)
  }
  reminderScheduler.start()

  registerIpc({
    store,
    reminders: reminderScheduler,
    shortcuts: shortcutService,
    browser: () => {
      if (!browserTabs) throw new Error('Browser is not available')
      return browserTabs
    },
    emitBookmarks,
    emitSettings
  })

  powerMonitor.on('resume', () => reminderScheduler.reconcile())

  app.on('activate', () => showWindow())
})

app.on('before-quit', () => {
  isQuitting = true
})

app.on('will-quit', () => {
  reminderScheduler?.stop()
  shortcutService?.stop()
  browserTabs?.destroy()
})

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit()
})
