import {
  createContext,
  useCallback,
  useContext,
  useMemo,
  type ReactNode
} from 'react'
import type { Language } from '../../shared/contracts'

const messages: Record<Language, Record<string, string>> = {
  zh: {
    'app.name': '提醒',
    'nav.reminders': '提醒',
    'nav.browser': '浏览器',
    'nav.settings': '设置',
    'nav.enabled': '个运行中',
    'common.cancel': '取消',
    'common.save': '保存',
    'common.delete': '删除',
    'common.edit': '编辑',
    'common.loading': '正在加载…',
    'common.error': '操作未完成',
    'reminders.title': '提醒',
    'reminders.add': '新建提醒',
    'reminders.active': '运行中',
    'reminders.paused': '已暂停',
    'reminders.completed': '已完成',
    'reminders.emptyTitle': '暂无提醒',
    'reminders.emptyAction': '新建提醒',
    'reminders.repeat': '循环',
    'reminders.once': '单次',
    'reminders.every': '每',
    'reminders.next': '下次',
    'reminders.resume': '继续',
    'reminders.pause': '暂停',
    'reminders.newTitle': '新建提醒',
    'reminders.editTitle': '编辑提醒',
    'reminders.content': '提醒内容',
    'reminders.contentPlaceholder': '例如：起身活动一下',
    'reminders.interval': '时间间隔',
    'reminders.hours': '小时',
    'reminders.minutes': '分钟',
    'reminders.seconds': '秒',
    'reminders.mode': '提醒方式',
    'reminders.enabled': '创建后立即启用',
    'reminders.create': '创建提醒',
    'browser.address': '搜索或输入网址',
    'browser.newTab': '新标签页',
    'browser.quickAccess': '快速开始',
    'browser.quickHint': '选择常用站点，或在上方输入搜索内容',
    'browser.back': '后退',
    'browser.forward': '前进',
    'browser.reload': '刷新',
    'browser.home': '主页',
    'browser.bookmark': '收藏',
    'browser.unbookmark': '取消收藏',
    'browser.dark': '网页暗色模式',
    'browser.light': '网页浅色模式',
    'settings.title': '设置',
    'settings.appearance': '外观',
    'settings.appearanceBody': '默认跟随系统，也可以固定一种外观。',
    'settings.system': '跟随系统',
    'settings.light': '浅色',
    'settings.dark': '深色',
    'settings.language': '语言',
    'settings.languageBody': '界面语言会立即切换。',
    'settings.shortcut': '全局快捷键',
    'settings.shortcutBody': '在任何应用中显示或隐藏提醒窗口。',
    'settings.shortcutHint': '点按输入框，然后按下包含修饰键的组合键。',
    'settings.reset': '恢复默认',
    'settings.saved': '设置已保存',
    'settings.unavailable': '快捷键无效或已被占用',
    'settings.browser': '浏览体验',
    'settings.browserBody': '网页暗色模式仅影响支持适配的网页。',
    'settings.about': '关于',
    'settings.version': '版本'
  },
  en: {
    'app.name': 'Reminder',
    'nav.reminders': 'Reminders',
    'nav.browser': 'Browser',
    'nav.settings': 'Settings',
    'nav.enabled': 'active',
    'common.cancel': 'Cancel',
    'common.save': 'Save',
    'common.delete': 'Delete',
    'common.edit': 'Edit',
    'common.loading': 'Loading…',
    'common.error': 'The action could not be completed',
    'reminders.title': 'Reminders',
    'reminders.add': 'New reminder',
    'reminders.active': 'Active',
    'reminders.paused': 'Paused',
    'reminders.completed': 'Completed',
    'reminders.emptyTitle': 'No reminders',
    'reminders.emptyAction': 'New reminder',
    'reminders.repeat': 'Repeat',
    'reminders.once': 'Once',
    'reminders.every': 'Every',
    'reminders.next': 'Next',
    'reminders.resume': 'Resume',
    'reminders.pause': 'Pause',
    'reminders.newTitle': 'New reminder',
    'reminders.editTitle': 'Edit reminder',
    'reminders.content': 'Reminder',
    'reminders.contentPlaceholder': 'For example: Take a stretch break',
    'reminders.interval': 'Time interval',
    'reminders.hours': 'hours',
    'reminders.minutes': 'min',
    'reminders.seconds': 'sec',
    'reminders.mode': 'Reminder mode',
    'reminders.enabled': 'Enable immediately',
    'reminders.create': 'Create reminder',
    'browser.address': 'Search or enter an address',
    'browser.newTab': 'New tab',
    'browser.quickAccess': 'Quick access',
    'browser.quickHint': 'Choose a frequent site or search from the field above',
    'browser.back': 'Back',
    'browser.forward': 'Forward',
    'browser.reload': 'Reload',
    'browser.home': 'Home',
    'browser.bookmark': 'Bookmark',
    'browser.unbookmark': 'Remove bookmark',
    'browser.dark': 'Dark page mode',
    'browser.light': 'Light page mode',
    'settings.title': 'Settings',
    'settings.appearance': 'Appearance',
    'settings.appearanceBody': 'Follow the system or keep a fixed appearance.',
    'settings.system': 'System',
    'settings.light': 'Light',
    'settings.dark': 'Dark',
    'settings.language': 'Language',
    'settings.languageBody': 'The interface updates immediately.',
    'settings.shortcut': 'Global shortcut',
    'settings.shortcutBody': 'Show or hide Reminder from any application.',
    'settings.shortcutHint': 'Focus the field, then press a modified key combination.',
    'settings.reset': 'Reset',
    'settings.saved': 'Settings saved',
    'settings.unavailable': 'That shortcut is invalid or already in use',
    'settings.browser': 'Browsing',
    'settings.browserBody': 'Page dark mode only affects supported sites.',
    'settings.about': 'About',
    'settings.version': 'Version'
  }
}

type I18nValue = {
  language: Language
  t: (key: string) => string
}

const I18nContext = createContext<I18nValue | null>(null)

export function I18nProvider({
  children,
  language = 'zh'
}: {
  children: ReactNode
  language?: Language
}): React.JSX.Element {
  const t = useCallback(
    (key: string) => messages[language][key] ?? key,
    [language]
  )
  const value = useMemo(() => ({ language, t }), [language, t])
  return <I18nContext.Provider value={value}>{children}</I18nContext.Provider>
}

export function useI18n(): I18nValue {
  const context = useContext(I18nContext)
  if (!context) throw new Error('useI18n must be used inside I18nProvider')
  return context
}
