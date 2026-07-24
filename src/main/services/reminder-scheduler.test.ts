import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { Reminder } from '../../shared/contracts.js'
import { createReminderRecord } from '../../shared/reminders.js'
import { ReminderScheduler } from './reminder-scheduler.js'

class MemoryReminderStore {
  reminders: Reminder[]

  constructor(reminders: Reminder[] = []) {
    this.reminders = structuredClone(reminders)
  }

  setReminders(reminders: Reminder[]): Reminder[] {
    this.reminders = structuredClone(reminders)
    return structuredClone(this.reminders)
  }
}

describe('ReminderScheduler', () => {
  beforeEach(() => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2026-07-24T02:00:00.000Z'))
  })

  afterEach(() => {
    vi.useRealTimers()
  })

  it('fires and completes a one-off reminder', () => {
    const store = new MemoryReminderStore()
    const notify = vi.fn()
    const scheduler = new ReminderScheduler({
      store,
      notify,
      onChanged: vi.fn()
    })

    scheduler.create({
      content: 'Stand up',
      intervalSeconds: 5,
      repeat: false,
      enabled: true
    })
    vi.advanceTimersByTime(5_000)

    expect(notify).toHaveBeenCalledOnce()
    expect(store.reminders[0]).toMatchObject({
      enabled: false,
      nextTriggerAt: null
    })
    expect(store.reminders[0]?.completedAt).not.toBeNull()
  })

  it('catches up an overdue repeating reminder once and reschedules from now', () => {
    const overdue = createReminderRecord({
      content: 'Drink water',
      intervalSeconds: 60,
      repeat: true,
      enabled: true
    }, new Date('2026-07-24T01:00:00.000Z'), 'overdue')
    const store = new MemoryReminderStore([overdue])
    const notify = vi.fn()
    const scheduler = new ReminderScheduler({
      store,
      notify,
      onChanged: vi.fn()
    })

    scheduler.start()
    vi.runOnlyPendingTimers()

    expect(notify).toHaveBeenCalledOnce()
    expect(store.reminders[0]?.nextTriggerAt).toBe(
      '2026-07-24T02:01:00.000Z'
    )
  })

  it('does not schedule disabled reminders and removes active timers', () => {
    const store = new MemoryReminderStore()
    const notify = vi.fn()
    const scheduler = new ReminderScheduler({
      store,
      notify,
      onChanged: vi.fn()
    })
    const reminder = scheduler.create({
      content: 'Pause me',
      intervalSeconds: 2,
      repeat: true,
      enabled: true
    })
    scheduler.setEnabled(reminder.id, false)
    vi.advanceTimersByTime(4_000)
    expect(notify).not.toHaveBeenCalled()

    expect(scheduler.remove(reminder.id)).toEqual([])
  })
})
