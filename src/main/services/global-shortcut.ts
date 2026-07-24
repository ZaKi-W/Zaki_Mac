import { globalShortcut } from 'electron'
import type { AppSettings } from '../../shared/contracts.js'
import { DEFAULT_SHORTCUT } from '../../shared/shortcut.js'
import type { StoreService } from './store.js'

export class GlobalShortcutService {
  private active = DEFAULT_SHORTCUT

  constructor(
    private readonly store: StoreService,
    private readonly toggleWindow: () => void
  ) {}

  start(): AppSettings {
    const saved = this.store.settings.globalShortcut
    if (this.register(saved)) return this.store.settings

    this.register(DEFAULT_SHORTCUT)
    return this.store.setSettings({
      ...this.store.settings,
      globalShortcut: DEFAULT_SHORTCUT
    })
  }

  update(accelerator: string): AppSettings {
    const previous = this.active
    globalShortcut.unregisterAll()

    if (!this.register(accelerator.trim())) {
      this.register(previous)
      throw new Error('Shortcut is invalid or already in use')
    }

    return this.store.setSettings({
      ...this.store.settings,
      globalShortcut: accelerator.trim()
    })
  }

  stop(): void {
    globalShortcut.unregisterAll()
  }

  private register(accelerator: string): boolean {
    try {
      const registered = globalShortcut.register(accelerator, this.toggleWindow)
      if (registered) this.active = accelerator
      return registered
    } catch (error) {
      console.error('Unable to register global shortcut:', error)
      return false
    }
  }
}
