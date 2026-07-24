import {
  BellRing,
  ChevronsLeftRight,
  Globe2,
  Settings2
} from 'lucide-react'
import type { AppView, Reminder } from '../../../shared/contracts'
import { useI18n } from '../i18n'

type AppShellProps = {
  view: AppView
  reminders: Reminder[]
  onNavigate: (view: AppView) => void
  children: React.ReactNode
}

const navigation = [
  { id: 'reminders', icon: BellRing, label: 'nav.reminders' },
  { id: 'browser', icon: Globe2, label: 'nav.browser' }
] as const

export function AppShell({
  view,
  reminders,
  onNavigate,
  children
}: AppShellProps): React.JSX.Element {
  const { t } = useI18n()
  const activeCount = reminders.filter((reminder) => reminder.enabled).length

  return (
    <div className="app-shell" data-view={view}>
      <aside className="sidebar">
        <div className="sidebar-drag-zone" aria-hidden="true" />
        <div className="brand-lockup">
          <div className="brand-mark">
            <BellRing size={15} strokeWidth={2.2} />
          </div>
          <div className="brand-copy">
            <strong>{t('app.name')}</strong>
          </div>
        </div>

        <nav className="primary-navigation" aria-label="Primary">
          {navigation.map(({ id, icon: Icon, label }) => (
            <button
              key={id}
              type="button"
              className="navigation-item"
              data-active={view === id}
              onClick={() => onNavigate(id)}
              aria-current={view === id ? 'page' : undefined}
              title={t(label)}
            >
              <Icon size={17} strokeWidth={1.9} />
              <span className="navigation-label">{t(label)}</span>
              {id === 'reminders' && activeCount > 0 && (
                <span className="navigation-count">{activeCount}</span>
              )}
            </button>
          ))}
        </nav>

        <div className="sidebar-status">
          <span className="status-pulse" />
          <span className="navigation-label">
            {activeCount} {t('nav.enabled')}
          </span>
        </div>

        <button
          type="button"
          className="navigation-item settings-navigation"
          data-active={view === 'settings'}
          onClick={() => onNavigate('settings')}
          aria-current={view === 'settings' ? 'page' : undefined}
          title={t('nav.settings')}
        >
          <Settings2 size={17} strokeWidth={1.9} />
          <span className="navigation-label">{t('nav.settings')}</span>
        </button>

        {view === 'browser' && (
          <div className="collapsed-indicator" aria-hidden="true">
            <ChevronsLeftRight size={13} />
          </div>
        )}
      </aside>
      <main className="workspace">{children}</main>
    </div>
  )
}
