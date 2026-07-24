import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import {
  ArrowLeft,
  ArrowRight,
  BookOpenText,
  ChevronRight,
  CirclePlay,
  Github,
  Globe2,
  Home,
  LoaderCircle,
  MessageCircle,
  Moon,
  Plus,
  RefreshCw,
  Search,
  Star,
  Sun,
  Video,
  X
} from 'lucide-react'
import type {
  AppSettings,
  Bookmark,
  BrowserState,
  BrowserTab,
  Result,
  SettingsPatch
} from '../../../../shared/contracts'
import { normalizeUrl, resolveUrl } from '../../../../shared/browser'
import { useI18n } from '../../i18n'

const EMPTY_STATE: BrowserState = {
  tabs: [],
  activeId: null,
  visible: false
}

const quickSites = [
  { name: '百度', url: 'https://www.baidu.com', icon: Search, tone: 'blue' },
  { name: 'Google', url: 'https://www.google.com', icon: Globe2, tone: 'green' },
  { name: 'GitHub', url: 'https://github.com', icon: Github, tone: 'graphite' },
  { name: '哔哩哔哩', url: 'https://www.bilibili.com', icon: CirclePlay, tone: 'pink' },
  { name: '知乎', url: 'https://www.zhihu.com', icon: BookOpenText, tone: 'blue' },
  { name: '微博', url: 'https://weibo.com', icon: MessageCircle, tone: 'red' },
  { name: 'YouTube', url: 'https://www.youtube.com', icon: Video, tone: 'red' },
  { name: 'X', url: 'https://x.com', icon: X, tone: 'graphite' }
] as const

type BrowserPageProps = {
  bookmarks: Bookmark[]
  onBookmarksChange: (bookmarks: Bookmark[]) => void
  settings: AppSettings
  onSettingsChange: (patch: SettingsPatch) => Promise<AppSettings>
}

function unwrap<T>(result: Result<T>): T {
  if (!result.ok) throw new Error(result.error.message)
  return result.data
}

