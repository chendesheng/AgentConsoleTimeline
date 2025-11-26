import {
  css,
  html,
  HTMLTemplateResult,
  LitElement,
  PropertyValues,
  unsafeCSS,
} from "lit";
import { customElement, property, query, state } from "lit/decorators.js";
import typeIcons from "../assets/images/TypeIcons.svg";
import showIcon from "../assets/images/Show.svg";
import circleIcon from "../assets/images/Circle.svg";
import { sort as sortKeys } from "json-keys-sort";
import { keyed } from "lit/directives/keyed.js";
import {
  ACTION_ROW_HEIGHT,
  clearFilter,
  filterTree,
  getItemByPath,
  isLeaf,
  JsonTreeItem,
  jsonType,
  ROW_HEIGHT,
  setExpanded,
} from "./jsonTree/model";
import { jsonSummary } from "./jsonTree/tokenizer";
import { leafValueRenderer } from "./jsonTree/leafValurRender";
import { tryParseNestedJson } from "./jsonTree/nested";

function escapeRegExp(str: string) {
  return str.replace(/[-\/\\^$*+?.()|[\]{}]/g, "\\$&");
}

const jsonToTree = (
  json: object,
  path: string[],
  options: {
    isArrayChild: boolean;
    soundUrl: string;
    campaignPreviewUrl: string;
    controlPanelUrl: string;
    parentJson?: object;
  },
): JsonTreeItem => {
  const isArrayChild = options.isArrayChild;
  const key = path[path.length - 1];
  const pathStr = path.join(".");
  if (json === null) {
    return {
      value: json,
      key,
      path,
      pathStr,
      summary: jsonSummary(json),
      type: "null",
      isArrayChild,
      valueRender: html`<span class="value null">null</span>`,
    };
  } else if (Array.isArray(json)) {
    const children = json.map((value, index) =>
      jsonToTree(value, [...path, index.toString()], {
        ...options,
        isArrayChild: true,
      }),
    );
    return {
      children,
      value: json,
      key,
      path,
      pathStr,
      summary: jsonSummary(json),
      type: "array",
      isArrayChild,
    };
  } else if (typeof json === "object" && json !== null) {
    const children = Object.entries(json).map(
      ([key, value]): JsonTreeItem =>
        jsonToTree(value, [...path, key], {
          ...options,
          isArrayChild: false,
          parentJson: json,
        }),
    );
    return {
      children,
      value: json,
      key,
      path,
      pathStr,
      summary: jsonSummary(json),
      type: "object",
      isArrayChild,
    };
  } else {
    return {
      value: json,
      key,
      path,
      pathStr,
      summary: jsonSummary(json),
      type: jsonType(json),
      isArrayChild,
      valueRender: leafValueRenderer(json, pathStr, options),
    };
  }
};

@customElement("json-tree")
export class JsonTree extends LitElement {
  @property({ type: String })
  data: string = "";

  @property({ type: Array })
  trackedPaths: string[] = [];

  @property({ type: Boolean })
  disableTrackingPath = false;

  @state()
  private _tree!: JsonTreeItem;
  @state()
  private _showFilter = false;
  @query("div.actions input")
  private _input?: HTMLInputElement;
  private get _hasFilter() {
    return !!this._input?.value?.length;
  }
  @state()
  private _filter = "";
  @query("div.actions button:last-child")
  private _filterButton?: HTMLButtonElement;

  @state()
  private _visibleStartRowIndex = 0;
  @state()
  private _visibleRows = 10;

  @state()
  private _showNestedJson: boolean = false;
  private handleParseNestedJson() {
    this._showNestedJson = !this._showNestedJson;
  }

  private _renderRowIndex = 0;
  private _totalVisibleRows = 0;

  private generateTree() {
    const reduxState: any = sortKeys(JSON.parse(this.data));
    const siteId = reduxState.agent?.siteId;
    const chatServerUrl = reduxState.config?.settings?.urls?.chatServer;
    const controlPanelUrl = reduxState.config?.settings?.urls?.controlPanel;
    this._tree = jsonToTree(
      this._showNestedJson ? tryParseNestedJson(reduxState) : reduxState,
      [],
      {
        isArrayChild: false,
        soundUrl: `${chatServerUrl}/DBResource/DBSound.ashx?soundId={soundId}&siteId=${siteId}`,
        // https://livechat3dash.testing.comm100dev.io/frontEnd/livechatpage/assets/livechat/previewpage/?campaignId=23daa136-1361-44aa-bf52-8dc92d8a3925&siteId=10008&lang=en
        campaignPreviewUrl: `${controlPanelUrl}/frontEnd/livechatpage/assets/livechat/previewpage/?campaignId={campaignId}&siteId=${siteId}&lang=en`,
        // https://dash11.comm100.io/ui/10100000/livechat/campaign/installation/?scopingcampaignid=28f5d50f-45f8-401e-beac-283e2d67a7b3
        controlPanelUrl: `${controlPanelUrl}/ui/${siteId}`,
      },
    );
    this._tree.expanded = true;
    this._showFilter = false;
  }

