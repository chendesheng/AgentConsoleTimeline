import { html, css, LitElement, PropertyValues, PropertyValueMap } from "lit";
import { customElement, property, query, state } from "lit/decorators.js";

@customElement("agent-console-snapshot")
export class AgentConsoleSnapshot extends LitElement {
  @property({ type: String })
  src = "";
  @property({ type: String })
  state = "";

  @property({ type: Array })
  actions: string[] = [];

  @property({ type: String })
  time = "";

  @query("iframe")
  iframe!: HTMLIFrameElement;

  @state()
  private popoutWindow?: Window | null;

  private getSnapshotWindow() {
    if (this.iframe) {
      return this.iframe.contentWindow;
    } else {
      return this.popoutWindow;
    }
  }

  static styles = css`
    :host {
      display: flex;
      flex-flow: column;
      gap: 4px;
    }
    .snapshot {
      border-radius: 4px;
      box-shadow: 0 0 10px 0 rgba(0, 0, 0, 0.1);
      border: none;
      height: 100%;
      width: 100%;
      flex: auto;
      background-color: rgb(240, 240, 240);
    }
    button.snapshot {
      font-size: 80px;
      cursor: pointer;
      opacity: 0.5;
      color: gray;
      font-weight: bold;
      text-transform: uppercase;
    }
    .header {
      flex: none;
      display: flex;
      align-items: end;
      color: var(--text-color);
      height: 20px;
    }
    .header button {
      flex: none;
      color: inherit;
      font-size: 20px;
      padding: 0;
      margin: 0;
      height: 18px;
      line-height: 18px;
      background: none;
      border: none;
      appearance: none;
      opacity: 0.5;
      cursor: pointer;
      margin-right: 4px;
    }
    .header button:hover,
    .header button:active {
      opacity: 0.8;
    }
    .header .src {
      flex: none;
    }
  `;

  private handleClickReloadButton() {
    this.iframe.src = this.src;
  }

  private handleClickPopoutButton() {
    if (this.popoutWindow) {
      this.popoutWindow.close();
      this.popoutWindow = undefined;
    }
    this.popoutWindow = window.open(this.src, "snapshot");
    console.log("popout window", this.popoutWindow);
  }

  private handleClickRestorePopoutButton() {
    if (this.popoutWindow) {
      this.popoutWindow.close();
      this.popoutWindow = undefined;
    }
  }

  private handleSrcInputBlur(e: UIEvent) {
    const ele = e.target as HTMLInputElement;
    const [prefix, rest] = AgentConsoleSnapshot.splitSrc(this.src);
    if (ele.textContent!.trim() !== prefix.trim()) {
      this.dispatchEvent(
        new CustomEvent("srcChange", {
          detail: { value: `${ele.textContent!.trim()}${rest}` },
        }),
      );
    }
  }

  private static splitSrc(src: string) {
    const url = new URL(src);
    return [`${url.protocol}//${url.host}`, `${url.pathname}${url.search}`];
  }

  render() {
    const [prefix, rest] = AgentConsoleSnapshot.splitSrc(this.src);
    return html`<div class="header">
        <button title="Reload" @click=${this.handleClickReloadButton}>⟳</button>
        <span class="src" contenteditable @blur=${this.handleSrcInputBlur}
          >${prefix}</span
        >${rest}
        <button title="Popout" @click=${this.handleClickPopoutButton}>🡽</button>
      </div>
      ${this.popoutWindow
        ? html`<button
            class="snapshot"
            @click=${this.handleClickRestorePopoutButton}
          >
            Restore Popout
          </button>`
        : html`<iframe
            class="snapshot"
            src="${this.src}"
            allow="clipboard-read; clipboard-write"
          ></iframe>`}`;
  }

  private sendToSnapshot() {
    if (this.state) {
      // console.log('restore state');
      this.getSnapshotWindow()?.postMessage(
        { type: "restoreReduxState", payload: this.state, time: this.time },
        "*",
      );
    }
    this.dispatchActionsToSnapshot(this.actions);
  }

  dispatchActionsToSnapshot(actions: string[]) {
    const win = this.getSnapshotWindow();
    if (!win) return;

    for (const action of actions) {
      // console.log('dispatch action', action);
      win.postMessage(
        {
          type: "dispatchReduxAction",
          action: JSON.parse(action),
          time: this.time,
        },
        "*",
      );
    }
  }

  handleMessage!: (e: MessageEvent) => void;

  connectedCallback(): void {
    super.connectedCallback();
    this.handleMessage = (e: MessageEvent) => {
      if (e.data?.type === "waitForReduxState") {
        this.sendToSnapshot();
      }
    };
    window.addEventListener("message", this.handleMessage);
  }

  disconnectedCallback(): void {
    if (this.popoutWindow) {
      this.popoutWindow.close();
      this.popoutWindow = undefined;
    }
    window.removeEventListener("message", this.handleMessage);
  }

  private diffActions(oldActions: string[]): string[] | undefined {
    const actions = this.actions;
    if (oldActions.length > actions.length) {
      return;
    }
    if (oldActions.some((action, i) => action !== actions[i])) {
      return;
    }
    return actions.slice(oldActions.length);
  }

  updated(prev: PropertyValues<this>) {
    if (!prev.has("state") && prev.has("actions")) {
      const actions = this.diffActions(prev.get("actions")!);
      if (actions) this.dispatchActionsToSnapshot(actions);
      else this.sendToSnapshot();
      return;
    }

    if (prev.has("state")) {
      this.sendToSnapshot();
    }
  }
}
