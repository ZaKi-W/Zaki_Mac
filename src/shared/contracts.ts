import { z } from 'zod'

export const languageSchema = z.enum(['zh', 'en'])
export type Language = z.infer<typeof languageSchema>

export const themeModeSchema = z.enum(['system', 'light', 'dark'])
export type ThemeMode = z.infer<typeof themeModeSchema>

export const appViewSchema = z.enum(['reminders', 'browser', 'settings'])
export type AppView = z.infer<typeof appViewSchema>

export const reminderSchema = z.object({
  id: z.string().min(1),
  content: z.string().min(1).max(240),
  intervalSeconds: z.number().int().min(1).max(86_399),
  repeat: z.boolean(),
  enabled: z.boolean(),
  createdAt: z.string().datetime(),
  nextTriggerAt: z.string().datetime().nullable(),
  completedAt: z.string().datetime().nullable()
})
export type Reminder = z.infer<typeof reminderSchema>

export const reminderInputSchema = z.object({
  content: z.string().trim().min(1).max(240),
  intervalSeconds: z.number().int().min(1).max(86_399),
  repeat: z.boolean(),
  enabled: z.boolean()
})
export type ReminderInput = z.infer<typeof reminderInputSchema>

export const reminderUpdateSchema = reminderInputSchema.partial()
export type ReminderUpdate = z.infer<typeof reminderUpdateSchema>

export const bookmarkSchema = z.object({
  id: z.string().min(1),
  title: z.string().trim().min(1).max(160),
  url: z.string().url(),
  createdAt: z.string().datetime()
})
export type Bookmark = z.infer<typeof bookmarkSchema>

export const bookmarkInputSchema = bookmarkSchema.pick({
  title: true,
  url: true
})
export type BookmarkInput = z.infer<typeof bookmarkInputSchema>

export const settingsSchema = z.object({
  language: languageSchema,
  themeMode: themeModeSchema,
  globalShortcut: z.string().min(3).max(80),
  browserDarkMode: z.boolean()
})
export type AppSettings = z.infer<typeof settingsSchema>

export const settingsPatchSchema = settingsSchema.partial()
export type SettingsPatch = z.infer<typeof settingsPatchSchema>

export const persistedStateSchema = z.object({
  version: z.literal(2),
  reminders: z.array(reminderSchema),
  bookmarks: z.array(bookmarkSchema),
  settings: settingsSchema
})
export type PersistedState = z.infer<typeof persistedStateSchema>

export const browserBoundsSchema = z.object({
  x: z.number().int().min(0),
  y: z.number().int().min(0),
  width: z.number().int().min(0),
  height: z.number().int().min(0)
})
export type BrowserBounds = z.infer<typeof browserBoundsSchema>

export const browserTabSchema = z.object({
  id: z.string().min(1),
  url: z.string(),
  title: z.string(),
  isHome: z.boolean(),
  loading: z.boolean(),
  canGoBack: z.boolean(),
  canGoForward: z.boolean()
})
export type BrowserTab = z.infer<typeof browserTabSchema>

export const browserStateSchema = z.object({
  tabs: z.array(browserTabSchema),
  activeId: z.string().nullable(),
  visible: z.boolean()
})
export type BrowserState = z.infer<typeof browserStateSchema>

export const safeWebUrlSchema = z.string().url().refine((value) => {
  const protocol = new URL(value).protocol
  return protocol === 'http:' || protocol === 'https:'
}, 'Only HTTP and HTTPS URLs are allowed')

export type AppError = {
  code: string
  message: string
}

export type Result<T> =
  | { ok: true; data: T }
  | { ok: false; error: AppError }

export type AppInfo = {
  name: string
  version: string
  platform: string
}

export type Unsubscribe = () => void

export type DesktopApi = {
  reminders: {
    list: () => Promise<Result<Reminder[]>>
    create: (input: ReminderInput) => Promise<Result<Reminder>>
    update: (id: string, updates: ReminderUpdate) => Promise<Result<Reminder>>
    remove: (id: string) => Promise<Result<Reminder[]>>
    setEnabled: (id: string, enabled: boolean) => Promise<Result<Reminder>>
    subscribe: (callback: (reminders: Reminder[]) => void) => Unsubscribe
  }
  bookmarks: {
    list: () => Promise<Result<Bookmark[]>>
    save: (input: BookmarkInput) => Promise<Result<Bookmark>>
    remove: (id: string) => Promise<Result<Bookmark[]>>
    subscribe: (callback: (bookmarks: Bookmark[]) => void) => Unsubscribe
  }
  browser: {
    state: () => Promise<Result<BrowserState>>
    create: () => Promise<Result<BrowserState>>
    close: (id: string) => Promise<Result<BrowserState>>
    activate: (id: string) => Promise<Result<BrowserState>>
    navigate: (id: string, url: string) => Promise<Result<BrowserState>>
    back: (id: string) => Promise<Result<BrowserState>>
    forward: (id: string) => Promise<Result<BrowserState>>
    reload: (id: string) => Promise<Result<BrowserState>>
    home: (id: string) => Promise<Result<BrowserState>>
    setBounds: (bounds: BrowserBounds) => Promise<Result<BrowserBounds>>
    setVisible: (visible: boolean) => Promise<Result<BrowserState>>
    subscribe: (callback: (state: BrowserState) => void) => Unsubscribe
  }
  settings: {
    get: () => Promise<Result<AppSettings>>
    update: (updates: SettingsPatch) => Promise<Result<AppSettings>>
    updateShortcut: (accelerator: string) => Promise<Result<AppSettings>>
    subscribe: (callback: (settings: AppSettings) => void) => Unsubscribe
  }
  app: {
    getInfo: () => Promise<Result<AppInfo>>
    subscribeNavigation: (callback: (view: AppView) => void) => Unsubscribe
  }
}

export { IPC } from './ipc-channels.js'
