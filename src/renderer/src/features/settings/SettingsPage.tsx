import { useEffect, useState } from 'react'
import {
  AppWindow,
  Check,
  Globe2,
  Keyboard,
  MonitorCog,
  Moon,
  RotateCcw,
  Sun
} from 'lucide-react'
import type {
  AppInfo,
  AppSettings,
  Language,
  SettingsPatch,
  ThemeMode
} from '../../../../shared/contracts'
import {
  DEFAULT_SHORTCUT,
  formatAccelerator,
  keyboardEventToAccelerator
} from '../../../../shared/shortcut'
import { useI18n } from '../../i18n'

type SettingsPageProps = {
  settings: AppSettings
  onSettingsChange: (patch: SettingsPatch) => Promise<AppSettings>
}

export function SettingsPage({
  settings,
  onSettingsChange
}: SettingsPageProps): React.JSX.Element {
  const { t } = useI18n()
  const [info, setInfo] = useState<AppInfo | null>(null)
  const [shortcutDraft, setShortcutDraft] = useState(settings.globalShortcut)
  const [status, setStatus] = useState<'saved' | 'error' | null>(null)

  useEffect(() => {
    void window.desktop.app.getInfo().then((result) => {
      if (result.ok) setInfo(result.data)
    })
  }, [])

  const update = async (patch: SettingsPatch): Promise<void> => {
    setStatus(null)
    try {
      await onSettingsChange(patch)
      setStatus('saved')
    } catch {
      setStatus('error')
    }
  }

  const saveShortcut = async (accelerator: string): Promise<void> => {
    setStatus(null)
    const result = await window.desktop.settings.updateShortcut(accelerator)
    if (result.ok) {
      setShortcutDraft(result.data.globalShortcut)
      setStatus('saved')
    } else {
      setShortcutDraft(settings.globalShortcut)
      setStatus('error')
    }
  }

  const platform = info?.platform ?? 'darwin'

  return (
    <section className="page settings-page">
      <header className="page-header settings-header">
        <div>
          <h1>{t('settings.title')}</h1>
        </div>
        {status && (
          <div className="save-status" data-error={status === 'error'} role="status">
            {status === 'saved' && <Check size={13} />}
            {status === 'saved' ? t('settings.saved') : t('settings.unavailable')}
          </div>
        )}
      </header>

      <div className="settings-list">
        <SettingRow
          icon={<MonitorCog size={17} />}
          title={t('settings.appearance')}
          body={t('settings.appearanceBody')}
        >
          <div className="segmented-control settings-segment">
            <ThemeButton
              mode="system"
              active={settings.themeMode === 'system'}
              label={t('settings.system')}
              icon={<MonitorCog size={14} />}
              onSelect={(mode) => void update({ themeMode: mode })}
            />
            <ThemeButton
              mode="light"
              active={settings.themeMode === 'light'}
              label={t('settings.light')}
              icon={<Sun size={14} />}
              onSelect={(mode) => void update({ themeMode: mode })}
            />
            <ThemeButton
              mode="dark"
              active={settings.themeMode === 'dark'}
              label={t('settings.dark')}
              icon={<Moon size={14} />}
              onSelect={(mode) => void update({ themeMode: mode })}
            />
          </div>
        </SettingRow>

        <SettingRow
          icon={<Globe2 size={17} />}
          title={t('settings.language')}
          body={t('settings.languageBody')}
        >
          <div className="segmented-control compact-segment">
            {([
              ['zh', '中文'],
              ['en', 'English']
            ] as const).map(([language, label]) => (
              <button
                type="button"
                key={language}
                data-active={settings.language === language}
                onClick={() => void update({ language: language as Language })}
              >
                {label}
              </button>
            ))}
          </div>
        </SettingRow>

        <SettingRow
          icon={<Keyboard size={17} />}
          title={t('settings.shortcut')}
          body={t('settings.shortcutBody')}
          vertical
        >
          <div className="shortcut-editor">
            <input
              readOnly
              value={formatAccelerator(shortcutDraft, platform)}
              aria-label={t('settings.shortcut')}
              onFocus={(event) => event.target.select()}
              onKeyDown={(event) => {
                event.preventDefault()
                event.stopPropagation()
                const accelerator = keyboardEventToAccelerator(event)
                if (accelerator) setShortcutDraft(accelerator)
              }}
            />
            <button
              type="button"
              className="button primary"
              disabled={shortcutDraft === settings.globalShortcut}
              onClick={() => void saveShortcut(shortcutDraft)}
            >
              {t('common.save')}
            </button>
            <button
              type="button"
              className="button secondary"
              onClick={() => void saveShortcut(DEFAULT_SHORTCUT)}
            >
              <RotateCcw size={14} />
              {t('settings.reset')}
            </button>
          </div>
          <span className="field-hint">{t('settings.shortcutHint')}</span>
        </SettingRow>

        <SettingRow
          icon={<Moon size={17} />}
          title={t('settings.browser')}
          body={t('settings.browserBody')}
        >
          <label className="toggle-control">
            <input
              type="checkbox"
              checked={settings.browserDarkMode}
              onChange={(event) => {
                void update({ browserDarkMode: event.target.checked })
              }}
            />
            <span />
          </label>
        </SettingRow>

        <SettingRow
          icon={<AppWindow size={17} />}
          title={t('settings.about')}
          body={info ? `${info.name} · ${info.platform}` : '—'}
        >
          <span className="version-badge">
            {t('settings.version')} {info?.version ?? '—'}
          </span>
        </SettingRow>
      </div>
    </section>
  )
}

function SettingRow({
  icon,
  title,
  body,
  vertical = false,
  children
}: {
  icon: React.ReactNode
  title: string
  body: string
  vertical?: boolean
  children: React.ReactNode
}): React.JSX.Element {
  return (
    <section className="setting-row" data-vertical={vertical}>
      <div className="setting-icon">{icon}</div>
      <div className="setting-copy">
        <h2>{title}</h2>
        <p>{body}</p>
      </div>
      <div className="setting-control">{children}</div>
    </section>
  )
}

function ThemeButton({
  mode,
  active,
  label,
  icon,
  onSelect
}: {
  mode: ThemeMode
  active: boolean
  label: string
  icon: React.ReactNode
  onSelect: (mode: ThemeMode) => void
}): React.JSX.Element {
  return (
    <button
      type="button"
      data-active={active}
      onClick={() => onSelect(mode)}
    >
      {icon}
      {label}
    </button>
  )
}
