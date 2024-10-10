import { html, css, LitElement, PropertyValues, PropertyValueMap } from "lit";
import { customElement, property, query, state } from "lit/decorators.js";
import "./agentConsoleSnapshotFrame";
import { AgentConsoleSnapshotFrame } from "./agentConsoleSnapshotFrame";

declare global {
  var popoutWindow: Window | null;
}

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

  @query("agent-console-snapshot-frame")
  frame?: AgentConsoleSnapshotFrame;

  @state()
  private isPopout: boolean = false;

  private getSrc() {
    if (
      this.src.includes("isSuperAgent=true") &&
      this.src.includes("agentconsole.html")
    ) {
      return (
        this.src.replace("agentconsole.html", "superagent.html") +
        "&snapshot=true"
      );
    }
    return this.src + "&snapshot=true";
  }

  private get popoutWindow() {
    return globalThis.popoutWindow;
  }

  private set popoutWindow(value) {
    globalThis.popoutWindow = value;
    this.isPopout = !!value;
    this.dispatchPopoutEvent(this.isPopout);
  }

  private dispatchPopoutEvent(value: boolean) {
    this.dispatchEvent(
      new CustomEvent("popout", {
        detail: { value },
      }),
    );
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
    this.frame?.reload();
  }

  private handleClickPopoutButton() {
    if (this.popoutWindow) {
      this.popoutWindow.close();
      this.popoutWindow = null;
    }
    this.popoutWindow = window.open(this.getSrc(), "snapshot");
    // FIXME: this is a workaround, the agent console should send waitForReduxState message
    if (this.popoutWindow) {
      this.popoutWindow.onload = () => {
        window.postMessage({ type: "waitForReduxState" }, "*");
      };
    }
    // console.log("popout window", this.popoutWindow);
  }

  private handleClickRestorePopoutButton() {
    if (this.popoutWindow) {
      this.popoutWindow.close();
      this.popoutWindow = null;
    }
  }

  private handleSrcInputBlur(e: UIEvent) {
    const ele = e.target as HTMLInputElement;
    const [prefix, rest] = AgentConsoleSnapshot.splitSrc(this.getSrc());
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
    const src = this.getSrc();
    const [prefix, rest] = AgentConsoleSnapshot.splitSrc(src);
    return html`<div class="header">
        <button title="Reload" @click=${this.handleClickReloadButton}>⟳</button>
        <span class="src" contenteditable @blur=${this.handleSrcInputBlur}
          >${prefix}</span
        >${rest}
        <button title="Popout" @click=${this.handleClickPopoutButton}>🡽</button>
      </div>
      ${this.isPopout
        ? html`<button
            class="snapshot"
            @click=${this.handleClickRestorePopoutButton}
          >
            Restore Popout
          </button>`
        : html`<agent-console-snapshot-frame
            class="snapshot"
            .src=${src}
            .actions=${this.actions}
            .state=${this.state}
            .time=${this.time}
            .isPopout=${false}
          />`}`;
  }

  connectedCallback(): void {
    super.connectedCallback();

    this.isPopout = !!this.popoutWindow;
  }
}
