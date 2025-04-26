import { html, css, LitElement, PropertyValues } from "lit";
import { customElement, property, query, state } from "lit/decorators.js";

@customElement("agent-console-snapshot-frame")
export class AgentConsoleSnapshotFrame extends LitElement {
  @property({ type: String })
  src = "";

  @property({ type: String })
  state = "";

  @property({ type: Array })
  actions: string[] = [];

  @property({ type: String })
  time = "";

  @property({ type: Boolean })
  isPopout = false;

  @query("iframe")
  iframe?: HTMLIFrameElement;

  private get popoutWindowPathname() {
    return new URL(this.src).pathname;
  }

  private get popoutWindow(): Window | undefined {
    return globalThis.popoutWindows?.[this.popoutWindowPathname];
  }

  private getSnapshotWindow() {
    return this.popoutWindow ?? this.iframe?.contentWindow;
  }

  public reload() {
    if (this.iframe) this.iframe.src = this.src;
  }

  static styles = css`
    :host {
      display: flex;
      flex-flow: column;
      gap: 4px;
    }
    iframe {
      border: none;
      border-radius: 6px;
      height: 100%;
      width: 100%;
    }
  `;

  render() {
    if (this.isPopout) return;

    return html`<iframe
      class="snapshot"
      src="${this.src}"
      allow="clipboard-read; clipboard-write"
    ></iframe>`;
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

  private handleMessage!: (e: MessageEvent) => void;

  connectedCallback(): void {
    super.connectedCallback();

    if (this.popoutWindow) {
      setTimeout(() => {
        this.sendToSnapshot();
      }, 10);
    }

    this.handleMessage = (e: MessageEvent) => {
      if (e.data?.type === "waitForReduxState") {
        this.sendToSnapshot();
      }
    };
    window.addEventListener("message", this.handleMessage);
  }

  disconnectedCallback(): void {
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
