import { useEffect, useState } from 'react'
import type {
  AppSettings,
  AppView,
  Bookmark,
  Reminder,
  Result,
  SettingsPatch
} from '../../shared/contracts'
import { DEFAULT_SHORTCUT } from '../../shared/shortcut'
import { AppShell } from './components/AppShell'
import { BrowserPage } from './features/browser/BrowserPage'
import { ReminderPage } from './features/reminders/ReminderPage'
import { SettingsPage } from './features/settings/SettingsPage'
import { I18nProvider } from './i18n'

const DEFAULT_SETTINGS: AppSettings = {
  language: 'zh',
  themeMode: 'system',
  globalShortcut: DEFAULT_SHORTCUT,
  browserDarkMode: false
}

function dataOrThrow<T>(result: Result<T>): T {
  if (!result.ok) throw new Error(result.error.message)
  return result.data
}

export function App(): React.JSX.Element {
  const [view, setView] = useState<AppView>('reminders')
  const [settings, setSettings] = useState(DEFAULT_SETTINGS)
  const [reminders, setReminders] = useState<Reminder[]>([])
  const [bookmarks, setBookmarks] = useState<Bookmark[]>([])
  const [ready, setReady] = useState(false)
  const [startupError, setStartupError] = useState<string | null>(null)

  useEffect(() => {
    const unsubscribers = [
      window.desktop.reminders.subscribe(setReminders),
      window.desktop.bookmarks.subscribe(setBookmarks),
      window.desktop.settings.subscribe(setSettings),
      window.desktop.app.subscribeNavigation(setView)
    ]

    void Promise.all([
      window.desktop.reminders.list(),
      window.desktop.bookmarks.list(),
      window.desktop.settings.get()
    ]).then(([reminderResult, bookmarkResult, settingsResult]) => {
      setReminders(dataOrThrow(reminderResult))
      setBookmarks(dataOrThrow(bookmarkResult))
      setSettings(dataOrThrow(settingsResult))
      setReady(true)
    }).catch((error: unknown) => {
      setStartupError(error instanceof Error ? error.message : 'Startup failed')
      setReady(true)
    })

    return () => {
      for (const unsubscribe of unsubscribers) unsubscribe()
    }
  }, [])

  useEffect(() => {
    document.documentElement.dataset.theme = settings.themeMode
    document.documentElement.lang = settings.language
  }, [settings])

  useEffect(() => {
    void window.desktop.browser.setVisible(view === 'browser')
  }, [view])

  const updateSettings = async (patch: SettingsPatch): Promise<AppSettings> => {
    const next = dataOrThrow(await window.desktop.settings.update(patch))
    setSettings(next)
    return next
  }

  if (!ready) {
    return (
      <div className="startup-screen">
        <div className="startup-mark" />
        <span>正在加载…</span>
      </div>
    )
  }

  return (
    <I18nProvider language={settings.language}>
      <AppShell view={view} reminders={reminders} onNavigate={setView}>
        {startupError && (
          <div className="global-error" role="alert">{startupError}</div>
        )}
        {view === 'reminders' && (
          <ReminderPage reminders={reminders} onChange={setReminders} />
        )}
        {view === 'browser' && (
          <BrowserPage
            bookmarks={bookmarks}
            onBookmarksChange={setBookmarks}
            settings={settings}
            onSettingsChange={updateSettings}
          />
        )}
        {view === 'settings' && (
          <SettingsPage
            settings={settings}
            onSettingsChange={updateSettings}
          />
        )}
      </AppShell>
    </I18nProvider>
  )
}