  static styles = css`
    :host {
      flex-direction: column;
      gap: 0.3em;
      position: relative;
      overflow-y: auto;
      overflow-x: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    :host > div {
      width: 100%;
      position: relative;
    }
    button {
      all: unset;
      cursor: pointer;
      user-select: none;
    }
    a.avatar {
      font-size: 0;
      height: ${ROW_HEIGHT}px;
    }
    a.avatar img {
      border-radius: 100%;
    }
    .label {
      display: flex;
      align-items: center;
      gap: 4px;
      height: ${ROW_HEIGHT}px;
      line-height: ${ROW_HEIGHT}px;
      white-space: nowrap;
    }
    div[role="treeitem"] {
      line-height: 1.5;
    }
    .arrow-right.invisible {
      visibility: hidden;
    }
    .arrow-right {
      display: inline-block;
      width: 0;
      height: 0;
      border-top: 0.4em solid transparent;
      border-bottom: 0.4em solid transparent;
      border-left: 0.7em solid currentColor;
      color: var(--text-color-secondary);
    }

    .arrow-right.expanded {
      transform: rotate(90deg);
    }

    .icon {
      display: inline-block;
      width: 1.2em;
      height: 1.2em;
      background-size: 100% 100%;
      background-repeat: no-repeat;
      background-position: center;
      flex: none;
    }

    button.preview {
      display: inline-block;
      width: 1.2em;
      height: 1.2em;
      flex: none;
      mask: url("${unsafeCSS(showIcon)}") no-repeat center;
      vertical-align: middle;
      background-color: var(--text-color-secondary);
    }
    .icon.object {
      background: url("${unsafeCSS(typeIcons)}#TypeObject-dark");
    }
    .icon.array {
      background: url("${unsafeCSS(typeIcons)}#TypeObject-dark");
    }
    .icon.string {
      background: url("${unsafeCSS(typeIcons)}#TypeString-dark");
    }
    .icon.number {
      background: url("${unsafeCSS(typeIcons)}#TypeNumber-dark");
    }
    .icon.boolean {
      background: url("${unsafeCSS(typeIcons)}#TypeBoolean-dark");
    }
    .icon.null {
      background: url("${unsafeCSS(typeIcons)}#TypeNull-dark");
    }
    .key,
    .value {
      cursor: default;
    }
    .key.index {
      color: var(--text-color-secondary);
      text-align: right;
      width: 3ch;
      flex: none;
      margin-right: 1ch;
    }
    .value.key {
      color: var(--syntax-highlight-boolean-color);
    }
    .value.string {
      color: var(--syntax-highlight-string-color);
    }
    .value.string a {
      color: inherit;
    }
    .value.count {
      color: var(--text-color-secondary);
    }
    .value.number {
      color: var(--syntax-highlight-number-color);
    }
    .value.boolean {
      color: var(--syntax-highlight-boolean-color);
    }
    .value.null {
      color: var(--syntax-highlight-boolean-color);
    }
    .value.array {
      color: var(--syntax-highlight-object-color);
    }
    .value.object {
      color: var(--syntax-highlight-object-color);
    }

    .actions {
      font-size: 10px;
      height: ${ACTION_ROW_HEIGHT}px;
      line-height: ${ACTION_ROW_HEIGHT}px;
      position: sticky;
      z-index: 1;
      top: 0;
      background-color: var(--background-color);
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
      font-size: inherit;
      padding: 0 0 0 1px;
      box-shadow: 0 1px 0 0 var(--border-color);
    }
    .html-preview {
      position: fixed;
      margin: 0;
      inset: unset;
      border: none;
      padding: 8px;
      border-radius: 8px;
      box-shadow: 0px 0px 4px 0px var(--border-color);
      background-color: var(--background-color);
    }
    .html-preview.controlPanelLogoCodeSnippet a[role="button"] {
      margin-top: unset !important;
      margin-bottom: unset !important;
    }
    .html-preview.agentConsoleLogoCodeSnippet a {
      margin: unset !important;
    }
    input[type="color"] {
      height: 1em;
      width: 1em;
      padding: 0;
      vertical-align: middle;
    }
    input[type="color" i]::-webkit-color-swatch-wrapper {
      padding: 0;
    }
    button.play-sound {
      all: unset;
      cursor: pointer;
      user-select: none;
      width: 1em;
      height: 1em;
      margin-right: 3px;
      display: inline-flex;
      align-items: center;
      justify-content: center;
      border: solid 1px currentColor;
      border-radius: 100%;
    }

    button.play-sound:after {
      content: "▶";
      position: relative;
      left: 1px;
    }

    button.play-sound.playing {
      pointer-events: none;
      opacity: 0.4;
    }

    button.play-sound.playing:after {
      content: "⏹";
      position: unset;
      top: unset;
      left: unset;
    }

    button.tracking {
      cursor: pointer;
      color: var(--text-color-secondary);
      position: absolute;
      display: none;
      transform: translateX(-100%);
      mask: url("${unsafeCSS(circleIcon)}") no-repeat center;
      mask-size: 50% 50%;
      background-color: var(--text-color-secondary);
      width: 1em;
      height: 1em;
    }

    button.tracking.no-expand-arrow {
      transform: unset;
    }

    .label:hover button.tracking {
      display: block;
      opacity: 0.6;
    }

    button.tracking.enable-tracking,
    .label:hover button.tracking.enable-tracking {
      display: block;
      opacity: 1;
    }

    .visible-rows {
      position: absolute;
      display: flex;
      flex-direction: column;
    }
  `;

