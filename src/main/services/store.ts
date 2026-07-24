import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import {
  persistedStateSchema,
  type AppSettings,
  type Bookmark,
  type PersistedState,
  type Reminder
} from '../../shared/contracts.js'
import { DEFAULT_SHORTCUT } from '../../shared/shortcut.js'

const DEFAULT_STATE: PersistedState = {
  version: 2,
  reminders: [],
  bookmarks: [],
  settings: {
    language: 'zh',
    themeMode: 'system',
    globalShortcut: DEFAULT_SHORTCUT,
    browserDarkMode: false
  }
}

export class StoreService {
  private readonly filePath: string
  private state: PersistedState

  constructor(userDataPath: string) {
    this.filePath = join(userDataPath, 'assistant-v2', 'state.json')
    this.state = this.read()
  }

  get reminders(): Reminder[] {
    return structuredClone(this.state.reminders)
  }

  get bookmarks(): Bookmark[] {
    return structuredClone(this.state.bookmarks)
  }

  get settings(): AppSettings {
    return structuredClone(this.state.settings)
  }

  setReminders(reminders: Reminder[]): Reminder[] {
    this.state = { ...this.state, reminders: structuredClone(reminders) }
    this.persist()
    return this.reminders
  }

  setBookmarks(bookmarks: Bookmark[]): Bookmark[] {
    this.state = { ...this.state, bookmarks: structuredClone(bookmarks) }
    this.persist()
    return this.bookmarks
  }

  setSettings(settings: AppSettings): AppSettings {
    this.state = { ...this.state, settings: structuredClone(settings) }
    this.persist()
    return this.settings
  }

  private read(): PersistedState {
    if (!existsSync(this.filePath)) return structuredClone(DEFAULT_STATE)

    try {
      const parsed: unknown = JSON.parse(readFileSync(this.filePath, 'utf8'))
      const result = persistedStateSchema.safeParse(parsed)
      return result.success ? result.data : structuredClone(DEFAULT_STATE)
    } catch (error) {
      console.error('Unable to read assistant-v2 store:', error)
      return structuredClone(DEFAULT_STATE)
    }
  }

  private persist(): void {
    const directory = dirname(this.filePath)
    mkdirSync(directory, { recursive: true })
    const temporaryPath = `${this.filePath}.tmp`
    writeFileSync(temporaryPath, JSON.stringify(this.state, null, 2), 'utf8')
    renameSync(temporaryPath, this.filePath)
  }
}
