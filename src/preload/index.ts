import { contextBridge, ipcRenderer } from 'electron'
import { IPC } from '../shared/ipc-channels.js'
import {
  type AppInfo,
  type AppSettings,
  type AppView,
  type Bookmark,
  type BookmarkInput,
  type BrowserBounds,
  type BrowserState,
  type DesktopApi,
  type Reminder,
  type ReminderInput,
  type ReminderUpdate,
  type Result,
  type SettingsPatch,
  type Unsubscribe
} from '../shared/contracts.js'

function invoke<T>(channel: string, ...args: unknown[]): Promise<Result<T>> {
  return ipcRenderer.invoke(channel, ...args) as Promise<Result<T>>
}

function subscribe<T>(
  channel: string,
  parse: (value: unknown) => T,
  callback: (value: T) => void
): Unsubscribe {
  const listener = (_event: Electron.IpcRendererEvent, value: unknown): void => {
    callback(parse(value))
  }
  ipcRenderer.on(channel, listener)
  return () => ipcRenderer.removeListener(channel, listener)
}

const desktopApi: DesktopApi = {
  reminders: {
    list: () => invoke<Reminder[]>(IPC.reminders.list),
    create: (input: ReminderInput) => invoke<Reminder>(IPC.reminders.create, input),
    update: (id: string, updates: ReminderUpdate) => {
      return invoke<Reminder>(IPC.reminders.update, id, updates)
    },
    remove: (id: string) => invoke<Reminder[]>(IPC.reminders.remove, id),
    setEnabled: (id: string, enabled: boolean) => {
      return invoke<Reminder>(IPC.reminders.setEnabled, id, enabled)
    },
    subscribe: (callback) => subscribe(
      IPC.reminders.changed,
      (value) => value as Reminder[],
      callback
    )
  },
  bookmarks: {
    list: () => invoke<Bookmark[]>(IPC.bookmarks.list),
    save: (input: BookmarkInput) => invoke<Bookmark>(IPC.bookmarks.save, input),
    remove: (id: string) => invoke<Bookmark[]>(IPC.bookmarks.remove, id),
    subscribe: (callback) => subscribe(
      IPC.bookmarks.changed,
      (value) => value as Bookmark[],
      callback
    )
  },
  browser: {
    state: () => invoke<BrowserState>(IPC.browser.state),
    create: () => invoke<BrowserState>(IPC.browser.create),
    close: (id: string) => invoke<BrowserState>(IPC.browser.close, id),
    activate: (id: string) => invoke<BrowserState>(IPC.browser.activate, id),
    navigate: (id: string, url: string) => {
      return invoke<BrowserState>(IPC.browser.navigate, id, url)
    },
    back: (id: string) => invoke<BrowserState>(IPC.browser.back, id),
    forward: (id: string) => invoke<BrowserState>(IPC.browser.forward, id),
    reload: (id: string) => invoke<BrowserState>(IPC.browser.reload, id),
    home: (id: string) => invoke<BrowserState>(IPC.browser.home, id),
    setBounds: (bounds: BrowserBounds) => {
      return invoke<BrowserBounds>(IPC.browser.setBounds, bounds)
    },
    setVisible: (visible: boolean) => {
      return invoke<BrowserState>(IPC.browser.setVisible, visible)
    },
    subscribe: (callback) => subscribe(
      IPC.browser.changed,
      (value) => value as BrowserState,
      callback
    )
  },
  settings: {
    get: () => invoke<AppSettings>(IPC.settings.get),
    update: (updates: SettingsPatch) => {
      return invoke<AppSettings>(IPC.settings.update, updates)
    },
    updateShortcut: (accelerator: string) => {
      return invoke<AppSettings>(IPC.settings.updateShortcut, accelerator)
    },
    subscribe: (callback) => subscribe(
      IPC.settings.changed,
      (value) => value as AppSettings,
      callback
    )
  },
  app: {
    getInfo: () => invoke<AppInfo>(IPC.app.info),
    subscribeNavigation: (callback) => subscribe<AppView>(
      IPC.app.navigate,
      (value) => value as AppView,
      callback
    )
  }
}

contextBridge.exposeInMainWorld('desktop', desktopApi)
