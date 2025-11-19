import { html, css, LitElement, PropertyValues } from "lit";
import { customElement, property, query, state } from "lit/decorators.js";
import { getPopoutWindow, PopoutWindow } from "./windowManager";

export type ReduxStateAndActions = {
  state: string;
  actions: string[];
  time: string;
};

@customElement("agent-console-snapshot-frame")
export class AgentConsoleSnapshotFrame extends LitElement {
  @property({ type: String })
  src = "";

  // key is siteId
  @property({ type: Object })
  stateAndActions: Record<number, ReduxStateAndActions> = {};

  @property({ type: String })
  time = "";

  @property({ type: Boolean })
  isPopout = false;

  @query("iframe")
  iframe?: HTMLIFrameElement;

  public static resolveSrc(src: string) {
    let res = src;

    if (
      src.includes("isSuperAgent=true") &&
      src.includes("agentconsole.html")
    ) {
      res = src
        .replace("agentconsole.html", "superagent.html")
        .replace("&isSuperAgent=true", "");
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
      @load=${this.handleIframeLoad}
    ></iframe>`;
  }

  private sendBootstrapPopupWindow() {
    this.getSnapshotWindow()?.postMessage(
      {
        type: "popupWindowRestoreState",
        payload: JSON.stringify({
          agent: {
            language: "en",
            jwtToken: "mock",
          },
          ui: {
            mychats: {},
          },
        }),
      },
      "*",
    );
  }

  private sendToSnapshot() {
    const siteIds = Object.keys(this.stateAndActions).map(Number);
    const restoreReduxStateMessages = siteIds.map((siteId) => ({
      type: "restoreReduxState",
      payload: this.stateAndActions[siteId].state,
      time: this.time,
      siteId,
    }));
    this.dispatchRestoreReduxState(restoreReduxStateMessages);

    for (const siteId of siteIds) {
      this.dispatchActionsToSnapshot(
        siteId,
        this.stateAndActions[siteId].actions,
      );
    }
  }

  dispatchRestoreReduxState(messages: any[]) {
    if (messages.length === 0) return;

    if (messages.length === 1) {
      this.getSnapshotWindow()?.postMessage(messages[0], "*");
    } else {
      this.getSnapshotWindow()?.postMessage(messages, "*");
    }
  }

  dispatchActionsToSnapshot(siteId: number, actions: string[]) {
    if (actions.length === 0) return;

    const win = this.getSnapshotWindow();
    if (!win) return;

    for (const action of actions) {
      // console.log('dispatch action', action);
      win.postMessage(
        {
          type: "dispatchReduxAction",
          action: JSON.parse(action),
          time: this.time,
          siteId,
        },
        "*",
      );
    }
  }

  private handleMessage!: (e: MessageEvent) => void;

  // this is true when agent console page we are debugging is a popout window
  private static isPopoutWindow(href: string) {
    return href.includes("visitor-popup.html") || href.includes("chat.html");
  }

  private handleIframeLoad() {
    // when initializing a snapshot for a popout window, we need have an empty state to bootstrap the popup window
    if (AgentConsoleSnapshotFrame.isPopoutWindow(this.src)) {
      this.sendBootstrapPopupWindow();
    }
  }

  connectedCallback(): void {
    super.connectedCallback();

    if (this.popoutWindow) {
      // this is a hack, only works when 1 second is enough for child window to be loaded
      setTimeout(() => {
        if (AgentConsoleSnapshotFrame.isPopoutWindow(this.src)) {
          this.sendBootstrapPopupWindow();
        }
        setTimeout(() => {
          this.sendToSnapshot();
        }, 100);
      }, 1000);
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

  private diffActions(siteId: number, oldActions: string[]): string[] {
    const actions = this.stateAndActions[siteId].actions;
    if (oldActions.length > actions.length) {
      return [];
    }
    if (oldActions.some((action, i) => action !== actions[i])) {
      return [];
    }
    return actions.slice(oldActions.length);
  }

  updated(changed: PropertyValues<this>) {
    if (changed.has("stateAndActions")) {
      const prevStateAndActions = changed.get("stateAndActions") ?? {};
      const { added, removed, unchanged } = diffSiteIds(
        Object.keys(prevStateAndActions).map(Number),
        Object.keys(this.stateAndActions).map(Number),
      );

      // restore all sites if any site's state is changed
      if (
        added.length > 0 ||
        removed.length > 0 ||
        unchanged.some((siteId) => {
          return (
            prevStateAndActions[siteId]!.state !==
            this.stateAndActions[siteId]!.state
          );
        })
      ) {
        this.dispatchRestoreReduxState(
          Object.keys(this.stateAndActions)
            .map(Number)
            .map((siteId) => ({
              type: "restoreReduxState",
              payload: this.stateAndActions[siteId].state,
              time: this.stateAndActions[siteId].time,
              siteId,
            })),
        );
      }

      const reduxActionMessages: any[] = [];

      for (const siteId of unchanged) {
        const prevStateAndAction = prevStateAndActions[siteId]!;
        const stateAndAction = this.stateAndActions[siteId]!;

        const actions = this.diffActions(siteId, prevStateAndAction.actions);
        if (actions.length > 0) {
          reduxActionMessages.push(
            ...actions.map((action) => ({
              type: "dispatchReduxAction",
              action: JSON.parse(action),
              time: stateAndAction.time,
              siteId,
            })),
          );
        }
      }

      for (const message of reduxActionMessages) {
        this.getSnapshotWindow()?.postMessage(message, "*");
      }
      return;
    }
  }
}

const diffSiteIds = (prevSiteIds: number[], siteIds: number[]) => {
  const added = siteIds.filter((id) => !prevSiteIds.includes(id));
  const removed = prevSiteIds.filter((id) => !siteIds.includes(id));
  const unchanged = siteIds.filter((id) => prevSiteIds.includes(id));
  return { added, removed, unchanged };
};
