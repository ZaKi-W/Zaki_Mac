export const IPC = {
  reminders: {
    list: 'reminders:list',
    create: 'reminders:create',
    update: 'reminders:update',
    remove: 'reminders:remove',
    setEnabled: 'reminders:set-enabled',
    changed: 'reminders:changed'
  },
  bookmarks: {
    list: 'bookmarks:list',
    save: 'bookmarks:save',
    remove: 'bookmarks:remove',
    changed: 'bookmarks:changed'
  },
  browser: {
    state: 'browser:state',
    create: 'browser:create',
    close: 'browser:close',
    activate: 'browser:activate',
    navigate: 'browser:navigate',
    back: 'browser:back',
    forward: 'browser:forward',
    reload: 'browser:reload',
    home: 'browser:home',
    setBounds: 'browser:set-bounds',
    setVisible: 'browser:set-visible',
    changed: 'browser:changed'
  },
  settings: {
    get: 'settings:get',
    update: 'settings:update',
    updateShortcut: 'settings:update-shortcut',
    changed: 'settings:changed'
  },
  app: {
    info: 'app:info',
    navigate: 'app:navigate'
  }
} as const
