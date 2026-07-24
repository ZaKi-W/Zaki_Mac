import { describe, expect, it } from 'vitest'
import {
  formatAccelerator,
  keyboardEventToAccelerator
} from './shortcut.js'

describe('shortcut helpers', () => {
  it('requires a modifier and formats platform labels', () => {
    expect(keyboardEventToAccelerator({
      key: 'h',
      metaKey: false,
      ctrlKey: false,
      altKey: false,
      shiftKey: false
    })).toBeNull()
    expect(keyboardEventToAccelerator({
      key: 'h',
      metaKey: true,
      ctrlKey: false,
      altKey: false,
      shiftKey: true
    })).toBe('CommandOrControl+Shift+H')
    expect(formatAccelerator('CommandOrControl+Shift+H', 'darwin')).toBe('⌘ ⇧ H')
    expect(formatAccelerator('CommandOrControl+Shift+H', 'win32')).toBe(
      'Ctrl + Shift + H'
    )
  })
})
