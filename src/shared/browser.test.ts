import { describe, expect, it } from 'vitest'
import {
  isCloseTabShortcut,
  isNewTabShortcut,
  isReloadShortcut,
  isSafeWebUrl,
  isZhihuUrl,
  normalizeUrl,
  resolveUrl
} from './browser.js'

describe('browser helpers', () => {
  it('allows only HTTP and HTTPS navigation', () => {
    expect(isSafeWebUrl('https://example.com')).toBe(true)
    expect(isSafeWebUrl('http://localhost:5173')).toBe(true)
    expect(isSafeWebUrl('javascript:alert(1)')).toBe(false)
    expect(isSafeWebUrl('file:///tmp/example')).toBe(false)
  })

  it('resolves addresses and localized searches', () => {
    expect(resolveUrl('example.com', 'zh')).toBe('https://example.com')
    expect(resolveUrl('测试 搜索', 'zh')).toContain('bing.com/search')
    expect(resolveUrl('search phrase', 'en')).toContain('google.com/search')
  })

  it('normalizes bookmark URLs and recognizes Zhihu subdomains', () => {
    expect(normalizeUrl('https://www.example.com/path/')).toBe(
      'https://example.com/path'
    )
    expect(isZhihuUrl('https://www.zhihu.com/question/1')).toBe(true)
    expect(isZhihuUrl('https://notzhihu.com')).toBe(false)
  })

  it('recognizes browser tab shortcuts without modified variants', () => {
    expect(isCloseTabShortcut({ key: 'w', meta: true })).toBe(true)
    expect(isCloseTabShortcut({ key: 'w', meta: true, shift: true })).toBe(false)
    expect(isNewTabShortcut({ key: 't', control: true })).toBe(true)
    expect(isNewTabShortcut({ key: 't', control: true, isAutoRepeat: true })).toBe(false)
    expect(isNewTabShortcut({ type: 'keyUp', key: 't', meta: true })).toBe(false)
    expect(isReloadShortcut({ type: 'keyDown', key: 'r', meta: true })).toBe(true)
    expect(isReloadShortcut({ key: 'R', control: true, shift: true })).toBe(true)
    expect(isReloadShortcut({ key: 'r', meta: true, alt: true })).toBe(false)
  })
})
