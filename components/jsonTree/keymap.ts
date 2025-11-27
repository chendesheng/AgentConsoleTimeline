export type Keymap = {
  keys: string[];
  action: () => void;
};

export class KeymapManager {
  private keymaps: Keymap[] = [];
  private pendingKeys: string[] = [];
  private pendingKeysTimeout?: any;

  register(...keymaps: Keymap[]) {
    this.keymaps.push(...keymaps);
  }

  handleKeydown(e: KeyboardEvent) {
    const key = toKey(e);
    const keymap = this.keymaps.find((action) => action.keys.includes(key));
    if (keymap) {
      this.pendingKeys.push(key);
      if (arrayEqual(keymap.keys, this.pendingKeys)) {
        this.pendingKeys = [];
        keymap.action();
      } else {
        this.clearPendingKeys();
      }
    }
  }

  private clearPendingKeys() {
    clearTimeout(this.pendingKeysTimeout);
    this.pendingKeysTimeout = setTimeout(() => {
      this.pendingKeys = [];
    }, 500);
  }
}

function arrayEqual(a: string[], b: string[]): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) return false;
  }
  return true;
}

function toKey(e: KeyboardEvent): string {
  // FIXME: handle super/command key
  return (
    (e.ctrlKey ? "ctrl+" : "") +
    (e.altKey ? "alt+" : "") +
    (e.metaKey ? "meta+" : "") +
    e.key
  );
}