  private handleClick(event: MouseEvent) {
    const pathStr = (event.currentTarget as HTMLElement).getAttribute(
      "data-path",
    );
    const path = pathStr === "" ? [] : pathStr?.split(".");
    if (path) {
      const item = getItemByPath(this._tree, path);
      if (item) {
        item.expanded = !item.expanded;
        this.requestUpdate();
      }
    }
  }

  private handleCopy() {
    navigator.clipboard.writeText(this.data);
  }
  private handleExpandAll() {
    setExpanded(this._tree, true);
    this.requestUpdate();
  }
  private handleCollapseAll() {
    setExpanded(this._tree, false);
    // root is always expanded
    this._tree.expanded = true;
    this.requestUpdate();
  }
  private handleInput(e: Event) {
    if (!this._showFilter) return;
    if (this._input?.value?.length === 0) {
      clearFilter(this._tree);
      this.requestUpdate();
      return;
    }

    const input = e.target as HTMLInputElement;
    const hasCapitalLetter = input.value.match(/[A-Z]/);
    const filter = new RegExp(
      escapeRegExp(input.value),
      hasCapitalLetter ? "" : "i",
    );
    filterTree(this._tree, filter);
    this.requestUpdate();
  }

  private handleShowFilter() {
    this._showFilter = true;
  }

  private handleKeyDown(e: KeyboardEvent) {
    if (e.key === "Escape") {
      this._showFilter = false;
    }
  }

  private handleBlur(e: Event) {
    if (this._input?.value?.length === 0) {
      this._showFilter = false;
    }
  }

  private static keyPrefix(item: JsonTreeItem): string | undefined {
    return item.key ? `${item.key}: ` : undefined;
  }

  private static totalVisibleRows(
    item: JsonTreeItem,
    hasFilter: boolean,
  ): number {
    const expanded = item.expanded || hasFilter;
    if (item.hidden) {
      return 0;
    }
    let height = item.key === undefined ? 0 : 1;
    if (expanded) {
      height +=
        item.children
          ?.map((child) => JsonTree.totalVisibleRows(child, hasFilter))
          .reduce((acc, child) => acc + child, 0) ?? 0;
    }
    return height;
  }

  private handleClickTrackingButton(e: MouseEvent) {
    e.stopPropagation();
    const button = e.currentTarget as HTMLButtonElement;
    button.classList.toggle("enable-tracking");

    const pathStr = button.getAttribute("data-path");
    if (pathStr) {
      this.dispatchEvent(
        new CustomEvent("togglePath", {
          detail: pathStr,
        }),
      );
    }
  }

  private renderTrackingButton(
    item: JsonTreeItem,
    className?: string,
  ): HTMLTemplateResult | undefined {
    if (this.disableTrackingPath) return;

    return html`<button
      data-path=${item.pathStr}
      class="tracking ${className} ${this.trackedPaths.includes(item.pathStr)
        ? "enable-tracking"
        : ""}"
      @click=${this.handleClickTrackingButton}
    ></button>`;
  }

