import { useMemo, useState } from 'react'
import { Bell, Clock3, Repeat2, X } from 'lucide-react'
import type {
  Reminder,
  ReminderInput
} from '../../../../shared/contracts'
import { useI18n } from '../../i18n'

type ReminderSheetProps = {
  reminder: Reminder | null
  onClose: () => void
  onSubmit: (input: ReminderInput) => Promise<void>
}

export function ReminderSheet({
  reminder,
  onClose,
  onSubmit
}: ReminderSheetProps): React.JSX.Element {
  const { t } = useI18n()
  const initialSeconds = reminder?.intervalSeconds ?? 30
  const [content, setContent] = useState(reminder?.content ?? '')
  const [hours, setHours] = useState(Math.floor(initialSeconds / 3600))
  const [minutes, setMinutes] = useState(
    Math.floor((initialSeconds % 3600) / 60)
  )
  const [seconds, setSeconds] = useState(initialSeconds % 60)
  const [repeat, setRepeat] = useState(reminder?.repeat ?? true)
  const [enabled, setEnabled] = useState(reminder?.enabled ?? true)
  const [submitting, setSubmitting] = useState(false)

  const intervalSeconds = useMemo(
    () => hours * 3600 + minutes * 60 + seconds,
    [hours, minutes, seconds]
  )
  const canSubmit = content.trim().length > 0 && intervalSeconds > 0 && !submitting

  const submit = async (event: React.FormEvent<HTMLFormElement>): Promise<void> => {
    event.preventDefault()
    if (!canSubmit) return
    setSubmitting(true)
    try {
      await onSubmit({
        content: content.trim(),
        intervalSeconds,
        repeat,
        enabled
      })
      onClose()
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <div className="sheet-backdrop" role="presentation" onMouseDown={onClose}>
      <aside
        className="reminder-sheet"
        role="dialog"
        aria-modal="true"
        aria-labelledby="reminder-sheet-title"
        onMouseDown={(event) => event.stopPropagation()}
      >
        <header className="sheet-header">
          <div>
            <span className="eyebrow">
              <Bell size={12} />
              {t('nav.reminders')}
            </span>
            <h2 id="reminder-sheet-title">
              {reminder ? t('reminders.editTitle') : t('reminders.newTitle')}
            </h2>
          </div>
          <button
            type="button"
            className="icon-button"
            onClick={onClose}
            aria-label={t('common.cancel')}
          >
            <X size={17} />
          </button>
        </header>

        <form className="sheet-form" onSubmit={submit}>
          <label className="field-group">
            <span>{t('reminders.content')}</span>
            <input
              autoFocus
              value={content}
              maxLength={240}
              onChange={(event) => setContent(event.target.value)}
              placeholder={t('reminders.contentPlaceholder')}
            />
          </label>

          <fieldset className="field-group">
            <legend>
              <Clock3 size={14} />
              {t('reminders.interval')}
            </legend>
            <div className="duration-grid">
              <DurationInput
                value={hours}
                max={23}
                label={t('reminders.hours')}
                onChange={setHours}
              />
              <DurationInput
                value={minutes}
                max={59}
                label={t('reminders.minutes')}
                onChange={setMinutes}
              />
              <DurationInput
                value={seconds}
                max={59}
                label={t('reminders.seconds')}
                onChange={setSeconds}
              />
            </div>
          </fieldset>

          <fieldset className="field-group">
            <legend>
              <Repeat2 size={14} />
              {t('reminders.mode')}
            </legend>
            <div className="segmented-control">
              <button
                type="button"
                data-active={repeat}
                onClick={() => setRepeat(true)}
              >
                {t('reminders.repeat')}
              </button>
              <button
                type="button"
                data-active={!repeat}
                onClick={() => setRepeat(false)}
              >
                {t('reminders.once')}
              </button>
            </div>
          </fieldset>

          <label className="switch-row">
            <span>
              <strong>{t('reminders.enabled')}</strong>
            </span>
            <input
              type="checkbox"
              checked={enabled}
              onChange={(event) => setEnabled(event.target.checked)}
            />
          </label>

          <footer className="sheet-actions">
            <button type="button" className="button secondary" onClick={onClose}>
              {t('common.cancel')}
            </button>
            <button type="submit" className="button primary" disabled={!canSubmit}>
              {reminder ? t('common.save') : t('reminders.create')}
            </button>
          </footer>
        </form>
      </aside>
    </div>
  )
}

function DurationInput({
  value,
  max,
  label,
  onChange
}: {
  value: number
  max: number
  label: string
  onChange: (value: number) => void
}): React.JSX.Element {
  return (
    <label className="duration-input">
      <input
        type="number"
        min={0}
        max={max}
        value={value}
        onChange={(event) => {
          const next = Number(event.target.value)
          onChange(Math.max(0, Math.min(max, Number.isFinite(next) ? next : 0)))
        }}
      />
      <span>{label}</span>
    </label>
  )
}
