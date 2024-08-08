import { LitElement, html, css, PropertyValues } from "lit";
import { customElement, property } from "lit/decorators";

@customElement("json-diff")
export class JsonDiff extends LitElement {
  render() {
    if (this.diffResult) {
      return html`<pre class="json">${this.diffResult}</pre>`;
    } else if (this.showWaiting) {
      return html`<pre class="json">Waiting...</pre>`;
    }
  }

  protected updated(changedProperties: PropertyValues): void {
    if (changedProperties.has("source") || changedProperties.has("target")) {
      if (this.worker) {
        this.worker.terminate();
      }

      this.diffResult = "";

      this.showWaiting = false;
      setTimeout(() => {
        this.showWaiting = true;
      }, 1000);

      this.worker = new Worker(
        new URL("./jsonDiffWorker.ts", import.meta.url),
        { type: "module" }
      );
      this.worker.postMessage({
        type: "diff",
        source: this.source,
        target: this.target
      });
      this.worker.onmessage = (e) => {
        if (e.data.type === "diffResult") {
          this.diffResult = e.data.payload;
          this.showWaiting = false;
        }
      };
    }
  }

  static styles = css`
    pre.json {
      font-family: monospace;
      margin-left: 20px;
    }
  `;

  @property()
  source: string = "";

  @property()
  target: string = "";

  @property({ state: true })
  diffResult: string = "";

  @property({ state: true })
  showWaiting: boolean = false;

  private worker: Worker | null = null;
}
