import { html, css, LitElement, PropertyValues, PropertyValueMap } from "lit";
import { customElement, property, query, state } from "lit/decorators.js";
import "./agentConsoleSnapshotFrame";
import { AgentConsoleSnapshotFrame } from "./agentConsoleSnapshotFrame";

declare global {
  var popoutWindows: undefined | Record<string, Window>;
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

  private get popoutWindowPathname() {
    return new URL(this.src).pathname;
  }

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

  private get popoutWindow(): Window | undefined {
    return globalThis.popoutWindows?.[this.popoutWindowPathname];
  }

  private set popoutWindow(value: Window | null) {
    if (value) {
      globalThis.popoutWindows ??= {};
      globalThis.popoutWindows[this.popoutWindowPathname] = value;
    } else if (globalThis.popoutWindows) {
      delete globalThis.popoutWindows[this.popoutWindowPathname];
    }

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
      border-radius: 6px;
      border: none;
      outline: solid 0.1px hsl(0, 0%, 33%);
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
      cursor: default;
    }
    .header button {
      flex: none;
      color: var(--text-color-secondary);
      font-size: 20px;
      padding: 0;
      margin: 0;
      height: 18px;
      line-height: 18px;
      background: none;
      border: none;
      appearance: none;
      cursor: pointer;
      margin-right: 4px;
      outline: none;
    }
    .header button:hover,
    .header button:focus,
    .header button:active {
      color: var(--text-color);
    }
    .header .src {
      flex: none;
      cursor: text;
      border: none;
    }
    .header .src:hover,
    .header .src:focus {
      border: none;
      border-bottom: solid 1px currentColor;
      outline: none;
      margin-bottom: -1px;
    }
    .header button.popout {
      font-size: 12px;
      display: flex;
      justify-content: center;
      align-items: center;
      padding: 0;
      height: 12px;
      margin-left: 2px;
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
        <button
          class="popout"
          title="Popout"
          @click=${this.handleClickPopoutButton}
        >
          🡽
        </button>
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
