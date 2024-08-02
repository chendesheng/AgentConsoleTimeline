import { LitElement, html, css } from "lit";
import { customElement, property } from "lit/decorators";
import { diffString } from "json-diff";

@customElement("json-diff")
export class JsonDiff extends LitElement {
  render() {
    // console.log(JSON.parse(this.source), JSON.parse(this.target));
    const t = JSON.parse(this.target);
    const s = JSON.parse(this.source);

    // config.salesforce is too large
    // if (t.config.salesforce) delete t.config.salesforce;
    // if (s.config.salesforce) delete s.config.salesforce;

    // TODO: use worker to diff
    const diff = diffString(t, s, {
      color: false,
    });
    return html`<pre class="json">${diff || "No Changes"}</pre>`;
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
}

