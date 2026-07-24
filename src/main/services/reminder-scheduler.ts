import type {
  Reminder,
  ReminderInput,
  ReminderUpdate
} from '../../shared/contracts.js'
import {
  createReminderRecord,
  settleDueReminder,
  updateReminderRecord
} from '../../shared/reminders.js'

type ReminderStore = {
  readonly reminders: Reminder[]
  setReminders: (reminders: Reminder[]) => Reminder[]
}

type ReminderSchedulerOptions = {
  store: ReminderStore
  notify: (reminder: Reminder) => void
  onChanged: (reminders: Reminder[]) => void
  now?: () => Date
}

export class ReminderScheduler {
  private readonly store: ReminderStore
  private readonly notify: (reminder: Reminder) => void
  private readonly onChanged: (reminders: Reminder[]) => void
  private readonly now: () => Date
  private readonly timers = new Map<string, ReturnType<typeof setTimeout>>()

  constructor(options: ReminderSchedulerOptions) {
    this.store = options.store
    this.notify = options.notify
    this.onChanged = options.onChanged
    this.now = options.now ?? (() => new Date())
  }

  start(): void {
    this.reconcile()
  }

  stop(): void {
    for (const timer of this.timers.values()) clearTimeout(timer)
    this.timers.clear()
  }

  list(): Reminder[] {
    return this.store.reminders
  }

  create(input: ReminderInput): Reminder {
    const reminder = createReminderRecord(input, this.now())
    const reminders = [...this.store.reminders, reminder]
    this.store.setReminders(reminders)
    this.schedule(reminder)
    this.onChanged(reminders)
    return reminder
  }

  update(id: string, updates: ReminderUpdate): Reminder {
    const reminders = this.store.reminders
    const current = reminders.find((reminder) => reminder.id === id)
    if (!current) throw new Error('Reminder not found')

    const updated = updateReminderRecord(current, updates, this.now())
    const next = reminders.map((reminder) => reminder.id === id ? updated : reminder)
    this.store.setReminders(next)
    this.clear(id)
    this.schedule(updated)
    this.onChanged(next)
    return updated
  }

  setEnabled(id: string, enabled: boolean): Reminder {
    return this.update(id, { enabled })
  }

  remove(id: string): Reminder[] {
    const reminders = this.store.reminders
    if (!reminders.some((reminder) => reminder.id === id)) {
      throw new Error('Reminder not found')
    }
    this.clear(id)
    const next = reminders.filter((reminder) => reminder.id !== id)
    this.store.setReminders(next)
    this.onChanged(next)
    return next
  }

  reconcile(): void {
    for (const reminder of this.store.reminders) {
      this.clear(reminder.id)
      this.schedule(reminder)
    }
  }

  private schedule(reminder: Reminder): void {
    if (!reminder.enabled || !reminder.nextTriggerAt) return
    const dueAt = new Date(reminder.nextTriggerAt).getTime()
    const delay = Math.max(0, dueAt - this.now().getTime())
    const timer = setTimeout(() => this.fire(reminder.id), delay)
    this.timers.set(reminder.id, timer)
  }

  private fire(id: string): void {
    this.timers.delete(id)
    const reminders = this.store.reminders
    const current = reminders.find((reminder) => reminder.id === id)
    if (!current?.enabled || !current.nextTriggerAt) return

    this.notify(current)
    const settled = settleDueReminder(current, this.now())
    const next = reminders.map((reminder) => reminder.id === id ? settled : reminder)
    this.store.setReminders(next)
    this.onChanged(next)
    this.schedule(settled)
  }

  private clear(id: string): void {
    const timer = this.timers.get(id)
    if (timer) clearTimeout(timer)
    this.timers.delete(id)
  }
}
