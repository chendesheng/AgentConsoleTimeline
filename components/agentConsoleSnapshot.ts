import {
  html,
  svg,
  css,
  LitElement,
  PropertyValues,
  PropertyValueMap,
  unsafeCSS,
} from "lit";
import { customElement, property, query, state } from "lit/decorators.js";
import "./agentConsoleSnapshotFrame";
import { AgentConsoleSnapshotFrame } from "./agentConsoleSnapshotFrame";
import { getPopoutWindow, openWindow, PopoutWindow } from "./windowManager";
import upDownArrowsUrl from "../assets/images/UpDownArrows.svg";
import popupUrl from "../assets/images/Popup.svg";
import popinUrl from "../assets/images/Popin.svg";
import reloadToolbar from "../assets/images/ReloadToolbar.svg";

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

  @property({ type: String })
  pageName = "";

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

  private get popoutWindow(): PopoutWindow | undefined {
    return getPopoutWindow(this.src);
  }

  private setIsPopout(value: boolean) {
    this.isPopout = value;
    this.dispatchPopoutEvent(value);
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
      align-items: baseline;
      color: var(--text-color);
      height: 20px;
      cursor: default;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
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
      margin-right: 2px;
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
      color: var(--text-color-active);
    }
    .header button.popout {
      font-size: 12px;
      display: flex;
      justify-content: center;
      align-items: center;
      padding: 0;
      height: 12px;
      display: block;
      width: 12px;
      height: 12px;
      position: relative;
      top: 1px;
    }

    .select {
      position: relative;
      border-radius: 2px;
      padding: 2px;
      display: flex;
      align-items: center;
      justify-content: center;
      bottom: -2px;
    }

    .select:hover,
    .select:focus,
    .select:focus-within {
      background-color: var(--selected-background-color);
    }

    .select > select {
      border: none;
      outline: none;
      appearance: none;
      background: none;
      opacity: 0;
      padding: 0;
      margin: 0;
      position: absolute;
      inset: 0;
    }

    .icon {
      display: inline-block;
      fill: currentColor;
      vertical-align: middle;
      overflow: hidden;
      flex: none;
      color: currentColor;
      background-color: currentColor;
    }

    .icon.reload-toolbar {
      mask: url("${unsafeCSS(reloadToolbar)}");
      width: 10px;
      height: 10px;
      position: relative;
      top: 1px;
    }

    .icon.popin,
    .icon.popup {
      width: 14px;
      height: 14px;
      position: relative;
      top: 1px;
    }
    .icon.popin {
      mask: url("${unsafeCSS(popinUrl)}");
    }

    .icon.popup {
      mask: url("${unsafeCSS(popupUrl)}");
    }

    .select:after {
      content: url("${unsafeCSS(upDownArrowsUrl)}");
      width: 5px;
      height: 12px;
      pointer-events: none;
    }
  `;

  private handleClickReloadButton() {
    this.frame?.reload();
    this.popoutWindow?.reload();
  }

  private handleClickPopoutButton() {
    if (this.popoutWindow) {
      this.popoutWindow.close();
      this.setIsPopout(false);
    }

    openWindow(this.getSrc(), `snapshot-${this.pageName}`);
    this.setIsPopout(true);

    if (this.popoutWindow) {
      this.popoutWindow.onClose(() => {
        this.handleClickRestorePopoutButton();
      });
    }
    // console.log("popout window", this.popoutWindow);
  }

  private handleClickRestorePopoutButton() {
    if (this.popoutWindow) {
      this.popoutWindow.close();
      this.setIsPopout(false);
    }
  }

  private fireSrcChangeEvent(value: string) {
    const [prefix, rest] = AgentConsoleSnapshot.splitSrc(this.getSrc());
    if (value.trim() !== prefix.trim()) {
      this.dispatchEvent(
        new CustomEvent("srcChange", {
          detail: { value: `${value.trim()}${rest}` },
        }),
      );
    }
  }

  private handleSrcInputBlur(e: UIEvent) {
    const ele = e.target as HTMLInputElement;
    this.fireSrcChangeEvent(ele.textContent!);
  }

  private handleSrcSelectInput(e: UIEvent) {
    const ele = e.target as HTMLSelectElement;
    this.fireSrcChangeEvent(ele.value);
  }

  private handleKeyPress(e: KeyboardEvent) {
    if (e.key === "Enter") {
      e.preventDefault();
      const ele = e.target as HTMLInputElement;
      this.fireSrcChangeEvent(ele.textContent!);
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
        <button
          class="reload"
          title="Reload"
          @click=${this.handleClickReloadButton}
        >
          <i class="icon reload-toolbar"></i>
        </button>
        <span
          class="src"
          contenteditable
          @keypress=${this.handleKeyPress}
          @blur=${this.handleSrcInputBlur}
          >${prefix}</span
        >
        <div class="select">
          <select @input=${this.handleSrcSelectInput}>
            ${platformPrefixes.map(
              (p) =>
                html`<option value=${p} ?selected=${p === prefix}>
                  ${p}
                </option>`,
            )}
          </select>
        </div>
        <span>${rest}</span>
        <button
          title=${this.isPopout ? "Restore Popout" : "Popout"}
          @click=${this.handleClickPopoutButton}
        >
          <i class=${this.isPopout ? "icon popin" : "icon popup"}></i>
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

  protected updated(changedProperties: PropertyValues): void {
    if (changedProperties.get("src") && this.popoutWindow) {
      this.popoutWindow?.reload(this.getSrc());
    }
  }
}

const platformPrefixes = [
  "https://canvasdash.testing.comm100dev.io",
  "https://customreportdash.testing.comm100dev.io",
  "https://global9dash.testing.comm100dev.io",
  "https://gptbotdash.testing.comm100dev.io",
  "https://internal7dash.testing.comm100dev.io",
  "https://livechat3dash.testing.comm100dev.io",
  "https://livechat6dash.testing.comm100dev.io",
  "https://livehelp100dash.testing.comm100dev.io",
  "https://ticketing2dash.testing.comm100dev.io",
  "https://ticketing3dash.testing.comm100dev.io",
  "https://van100dash.testing.comm100dev.io",
  "http://localhost:32400",
  "https://dash11staging.comm100.io",
  "https://dash11.comm100.io",
  "https://dash12.comm100.io",
  "https://dash13.comm100.io",
  "https://dash15.comm100.io",
  "https://dash17.comm100.io",
];