export function BrowserPage({
  bookmarks,
  onBookmarksChange,
  settings,
  onSettingsChange
}: BrowserPageProps): React.JSX.Element {
  const { t, language } = useI18n()
  const [state, setState] = useState(EMPTY_STATE)
  const [address, setAddress] = useState('')
  const [error, setError] = useState<string | null>(null)
  const addressRef = useRef<HTMLInputElement>(null)
  const hostRef = useRef<HTMLDivElement>(null)

  const activeTab = state.tabs.find((tab) => tab.id === state.activeId) ?? null

  const applyState = useCallback((next: BrowserState): void => {
    setState(next)
    const nextActive = next.tabs.find((tab) => tab.id === next.activeId)
    if (document.activeElement !== addressRef.current) {
      setAddress(nextActive?.isHome ? '' : nextActive?.url ?? '')
    }
  }, [])

  useEffect(() => {
    const unsubscribe = window.desktop.browser.subscribe(applyState)
    void window.desktop.browser.state().then((result) => {
      applyState(unwrap(result))
    }).catch((caught: unknown) => {
      setError(caught instanceof Error ? caught.message : t('common.error'))
    })
    return unsubscribe
  }, [applyState, t])

  useEffect(() => {
    const host = hostRef.current
    if (!host) return

    let frame = 0
    const updateBounds = (): void => {
      cancelAnimationFrame(frame)
      frame = requestAnimationFrame(() => {
        const rect = host.getBoundingClientRect()
        void window.desktop.browser.setBounds({
          x: Math.round(rect.x),
          y: Math.round(rect.y),
          width: Math.max(0, Math.round(rect.width)),
          height: Math.max(0, Math.round(rect.height))
        })
      })
    }

    const observer = new ResizeObserver(updateBounds)
    observer.observe(host)
    window.addEventListener('resize', updateBounds)
    updateBounds()
    return () => {
      cancelAnimationFrame(frame)
      observer.disconnect()
      window.removeEventListener('resize', updateBounds)
    }
  }, [])

  const isBookmarked = useMemo(() => {
    if (!activeTab || activeTab.isHome) return false
    const activeUrl = normalizeUrl(activeTab.url)
    return bookmarks.some((bookmark) => normalizeUrl(bookmark.url) === activeUrl)
  }, [activeTab, bookmarks])

  const run = async (
    promise: Promise<Result<BrowserState>>
  ): Promise<BrowserState | null> => {
    setError(null)
    try {
      const next = unwrap(await promise)
      applyState(next)
      return next
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : t('common.error'))
      return null
    }
  }

  const navigate = async (value: string): Promise<void> => {
    if (!activeTab) return
    const url = resolveUrl(value, language)
    if (!url) return
    await run(window.desktop.browser.navigate(activeTab.id, url))
    addressRef.current?.blur()
  }

  const createTab = async (): Promise<void> => {
    const next = await run(window.desktop.browser.create())
    if (next) requestAnimationFrame(() => addressRef.current?.focus())
  }

  const toggleBookmark = async (): Promise<void> => {
    if (!activeTab || activeTab.isHome) return
    const normalized = normalizeUrl(activeTab.url)
    const existing = bookmarks.find(
      (bookmark) => normalizeUrl(bookmark.url) === normalized
    )
    try {
      if (existing) {
        onBookmarksChange(
          unwrap(await window.desktop.bookmarks.remove(existing.id))
        )
      } else {
        const created = unwrap(await window.desktop.bookmarks.save({
          title: activeTab.title || new URL(activeTab.url).hostname,
          url: activeTab.url
        }))
        onBookmarksChange([...bookmarks, created])
      }
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : t('common.error'))
    }
  }

  return (
    <section className="browser-page">
      <header className="browser-toolbar">
        <div className="browser-history-controls">
          <ToolbarButton
            label={t('browser.back')}
            disabled={!activeTab?.canGoBack}
            onClick={() => activeTab && void run(window.desktop.browser.back(activeTab.id))}
          >
            <ArrowLeft size={15} />
          </ToolbarButton>
          <ToolbarButton
            label={t('browser.forward')}
            disabled={!activeTab?.canGoForward}
            onClick={() => activeTab && void run(window.desktop.browser.forward(activeTab.id))}
          >
            <ArrowRight size={15} />
          </ToolbarButton>
          <ToolbarButton
            label={t('browser.reload')}
            onClick={() => activeTab && void run(window.desktop.browser.reload(activeTab.id))}
          >
            {activeTab?.loading
              ? <LoaderCircle size={15} className="spin" />
              : <RefreshCw size={15} />}
          </ToolbarButton>
          <ToolbarButton
            label={t('browser.home')}
            onClick={() => activeTab && void run(window.desktop.browser.home(activeTab.id))}
          >
            <Home size={15} />
          </ToolbarButton>
        </div>

        <form
          className="address-field"
          onSubmit={(event) => {
            event.preventDefault()
            void navigate(address)
          }}
        >
          <Search size={14} />
          <input
            ref={addressRef}
            value={address}
            onChange={(event) => setAddress(event.target.value)}
            onFocus={(event) => event.target.select()}
            placeholder={t('browser.address')}
            aria-label={t('browser.address')}
          />
          {activeTab?.loading && <span className="loading-dot" />}
        </form>

        <div className="browser-page-actions">
          <ToolbarButton
            label={isBookmarked ? t('browser.unbookmark') : t('browser.bookmark')}
            active={isBookmarked}
            onClick={() => void toggleBookmark()}
          >
            <Star size={15} fill={isBookmarked ? 'currentColor' : 'none'} />
          </ToolbarButton>
          <ToolbarButton
            label={settings.browserDarkMode ? t('browser.light') : t('browser.dark')}
            active={settings.browserDarkMode}
            onClick={() => {
              void onSettingsChange({
                browserDarkMode: !settings.browserDarkMode
              })
            }}
          >
            {settings.browserDarkMode ? <Sun size={15} /> : <Moon size={15} />}
          </ToolbarButton>
        </div>
      </header>

      <div className="browser-tabs" role="tablist" aria-label={t('browser.newTab')}>
        {state.tabs.map((tab) => (
          <div
            key={tab.id}
            className="browser-tab"
            data-active={tab.id === state.activeId}
            role="tab"
            aria-selected={tab.id === state.activeId}
            tabIndex={tab.id === state.activeId ? 0 : -1}
            onClick={() => void run(window.desktop.browser.activate(tab.id))}
            onKeyDown={(event) => {
              if (event.key === 'Enter' || event.key === ' ') {
                void run(window.desktop.browser.activate(tab.id))
              }
            }}
          >
            {tab.loading ? <LoaderCircle size={12} className="spin" /> : <Globe2 size={12} />}
            <span>{tabTitle(tab, t('browser.newTab'))}</span>
            <button
              type="button"
              aria-label={t('common.delete')}
              onClick={(event) => {
                event.stopPropagation()
                void run(window.desktop.browser.close(tab.id))
              }}
            >
              <X size={12} />
            </button>
          </div>
        ))}
        <button
          type="button"
          className="new-tab-button"
          onClick={() => void createTab()}
          aria-label={t('browser.newTab')}
        >
          <Plus size={15} />
        </button>
      </div>

      <div className="bookmark-bar" data-empty={bookmarks.length === 0}>
        {bookmarks.map((bookmark) => (
          <div className="bookmark-item" key={bookmark.id}>
            <button type="button" onClick={() => void navigate(bookmark.url)}>
              <Globe2 size={12} />
              <span>{bookmark.title}</span>
            </button>
            <button
              type="button"
              className="bookmark-remove"
              aria-label={t('common.delete')}
              onClick={() => {
                void window.desktop.bookmarks.remove(bookmark.id)
                  .then((result) => onBookmarksChange(unwrap(result)))
                  .catch((caught: unknown) => {
                    setError(caught instanceof Error ? caught.message : t('common.error'))
                  })
              }}
            >
              <X size={11} />
            </button>
          </div>
        ))}
      </div>

      {error && <div className="browser-error" role="alert">{error}</div>}

      <div ref={hostRef} className="browser-host">
        {activeTab?.isHome && (
          <QuickAccess onNavigate={(url) => void navigate(url)} />
        )}
      </div>
    </section>
  )
}

