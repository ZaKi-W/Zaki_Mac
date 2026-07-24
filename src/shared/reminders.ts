import type { Reminder, ReminderInput, ReminderUpdate } from './contracts.js'

export function createReminderRecord(
  input: ReminderInput,
  now = new Date(),
  id: string = globalThis.crypto.randomUUID()
): Reminder {
  const timestamp = now.toISOString()
  return {
    id,
    content: input.content.trim(),
    intervalSeconds: input.intervalSeconds,
    repeat: input.repeat,
    enabled: input.enabled,
    createdAt: timestamp,
    nextTriggerAt: input.enabled
      ? new Date(now.getTime() + input.intervalSeconds * 1000).toISOString()
      : null,
    completedAt: null
  }
}

export function updateReminderRecord(
  reminder: Reminder,
  updates: ReminderUpdate,
  now = new Date()
): Reminder {
  const next = { ...reminder, ...updates }
  const schedulingChanged = updates.intervalSeconds !== undefined
    || updates.repeat !== undefined
    || updates.enabled !== undefined

  if (!next.enabled) {
    return { ...next, nextTriggerAt: null }
  }

  if (schedulingChanged || !next.nextTriggerAt) {
    return {
      ...next,
      completedAt: null,
      nextTriggerAt: new Date(
        now.getTime() + next.intervalSeconds * 1000
      ).toISOString()
    }
  }

  return next
}

export function settleDueReminder(
  reminder: Reminder,
  now = new Date()
): Reminder {
  if (!reminder.repeat) {
    return {
      ...reminder,
      enabled: false,
      nextTriggerAt: null,
      completedAt: now.toISOString()
    }
  }

  return {
    ...reminder,
    nextTriggerAt: new Date(
      now.getTime() + reminder.intervalSeconds * 1000
    ).toISOString(),
    completedAt: null
  }
}
