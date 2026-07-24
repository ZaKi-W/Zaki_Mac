import { useMemo, useState } from 'react'
import {
  BellRing,
  Check,
  CirclePause,
  Clock3,
  Pencil,
  Play,
  Plus,
  Trash2
} from 'lucide-react'
import type {
  Reminder,
  ReminderInput,
  Result
} from '../../../../shared/contracts'
import { useI18n } from '../../i18n'
import { ReminderSheet } from './ReminderSheet'

type ReminderPageProps = {
  reminders: Reminder[]
  onChange: (reminders: Reminder[]) => void
}

function unwrap<T>(result: Result<T>): T {
  if (!result.ok) throw new Error(result.error.message)
  return result.data
}

export function ReminderPage({
  reminders,
  onChange
}: ReminderPageProps): React.JSX.Element {
  const { t, language } = useI18n()
  const [sheetOpen, setSheetOpen] = useState(false)
  const [editing, setEditing] = useState<Reminder | null>(null)
  const [error, setError] = useState<string | null>(null)

  const groups = useMemo(() => ({
    active: reminders.filter((reminder) => reminder.enabled),
    paused: reminders.filter(
      (reminder) => !reminder.enabled && !reminder.completedAt
    ),
    completed: reminders.filter((reminder) => Boolean(reminder.completedAt))
  }), [reminders])

  const dateLabel = new Intl.DateTimeFormat(
    language === 'zh' ? 'zh-CN' : 'en-US',
    { weekday: 'long', month: 'long', day: 'numeric' }
  ).format(new Date())

  const openCreate = (): void => {
    setEditing(null)
    setSheetOpen(true)
  }

  const submit = async (input: ReminderInput): Promise<void> => {
    setError(null)
    try {
      if (editing) {
        const updated = unwrap(
          await window.desktop.reminders.update(editing.id, input)
        )
        onChange(reminders.map((item) => item.id === updated.id ? updated : item))
      } else {
        const created = unwrap(await window.desktop.reminders.create(input))
        onChange([...reminders, created])
      }
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : t('common.error'))
      throw caught
    }
  }

  const setEnabled = async (reminder: Reminder): Promise<void> => {
    setError(null)
    try {
      const updated = unwrap(
        await window.desktop.reminders.setEnabled(
          reminder.id,
          !reminder.enabled
        )
      )
      onChange(reminders.map((item) => item.id === updated.id ? updated : item))
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : t('common.error'))
    }
  }

  const remove = async (id: string): Promise<void> => {
    setError(null)
    try {
      onChange(unwrap(await window.desktop.reminders.remove(id)))
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : t('common.error'))
    }
  }

  return (
    <section className="page reminder-page">
      <header className="page-header">
        <div>
          <span className="eyebrow">{dateLabel}</span>
          <h1>{t('reminders.title')}</h1>
        </div>
        <button type="button" className="button primary" onClick={openCreate}>
          <Plus size={15} strokeWidth={2.2} />
          {t('reminders.add')}
        </button>
      </header>

      {error && <div className="inline-error" role="alert">{error}</div>}

      {reminders.length === 0 ? (
        <div className="empty-reminders">
          <div className="empty-icon">
            <BellRing size={25} strokeWidth={1.6} />
          </div>
          <div>
            <h2>{t('reminders.emptyTitle')}</h2>
            <button type="button" className="text-action" onClick={openCreate}>
              {t('reminders.emptyAction')} <span aria-hidden="true">→</span>
            </button>
          </div>
        </div>
      ) : (
        <div className="reminder-groups">
          <ReminderGroup
            title={t('reminders.active')}
            reminders={groups.active}
            onToggle={setEnabled}
            onEdit={(reminder) => {
              setEditing(reminder)
              setSheetOpen(true)
            }}
            onRemove={remove}
          />
          <ReminderGroup
            title={t('reminders.paused')}
            reminders={groups.paused}
            onToggle={setEnabled}
            onEdit={(reminder) => {
              setEditing(reminder)
              setSheetOpen(true)
            }}
            onRemove={remove}
          />
          <ReminderGroup
            title={t('reminders.completed')}
            reminders={groups.completed}
            onToggle={setEnabled}
            onEdit={(reminder) => {
              setEditing(reminder)
              setSheetOpen(true)
            }}
            onRemove={remove}
          />
        </div>
      )}

      {sheetOpen && (
        <ReminderSheet
          reminder={editing}
          onClose={() => {
            setSheetOpen(false)
            setEditing(null)
          }}
          onSubmit={submit}
        />
      )}
    </section>
  )
}

