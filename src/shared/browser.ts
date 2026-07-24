import type { Language } from './contracts.js'

export function isSafeWebUrl(value: string): boolean {
  try {
    const protocol = new URL(value).protocol
    return protocol === 'http:' || protocol === 'https:'
  } catch {
    return false
  }
}

export function isZhihuUrl(value: string): boolean {
  try {
    const hostname = new URL(value).hostname.toLowerCase()
    return hostname === 'zhihu.com' || hostname.endsWith('.zhihu.com')
  } catch {
    return false
  }
}

export function normalizeUrl(value: string): string {
  try {
    const url = new URL(value)
    const hostname = url.hostname.replace(/^www\./, '').toLowerCase()
    const pathname = url.pathname.replace(/\/$/, '') || '/'
    return `${url.protocol}//${hostname}${pathname}${url.search}`
  } catch {
    return value
  }
}

export function resolveUrl(input: string, language: Language): string {
  const value = input.trim()
  if (!value) return ''
  if (/^https?:\/\//i.test(value)) return value
  if (/^[\w-]+(\.[\w-]+)+(:\d+)?(\/.*)?$/i.test(value)) {
    return `https://${value}`
  }
  if (/^localhost(:\d+)?(\/.*)?$/i.test(value)) {
    return `http://${value}`
  }
  const engine = language === 'zh'
    ? 'https://www.bing.com/search?q='
    : 'https://www.google.com/search?q='
  return `${engine}${encodeURIComponent(value)}`
}

type BrowserShortcutInput = {
  type?: string
  key?: string
  meta?: boolean
  control?: boolean
  alt?: boolean
  shift?: boolean
  isAutoRepeat?: boolean
}

function isShortcutKeyDown(input: BrowserShortcutInput): boolean {
  return (input.type === undefined || input.type === 'keyDown')
    && !input.isAutoRepeat
}

export function isCloseTabShortcut(input: BrowserShortcutInput): boolean {
  return isShortcutKeyDown(input)
    && input.key?.toLowerCase() === 'w'
    && Boolean(input.meta || input.control)
    && !input.alt
    && !input.shift
}

export function isNewTabShortcut(input: BrowserShortcutInput): boolean {
  return isShortcutKeyDown(input)
    && input.key?.toLowerCase() === 't'
    && Boolean(input.meta || input.control)
    && !input.alt
    && !input.shift
}

export function isReloadShortcut(input: BrowserShortcutInput): boolean {
  return isShortcutKeyDown(input)
    && input.key?.toLowerCase() === 'r'
    && Boolean(input.meta || input.control)
    && !input.alt
}
