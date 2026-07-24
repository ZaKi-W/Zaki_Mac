import { randomUUID } from 'node:crypto'
import { app, ipcMain, nativeTheme } from 'electron'
import { z } from 'zod'
import {
  IPC,
  bookmarkInputSchema,
  browserBoundsSchema,
  reminderInputSchema,
  reminderUpdateSchema,
  settingsPatchSchema,
  type AppInfo,
  type AppSettings,
  type Bookmark,
  type Result
} from '../shared/contracts.js'
import { isSafeWebUrl, normalizeUrl } from '../shared/browser.js'
import type { BrowserTabManager } from './services/browser-tabs.js'
import type { GlobalShortcutService } from './services/global-shortcut.js'
import type { ReminderScheduler } from './services/reminder-scheduler.js'
import type { StoreService } from './services/store.js'

type IpcDependencies = {
  store: StoreService
  reminders: ReminderScheduler
  shortcuts: GlobalShortcutService
  browser: () => BrowserTabManager
  emitBookmarks: (bookmarks: Bookmark[]) => void
  emitSettings: (settings: AppSettings) => void
}

const idSchema = z.string().min(1)

function success<T>(data: T): Result<T> {
  return { ok: true, data }
}

function failure(error: unknown): Result<never> {
  return {
    ok: false,
    error: {
      code: 'OPERATION_FAILED',
      message: error instanceof Error ? error.message : 'Unknown error'
    }
  }
}

function register<T>(
  channel: string,
  handler: (...args: unknown[]) => T | Promise<T>
): void {
  ipcMain.handle(channel, async (_event, ...args: unknown[]) => {
    try {
      return success(await handler(...args))
    } catch (error) {
      return failure(error)
    }
  })
}

export function registerIpc(deps: IpcDependencies): void {
  register(IPC.reminders.list, () => deps.reminders.list())
  register(IPC.reminders.create, (value) => {
    return deps.reminders.create(reminderInputSchema.parse(value))
  })
  register(IPC.reminders.update, (id, updates) => {
    return deps.reminders.update(
      idSchema.parse(id),
      reminderUpdateSchema.parse(updates)
    )
  })
  register(IPC.reminders.remove, (id) => {
    return deps.reminders.remove(idSchema.parse(id))
  })
  register(IPC.reminders.setEnabled, (id, enabled) => {
    return deps.reminders.setEnabled(
      idSchema.parse(id),
      z.boolean().parse(enabled)
    )
  })

  register(IPC.bookmarks.list, () => deps.store.bookmarks)
  register(IPC.bookmarks.save, (value) => {
    const input = bookmarkInputSchema.parse(value)
    if (!isSafeWebUrl(input.url)) throw new Error('Bookmark URL is not allowed')
    const current = deps.store.bookmarks
    const normalized = normalizeUrl(input.url)
    const duplicate = current.find(
      (bookmark) => normalizeUrl(bookmark.url) === normalized
    )
    if (duplicate) return duplicate

    const bookmark: Bookmark = {
      id: randomUUID(),
      title: input.title,
      url: input.url,
      createdAt: new Date().toISOString()
    }
    const bookmarks = deps.store.setBookmarks([...current, bookmark])
    deps.emitBookmarks(bookmarks)
    return bookmark
  })
  register(IPC.bookmarks.remove, (value) => {
    const id = idSchema.parse(value)
    const bookmarks = deps.store.setBookmarks(
      deps.store.bookmarks.filter((bookmark) => bookmark.id !== id)
    )
    deps.emitBookmarks(bookmarks)
    return bookmarks
  })

  register(IPC.browser.state, () => deps.browser().state())
  register(IPC.browser.create, () => deps.browser().create())
  register(IPC.browser.close, (id) => deps.browser().close(idSchema.parse(id)))
  register(
    IPC.browser.activate,
    (id) => deps.browser().activate(idSchema.parse(id))
  )
  register(IPC.browser.navigate, (id, url) => {
    return deps.browser().navigate(
      idSchema.parse(id),
      z.string().parse(url)
    )
  })
  register(IPC.browser.back, (id) => deps.browser().back(idSchema.parse(id)))
  register(
    IPC.browser.forward,
    (id) => deps.browser().forward(idSchema.parse(id))
  )
  register(
    IPC.browser.reload,
    (id) => deps.browser().reload(idSchema.parse(id))
  )
  register(IPC.browser.home, (id) => deps.browser().home(idSchema.parse(id)))
  register(IPC.browser.setBounds, (value) => {
    return deps.browser().setBounds(browserBoundsSchema.parse(value))
  })
  register(IPC.browser.setVisible, (value) => {
    return deps.browser().setVisible(z.boolean().parse(value))
  })

  register(IPC.settings.get, () => deps.store.settings)
  register(IPC.settings.update, (value) => {
    const updates = settingsPatchSchema.parse(value)
    if (updates.globalShortcut !== undefined) {
      throw new Error('Use the shortcut update endpoint')
    }
    const settings = deps.store.setSettings({
      ...deps.store.settings,
      ...updates
    })
    nativeTheme.themeSource = settings.themeMode
    deps.browser().setDarkMode(settings.browserDarkMode)
    deps.emitSettings(settings)
    return settings
  })
  register(IPC.settings.updateShortcut, (value) => {
    const accelerator = z.string().trim().min(3).max(80).parse(value)
    const settings = deps.shortcuts.update(accelerator)
    deps.emitSettings(settings)
    return settings
  })

  register(IPC.app.info, () => {
    const info: AppInfo = {
      name: app.getName(),
      version: app.getVersion(),
      platform: process.platform
    }
    return info
  })
}