  protected renderLabel(item: JsonTreeItem, indent: number): any {
    if (this._renderRowIndex < this._visibleStartRowIndex) return;
    if (this._renderRowIndex > this._visibleStartRowIndex + this._visibleRows)
      return;

    if (isLeaf(item)) {
      if (item.isArrayChild) {
        return html`<div
          class="label array-child"
          style="margin-left: ${indent}ch;"
        >
          <span class="key index">${item.key}</span>
          ${item.valueRender}
        </div>`;
      } else {
        return html`<div class="label" style="margin-left: ${indent}ch;">
          ${this.renderTrackingButton(item, "no-expand-arrow")}
          <span class="arrow-right invisible"></span>
          <span class="icon ${item.type}"></span>
          <span class="key">${JsonTree.keyPrefix(item)}</span>
          ${item.valueRender}
        </div>`;
      }
    }

    const expanded = item.expanded || this._hasFilter;

    return html`
      <button
        data-path=${item.pathStr}
        class="label"
        @click=${this.handleClick}
        style="margin-left: ${indent}ch;"
      >
        ${this.renderTrackingButton(item)}
        ${item.isArrayChild
          ? html`<span class="key index">${item.key}</span>`
          : undefined}
        ${expanded
          ? html`<span class="arrow-right expanded"></span>`
          : html`<span class="arrow-right"></span>`}
        ${item.isArrayChild
          ? undefined
          : html`<span class="icon ${item.type}"></span>`}
        ${expanded
          ? html`<span
              >${item.isArrayChild ? undefined : JsonTree.keyPrefix(item)}
              ${Array.isArray(item.value)
                ? html`Array
                    <span class="value count">(${item.value.length})</span>`
                : "Object"}</span
            >`
          : html`<span
              >${item.isArrayChild ? undefined : JsonTree.keyPrefix(item)}
              ${item.summary}</span
            >`}
      </button>
    `;
  }

  protected renderItem(
    item: JsonTreeItem,
    indent: number,
  ): HTMLTemplateResult | undefined {
    if (item.hidden) return;
    if (this._renderRowIndex >= this._totalVisibleRows) return;

    this._renderRowIndex++;
    const expanded = item.expanded || this._hasFilter;
    return html`${this.renderLabel(item, indent)}
    ${item.children && expanded
      ? item.children.map((child) =>
          keyed(
            child.pathStr,
            this.renderItem(child, indent + (item.isArrayChild ? 5 : 2)),
          ),
        )
      : undefined}`;
  }

  renderActions() {
    return html`<div class="actions">
      ${this._showFilter
        ? html`<input
            type="search"
            @input="${this.handleInput}"
            @keydown="${this.handleKeyDown}"
            @blur="${this.handleBlur}"
            placeholder="Filter"
          />`
        : html`
            <button tabindex="0" @click=${this.handleCopy}>Copy</button>
            <button tabindex="0" @click=${this.handleCollapseAll}>
              Collapse
            </button>
            <button tabindex="0" @click=${this.handleExpandAll}>Expand</button>
            <button tabindex="0" @click=${this.handleShowFilter}>Filter</button>
            <button tabindex="0" @click=${this.handleParseNestedJson}>
              ${this._showNestedJson ? "⊟Nested" : "⊞Nested"}
            </button>
          `}
    </div>`;
  }

  render() {
    if (!this._tree || !this._tree.children || this._tree.children.length === 0)
      return html``;
    const children = this._tree.children;
    this._renderRowIndex = 0;
    this._totalVisibleRows = JsonTree.totalVisibleRows(
      this._tree,
      this._hasFilter,
    );
    const height = ACTION_ROW_HEIGHT + this._totalVisibleRows * ROW_HEIGHT;
    return html`<div style="height: ${height}px;">
      ${this.renderActions()}
      <div
        class="visible-rows"
        style="top: ${ACTION_ROW_HEIGHT +
        this._visibleStartRowIndex * ROW_HEIGHT}px;"
      >
        ${children.map((child) =>
          keyed(child.pathStr, this.renderItem(child, 0)),
        )}
      </div>
    </div>`;
  }

  connectedCallback(): void {
    super.connectedCallback();
    this.generateTree();

    const host = this.shadowRoot!.host;
    // monitor shadowRoot size change
    const observer = new ResizeObserver((e) => {
      const height = e[0].contentBoxSize[0].blockSize;
      this._visibleRows = Math.max(10, Math.ceil(height / ROW_HEIGHT));
    });
    observer.observe(host);

    host.addEventListener("scroll", (e) => {
      this._visibleStartRowIndex = Math.floor(
        (e.currentTarget as HTMLElement).scrollTop / ROW_HEIGHT,
      );
    });
  }

  update(changedProperties: PropertyValues): void {
    if (changedProperties.has("_showFilter")) {
      if (!this._showFilter) {
        this._filter = this._input?.value || "";
      }
    }
    super.update(changedProperties);
  }

  updated(changedProperties: PropertyValues): void {
    super.updated(changedProperties);
    if (changedProperties.has("data")) {
      this.generateTree();
    } else if (changedProperties.has("_showNestedJson")) {
      this.generateTree();
    } else if (changedProperties.has("_showFilter")) {
      if (this._showFilter) {
        if (this._input) {
          this._input.focus();
          if (this._filter.length > 0) {
            this._input.value = this._filter;
            // apply filter by triggering input event
            this._input.dispatchEvent(new Event("input", { bubbles: true }));
            this._input.select();
          }
        }
      } else {
        this._filterButton?.focus();
        clearFilter(this._tree);
        this.requestUpdate();
      }
    }
  }
}
