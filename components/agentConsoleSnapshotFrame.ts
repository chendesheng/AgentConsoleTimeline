import { html, css, LitElement, PropertyValues } from "lit";
import { customElement, property, query, state } from "lit/decorators.js";
import { getPopoutWindow, PopoutWindow } from "./windowManager";

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

  public static resolveSrc(src: string) {
    let res = src;

    if (src.includes("isSuperAgent=true") && src.includes("agentconsole.html")) {
      res = src.replace("agentconsole.html", "superagent.html");
    }

    if (res.includes("snapshot=true")) return res;
    else return res + "&snapshot=true";
  }

  private getSrc() {
    return AgentConsoleSnapshotFrame.resolveSrc(this.src);
  }

  private get popoutWindow(): PopoutWindow | undefined {
    return getPopoutWindow(this.getSrc());
  }

  private getSnapshotWindow() {
    return this.isPopout ? this.popoutWindow : this.iframe?.contentWindow;
  }

  public reload() {
    if (this.iframe) this.iframe.src = this.getSrc();
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
      src="${this.getSrc()}"
      allow="clipboard-read; clipboard-write"
    ></iframe>`;
  }

  private sendToSnapshot() {
    if (this.state) {
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
      if (
        e.source === this.getSnapshotWindow() &&
        e.data?.type === "waitForReduxState"
      ) {
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
