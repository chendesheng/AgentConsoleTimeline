import { JsonViewer } from "@alenaksu/json-viewer/JsonViewer.js";
import { html, css, LitElement, PropertyValues } from "lit";
import { customElement, property, query, state } from "lit/decorators.js";
import { sort as sortKeys } from "json-keys-sort";

customElements.define("json-viewer", JsonViewer);

/*
customElements.define(
  "json-viewer",
  class extends JsonViewer {
    static styles = [
      JsonViewer.styles,
      css`
        a {
          color: var(--string-color);
          text-decoration: underline;
        }
      `,
    ];

    static customRenderer(value: any, path: string) {
      if (typeof value === "string") {
        if (URL.canParse(value)) {
          return html`"<a href="${value}" target="_blank">${value}</a>"`;
        } else if (value.startsWith("<div>")) {
          // set inner html
          const div = document.createElement("div");
          div.innerHTML = value;
          return div;
        }
      }

      return super.customRenderer(value, path);
    }
  },
);
*/

declare global {
  interface HTMLElementTagNameMap {
    "json-viewer": JsonViewer;
  }
}

declare global {
  interface HTMLElementTagNameMap {
    "json-viewer": JsonViewer;
  }
}

@customElement("json-tree")
export class JsonTree extends LitElement {
  @property({ type: String })
  data = "";

  @property({ type: Boolean })
  initialExpanded = false;

  @query("json-viewer")
  private _jsonViewer?: JsonViewer;

  @query("input")
  private _input?: HTMLInputElement;

  private _filter = "";

  static styles = css`
    .actions {
      line-height: 10px;
      font-size: 10px;
      margin-top: 10px;
      margin-bottom: 2px;
    }
    .actions button {
      appearance: none;
      -webkit-appearance: none;
      all: unset;
      cursor: pointer;
      opacity: 0.5;
      user-select: none;
    }
    .actions button:hover,
    .actions button:focus,
    .actions button:focus-visible {
      opacity: 0.8;
    }
    .actions button:active {
      opacity: 0.5;
    }

    .actions input {
      color: var(--text-color);
      border: none;
      background: transparent;
      outline: none;
      width: 200px;
      font-size: 10px;
      padding: 0 0 0 1px;
      height: 10px;
      line-height: 10px;
      box-shadow: 0 1px 0 0 var(--border-color);
    }

    json-viewer {
      --property-color: var(--text-color);
      --string-color: var(--syntax-highlight-string-color);
      --number-color: var(--syntax-highlight-number-color);
      --boolean-color: var(--syntax-highlight-boolean-color);
      --null-color: var(--syntax-highlight-symbol-color);
      --background-color: transparent;
      line-height: 1.5;
      --font-family: menlo, monospace;
      overflow-wrap: break-word;
    }

    json-viewer::part(key)::before {
      position: relative;
      left: -0.7px;
      top: 1px;
    }
    json-viewer::part(object) {
      margin-block: 0;
    }
  `;

  private handleCopy() {
    navigator.clipboard.writeText(this.data);
  }
  private handleExpandAll() {
    this._jsonViewer?.expandAll();
  }
  private handleCollapseAll() {
    this._jsonViewer?.collapseAll();
  }
  private handleInput(e: Event) {
    const input = e.target as HTMLInputElement;
    this._jsonViewer?.expandAll();
    this._jsonViewer?.filter(new RegExp(input.value, "i"));
  }

  private handleShowFilter() {
    this._showFilter = true;
  }

  private handleKeyDown(e: KeyboardEvent) {
    if (e.key === "Escape") {
      this._showFilter = false;
    }
  }

  @state()
  private _showNestedJson: boolean = false;
  private handleParseNestedJson() {
    this._showNestedJson = !this._showNestedJson;
  }

  @state()
  private _showFilter = false;

  private _parsedData?: any;
  parseData() {
    if (this._parsedData) {
      return this._parsedData;
    }

    try {
      let json = JSON.parse(this.data);
      if (this._showNestedJson) {
        json = tryParseNestedJson(json);
      }
      json = sortKeys(json);
      this._parsedData = json;

      return json;
    } catch (e) {
      this._parsedData = this.data;
      return this.data;
    }
  }

