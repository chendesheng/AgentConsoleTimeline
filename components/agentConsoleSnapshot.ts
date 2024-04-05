import { html, css, LitElement, PropertyValues, PropertyValueMap } from "lit";
import { customElement, property, query } from "lit/decorators.js";

@customElement("agent-console-snapshot")
export class AgentConsoleSnapshot extends LitElement {
  @property()
  src = "";
  @property()
  state = "";

  @query("iframe")
  iframe!: HTMLIFrameElement;

  static styles = css`
    iframe {
      width: calc(100% - 40px);
      height: calc(100% - 40px);
      margin: 20px;
      border-radius: 4px;
      box-shadow: 0 0 10px 0 rgba(0, 0, 0, 0.1);
    }
  `;

  render() {
    return html`<iframe src="${this.src}" frameborder="0" />`;
  }

  connectedCallback(): void {
    super.connectedCallback();
    const handleMessage = (e: MessageEvent) => {
      if (this.iframe?.contentWindow && e.data?.type === "waitForReduxState") {
        this.iframe.contentWindow.postMessage(
          { type: "restoreReduxState", payload: this.state },
          "*",
        );
        window.removeEventListener("message", handleMessage);
      }
    };
    window.addEventListener("message", handleMessage);
  }

  updated(changed: PropertyValues<this>) {
    if (changed.has("state")) {
      // console.log("updated");
      // console.log(this.state);
      this.iframe?.contentWindow?.postMessage(
        { type: "restoreReduxState", payload: this.state },
        "*",
      );
    }
  }
}
