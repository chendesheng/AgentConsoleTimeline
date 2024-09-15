import "@alenaksu/json-viewer";
import { JsonViewer } from "@alenaksu/json-viewer/dist/JsonViewer";
import { html, css, LitElement, PropertyValues } from "lit";
import { customElement, property, query, state } from "lit/decorators.js";
import { sort as sortKeys } from "json-keys-sort";

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
  private _jsonViewer!: JsonViewer;

  @query("input")
  private _input?: HTMLInputElement;

  private _filter = "";

  static styles = css`
    .actions {
      line-height: 10px;
      font-size: 10px;
      top: 10px;
      position: relative;
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

    json-viewer::part(key) {
      margin-right: 1ch;
    }
    json-viewer::part(key)::before {
      position: relative;
      left: 1px;
      margin-right: 2px;
      top: -1px;
    }
  `;

  private handleCopy() {
    navigator.clipboard.writeText(this.data);
  }
  private handleExpandAll() {
    this._jsonViewer.expandAll();
  }
  private handleCollapseAll() {
    this._jsonViewer.collapseAll();
  }
  private handleInput(e: Event) {
    const input = e.target as HTMLInputElement;
    this._jsonViewer.expandAll();
    this._jsonViewer.filter(new RegExp(input.value, "i"));
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
  private _showFilter = false;

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
                    Filter
                  </button>
                </div>
              `}
        </div>
        <json-viewer .data=${sortKeys(JSON.parse(this.data))}></json-viewer>`;
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
    super.update(changedProperties);
  }

  protected updated(changedProperties: PropertyValues): void {
    super.updated(changedProperties);
    if (changedProperties.has("data")) {
      this._jsonViewer.expandAll();
      this._showFilter = false;
      this._filter = "";
      if (this.initialExpanded) {
        this._jsonViewer.expandAll();
      } else {
        this._jsonViewer.collapseAll();
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
        this._jsonViewer.resetFilter();
      }
    }
  }
}