function ReminderGroup({
  title,
  reminders,
  onToggle,
  onEdit,
  onRemove
}: {
  title: string
  reminders: Reminder[]
  onToggle: (reminder: Reminder) => void
  onEdit: (reminder: Reminder) => void
  onRemove: (id: string) => void
}): React.JSX.Element | null {
  if (reminders.length === 0) return null
  return (
    <section className="reminder-group">
      <header>
        <h2>{title}</h2>
        <span>{reminders.length.toString().padStart(2, '0')}</span>
      </header>
      <div className="reminder-list">
        {reminders.map((reminder) => (
          <ReminderRow
            key={reminder.id}
            reminder={reminder}
            onToggle={() => onToggle(reminder)}
            onEdit={() => onEdit(reminder)}
            onRemove={() => onRemove(reminder.id)}
          />
        ))}
      </div>
    </section>
  )
}

function ReminderRow({
  reminder,
  onToggle,
  onEdit,
  onRemove
}: {
  reminder: Reminder
  onToggle: () => void
  onEdit: () => void
  onRemove: () => void
}): React.JSX.Element {
  const { t, language } = useI18n()
  const nextTime = reminder.nextTriggerAt
    ? new Intl.DateTimeFormat(language === 'zh' ? 'zh-CN' : 'en-US', {
        hour: '2-digit',
        minute: '2-digit',
        second: reminder.intervalSeconds < 60 ? '2-digit' : undefined
      }).format(new Date(reminder.nextTriggerAt))
    : null

  return (
    <article className="reminder-row" data-enabled={reminder.enabled}>
      <button
        type="button"
        className="reminder-toggle"
        onClick={onToggle}
        aria-label={reminder.enabled ? t('reminders.pause') : t('reminders.resume')}
      >
        {reminder.completedAt
          ? <Check size={14} />
          : reminder.enabled
            ? <CirclePause size={14} />
            : <Play size={14} />}
      </button>

      <div className="reminder-copy">
        <strong>{reminder.content}</strong>
        <div className="reminder-meta">
          <span>
            <Clock3 size={12} />
            {formatInterval(reminder.intervalSeconds, t)}
          </span>
          <span>{reminder.repeat ? t('reminders.repeat') : t('reminders.once')}</span>
          {nextTime && <span>{t('reminders.next')} {nextTime}</span>}
        </div>
      </div>

      <div className="row-actions">
        <button type="button" className="icon-button" onClick={onEdit} aria-label={t('common.edit')}>
          <Pencil size={14} />
        </button>
        <button type="button" className="icon-button danger" onClick={onRemove} aria-label={t('common.delete')}>
          <Trash2 size={14} />
        </button>
      </div>
    </article>
  )
}

function formatInterval(
  seconds: number,
  t: (key: string) => string
): string {
  const hours = Math.floor(seconds / 3600)
  const minutes = Math.floor((seconds % 3600) / 60)
  const remainder = seconds % 60
  const parts: string[] = []
  if (hours) parts.push(`${hours} ${t('reminders.hours')}`)
  if (minutes) parts.push(`${minutes} ${t('reminders.minutes')}`)
  if (remainder) parts.push(`${remainder} ${t('reminders.seconds')}`)
  return `${t('reminders.every')} ${parts.join(' ')}`
}