  render() {
    try {
      return html`<div class="actions">
          ${this._showFilter
            ? html`<input
                type="search"
                @input="${this.handleInput}"
                @keydown="${this.handleKeyDown}"
                placeholder="Filter"
              />`
            : html`
                <div style="display: contents">
                  <button tabindex="0" @click=${this.handleCopy}>Copy</button
                  >&nbsp;<button tabindex="0" @click=${this.handleCollapseAll}>
                    Collapse</button
                  >&nbsp;<button tabindex="0" @click=${this.handleExpandAll}>
                    Expand</button
                  >&nbsp;<button tabindex="0" @click=${this.handleShowFilter}>
                    Filter</button
                  >&nbsp;
                  <button tabindex="0" @click=${this.handleParseNestedJson}>
                    ${this._showNestedJson ? "▼" : "►"} Nested
                  </button>
                </div>
              `}
        </div>
        <json-viewer .data=${this.parseData()}></json-viewer>`;
    } catch (e: any) {
      console.error(e);
      return html`<div style="margin-top: 10px;">
        <pre>${this.data}</pre>
      </div>`;
    }
  }

  protected update(changedProperties: PropertyValues): void {
    if (changedProperties.has("_showFilter")) {
      if (!this._showFilter) {
        this._filter = this._input?.value || "";
      }
    }
    if (
      changedProperties.has("data") ||
      changedProperties.has("_showNestedJson")
    ) {
      this._parsedData = undefined;
    }
    super.update(changedProperties);
  }

  protected updated(changedProperties: PropertyValues): void {
    super.updated(changedProperties);
    if (changedProperties.has("data")) {
      this._jsonViewer?.expandAll();
      this._showFilter = false;
      this._filter = "";
      if (this.initialExpanded) {
        this._jsonViewer?.expandAll();
      } else {
        this._jsonViewer?.collapseAll();
      }
    }

    if (changedProperties.has("_showFilter")) {
      if (this._showFilter) {
        if (this._input) {
          this._input.value = this._filter;
          // apply filter by triggering input event
          this._input.dispatchEvent(new Event("input", { bubbles: true }));
          this._input?.select();
          this._input.focus();
        }
      } else {
        this._jsonViewer?.resetFilter();
      }
    }
  }
}

const equals = (a: (string | number)[], b: (string | number)[]) => {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) return false;
  }
  return true;
};
const isTimestamp = (o: any, path: (string | number)[] = []) => {
  const timestampPath = [
    ["agent", "loggedInTime"],
    ["config", "preference", "lastStatusChangedTime"],
    ["config", "preference", "loginTime"],
    ["visitor", "lastGetSegmentChangedTime"],
  ];
  for (const p of timestampPath) {
    if (equals(path, p)) {
      return typeof o === "number";
    }
  }
  return false;
};

function tryParseNestedJson(o: any, path: (string | number)[] = []): any {
  if (isTimestamp(o, path)) {
    return new Date(o).toString();
  }

  if (typeof o === "string") {
    if (
      o.startsWith(
        "eyJhbGciOiJodHRwOi8vd3d3LnczLm9yZy8yMDAxLzA0L3htbGRzaWctbW9yZSNyc2Etc2hhMjU2IiwidHlwIjoiSldUIn0",
      )
    ) {
      return parseToken(o);
    }
    if (/^\/Date\((\d+)\)\/$/.test(o)) {
      return new Date(parseInt(o.match(/\/Date\((\d+)\)\//)![1])).toString();
    }

    try {
      return tryParseNestedJson(JSON.parse(o), path);
    } catch (e) {
      return o;
    }
  } else if (Array.isArray(o)) {
    return o.map((value, index) => tryParseNestedJson(value, [...path, index]));
  } else if (typeof o === "object" && o !== null) {
    const result: any = {};
    for (const key of Object.keys(o)) {
      result[key] = tryParseNestedJson(o[key], [...path, key]);
    }
    return result;
  } else {
    return o;
  }
}

function parseToken(o: string) {
  const token = JSON.parse(window.atob(o.split(".")[1]));
  if (token.exp) token.exp = new Date(token.exp * 1000).toString();
  if (token.nbf) token.nbf = new Date(token.nbf * 1000).toString();
  return token;
}
