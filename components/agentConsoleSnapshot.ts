import { html, css, LitElement, PropertyValues, PropertyValueMap } from "lit";
import { customElement, property, query } from "lit/decorators.js";

@customElement("agent-console-snapshot")
export class AgentConsoleSnapshot extends LitElement {
  @property()
  src = "";
  @property()
  state = "";
  @property()
  time = "";

  @query("iframe")
  iframe!: HTMLIFrameElement;

  static styles = css`
    iframe {
      border-radius: 4px;
      box-shadow: 0 0 10px 0 rgba(0, 0, 0, 0.1);
      border: none;
      height: 100%;
      width: 100%;
    }
  `;

  render() {
    return html`<iframe src="${this.src}"></iframe>`;
  }

  sendToIframe() {
    if (this.iframe?.contentWindow) {
      this.iframe.contentWindow.postMessage(
        { type: "restoreReduxState", payload: this.state, time: this.time },
        "*"
      );
    }
  }

  connectedCallback(): void {
    super.connectedCallback();
    const handleMessage = (e: MessageEvent) => {
      if (e.data?.type === "waitForReduxState") {
        this.sendToIframe();
        window.removeEventListener("message", handleMessage);
      }
    };
    window.addEventListener("message", handleMessage);
  }

  updated(changed: PropertyValues<this>) {
    if (changed.has("state")) {
      this.sendToIframe();
    }
  }
}
