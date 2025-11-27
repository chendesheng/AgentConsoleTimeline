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
    if (!key) return false;

    this.pendingKeys.push(key);
    const keymap = this.keymaps.find((action) =>
      arrayStartsWith(action.keys, this.pendingKeys),
    );
    if (keymap) {
      if (keymap.keys.length === this.pendingKeys.length) {
        this.pendingKeys = [];
        keymap.action();
      } else {
        this.delayClearPendingKeys();
      }
      return true;
    } else {
      this.pendingKeys = [];
      return false;
    }
  }

  private delayClearPendingKeys() {
    clearTimeout(this.pendingKeysTimeout);
    this.pendingKeysTimeout = setTimeout(() => {
      this.pendingKeys = [];
    }, 500);
  }
}

function arrayStartsWith(a: string[], b: string[]): boolean {
  if (a.length < b.length) return false;
  for (let i = 0; i < b.length; i++) {
    if (a[i] !== b[i]) return false;
  }
  return true;
}

function arrayEqual(a: string[], b: string[]): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) return false;
  }
  return true;
}

function toKey(e: KeyboardEvent): string | undefined {
  if (e.key === "Control") return;
  if (e.key === "Alt") return;
  if (e.key === "Meta") return;
  if (e.key === "Shift") return;

  // FIXME: handle super/command key
  return (
    (e.ctrlKey ? "ctrl+" : "") +
    (e.altKey ? "alt+" : "") +
    (e.metaKey ? "meta+" : "") +
    e.key
  );
}