function ToolbarButton({
  label,
  disabled,
  active,
  onClick,
  children
}: {
  label: string
  disabled?: boolean
  active?: boolean
  onClick: () => void
  children: React.ReactNode
}): React.JSX.Element {
  return (
    <button
      type="button"
      className="toolbar-button"
      data-active={active}
      disabled={disabled}
      aria-label={label}
      title={label}
      onClick={onClick}
    >
      {children}
    </button>
  )
}

function QuickAccess({
  onNavigate
}: {
  onNavigate: (url: string) => void
}): React.JSX.Element {
  const { t } = useI18n()
  return (
    <div className="quick-access">
      <div className="quick-access-heading">
        <span className="eyebrow">{t('browser.newTab')}</span>
        <h1>{t('browser.quickAccess')}</h1>
        <p>{t('browser.quickHint')}</p>
      </div>
      <div className="quick-site-grid">
        {quickSites.map(({ name, url, icon: Icon, tone }) => (
          <button
            type="button"
            key={url}
            className="quick-site"
            data-tone={tone}
            onClick={() => onNavigate(url)}
          >
            <span className="quick-site-icon"><Icon size={20} /></span>
            <span>{name}</span>
            <ChevronRight size={13} className="quick-site-arrow" />
          </button>
        ))}
      </div>
    </div>
  )
}

function tabTitle(tab: BrowserTab, fallback: string): string {
  if (tab.isHome) return fallback
  if (tab.title) return tab.title
  try {
    return new URL(tab.url).hostname
  } catch {
    return fallback
  }
}
