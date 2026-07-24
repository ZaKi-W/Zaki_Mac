import { describe, expect, it } from 'vitest'
import {
  browserBoundsSchema,
  reminderInputSchema,
  safeWebUrlSchema,
  settingsPatchSchema
} from './contracts.js'

describe('IPC contract validation', () => {
  it('rejects empty and zero-duration reminders', () => {
    expect(reminderInputSchema.safeParse({
      content: '',
      intervalSeconds: 0,
      repeat: true,
      enabled: true
    }).success).toBe(false)
  })

  it('rejects unsafe URL schemes and negative view bounds', () => {
    expect(safeWebUrlSchema.safeParse('javascript:alert(1)').success).toBe(false)
    expect(browserBoundsSchema.safeParse({
      x: -1,
      y: 0,
      width: 100,
      height: 100
    }).success).toBe(false)
  })

  it('accepts supported theme and language updates', () => {
    expect(settingsPatchSchema.safeParse({
      themeMode: 'dark',
      language: 'en'
    }).success).toBe(true)
  })
})
