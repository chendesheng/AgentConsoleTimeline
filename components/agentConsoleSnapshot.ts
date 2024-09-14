import { html, css, LitElement, PropertyValues, PropertyValueMap } from "lit";
import { customElement, property, query } from "lit/decorators.js";

@customElement("agent-console-snapshot")
export class AgentConsoleSnapshot extends LitElement {
  @property()
  src = "";
  @property()
  state = "";

  @property()
  actions = "";

  @property()
  time = "";

  @query("iframe")
  iframe!: HTMLIFrameElement;

  static styles = css`
    :host {
      display: flex;
      flex-flow: column;
      gap: 4px;
    }
    iframe {
      border-radius: 4px;
      box-shadow: 0 0 10px 0 rgba(0, 0, 0, 0.1);
      border: none;
      height: 100%;
      width: 100%;
      flex: auto;
    }
    .header {
      flex: none;
      display: flex;
      gap: 4px;
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
    }
    .header button:hover,
    .header button:active {
      opacity: 0.8;
    }
    .header .href {
      flex: auto;
      opacity: 0.5;
    }
  `;

  private handleClickReloadButton() {
    this.iframe.src = this.src;
  }

  render() {
    return html`<div class="header">
      <button title="Reload" @click=${this.handleClickReloadButton}>⟳</button>
      <div class="href">${this.src}</div>
    </div>
    <iframe src="${this.src}" allow="clipboard-read; clipboard-write"></iframe>`;
  }

  private sendToIframe() {
    if (this.state) {
      console.log('restore state');
      this.iframe.contentWindow?.postMessage(
        { type: "restoreReduxState", payload: this.state, time: this.time },
        "*"
      );
    }
    this.dispatchActionsToIframe(AgentConsoleSnapshot.parseActions(this.actions));
  }

  static parseActions(actions: string): string[] {
    return actions ? JSON.parse(actions) : [];
  }

  dispatchActionsToIframe(actions: string[]) {
    if (!this.iframe.contentWindow) return;

    for (const action of actions) {
      console.log('dispatch action', action);
      this.iframe.contentWindow.postMessage(
        { type: "dispatchReduxAction", action: JSON.parse(action), time: this.time },
        "*"
      );
    }
  }

  handleMessage!: (e: MessageEvent) => void;

  connectedCallback(): void {
    super.connectedCallback();
    this.handleMessage = (e: MessageEvent) => {
      if (e.data?.type === "waitForReduxState") {
        this.sendToIframe();
      }
    };
    window.addEventListener("message", this.handleMessage);
  }

  disconnectedCallback(): void {
    window.removeEventListener("message", this.handleMessage);
  }

  private diffActions(oldActionsStr: string): string[] | undefined {
    const oldActions = AgentConsoleSnapshot.parseActions(oldActionsStr) as string[];
    const actions = AgentConsoleSnapshot.parseActions(this.actions);
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
      if (actions) this.dispatchActionsToIframe(actions);
      else this.sendToIframe();
      return;
    }

    if (prev.has("state")) {
      this.sendToIframe();
    }
  }
}
