const MODIFIER_KEYS = new Set(['Alt', 'Control', 'Meta', 'Shift'])

const KEY_ALIASES: Record<string, string> = {
  ' ': 'Space',
  ArrowDown: 'Down',
  ArrowLeft: 'Left',
  ArrowRight: 'Right',
  ArrowUp: 'Up',
  Escape: 'Esc'
}

export const DEFAULT_SHORTCUT = 'CommandOrControl+Shift+H'

export type ShortcutKeyboardEvent = {
  key: string
  metaKey: boolean
  ctrlKey: boolean
  altKey: boolean
  shiftKey: boolean
}

export function keyboardEventToAccelerator(
  event: ShortcutKeyboardEvent
): string | null {
  if (MODIFIER_KEYS.has(event.key)) return null

  const modifiers: string[] = []
  if (event.metaKey || event.ctrlKey) modifiers.push('CommandOrControl')
  if (event.altKey) modifiers.push('Alt')
  if (event.shiftKey) modifiers.push('Shift')
  if (modifiers.length === 0) return null

  let key = KEY_ALIASES[event.key] ?? event.key
  if (key.length === 1) key = key.toUpperCase()
  return [...modifiers, key].join('+')
}

export function formatAccelerator(
  accelerator: string,
  platform: string
): string {
  const labels = platform === 'darwin'
    ? {
        CommandOrControl: '⌘',
        Command: '⌘',
        Control: '⌃',
        Alt: '⌥',
        Option: '⌥',
        Shift: '⇧'
      }
    : {
        CommandOrControl: 'Ctrl',
        Command: 'Ctrl',
        Control: 'Ctrl',
        Alt: 'Alt',
        Option: 'Alt',
        Shift: 'Shift'
      }

  const separator = platform === 'darwin' ? ' ' : ' + '
  return accelerator
    .split('+')
    .map((part) => labels[part as keyof typeof labels] ?? part)
    .join(separator)
}
