import {
  css,
  html,
  HTMLTemplateResult,
  LitElement,
  PropertyValues,
  unsafeCSS,
} from "lit";
import { repeat } from "lit/directives/repeat.js";
import { customElement, property, query, state } from "lit/decorators.js";
import typeIcons from "../assets/images/TypeIcons.svg";
import showIcon from "../assets/images/Show.svg";
import circleIcon from "../assets/images/Circle.svg";
import { sort as sortKeys } from "json-keys-sort";
import {
  ACTION_ROW_HEIGHT,
  clearFilter,
  filterTree,
  getFirstItem,
  getItemByPathStr,
  getLastItem,
  getNextItem,
  getPreviousItem,
  indexOfPathStr,
  isLeaf,
  JsonTreeItem,
  ROW_HEIGHT,
  setExpanded,
  totalVisibleRows,
  visibleItems,
  getSummary,
  renderLeafValue,
  jsonToTree,
} from "./jsonTree/model";
import { tryParseNestedJson } from "./jsonTree/nested";
import { productionPlatformsPrefixes } from "./domains";

function escapeRegExp(str: string) {
  return str.replace(/[-\/\\^$*+?.()|[\]{}]/g, "\\$&");
}

function getPartnerPortalUrl(controlPanelUrl?: string) {
  if (!controlPanelUrl) {
    return;
  }

  if (controlPanelUrl.includes("dash.testing.comm100dev.io")) {
    return controlPanelUrl.replace(
      "dash.testing.comm100dev.io",
      "partner.testing.comm100dev.io",
    );
  } else if (
    productionPlatformsPrefixes.some((p) => controlPanelUrl.includes(p))
  ) {
    return "https://partner.comm100.io";
  } else if (controlPanelUrl.includes("comm100staging.com")) {
    return "https://partner.comm100staging.com";
  } else {
    console.warn(`Unknown partner portal url: ${controlPanelUrl}`);
    return "https://partner.comm100.io";
  }
}

@customElement("json-tree")
export class JsonTree extends LitElement {
  constructor() {
    super();
    this.renderItem = this.renderItem.bind(this);
  }

  @property({ type: String })
  data: string = "";

  @property({ type: Number })
  initialIndent: number = 2;

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
  private _visibleHeight = 10 * ROW_HEIGHT;
  @state()
  private _selectedPath: string | undefined;

  private selectNextPath() {
    this._selectedPath = getNextItem(
      this._tree,
      this._hasFilter,
      this._selectedPath,
    )?.pathStr;
    if (!this._selectedPath) {
      this._selectedPath = getFirstItem(this._tree, this._hasFilter)?.pathStr;
    }
  }

  private selectPreviousPath() {
    this._selectedPath = getPreviousItem(
      this._tree,
      this._hasFilter,
      this._selectedPath,
    )?.pathStr;
    if (!this._selectedPath) {
      this._selectedPath = getLastItem(this._tree, this._hasFilter)?.pathStr;
    }
  }

  @state()
  private _showNestedJson: boolean = false;
  private handleParseNestedJson() {
    this._showNestedJson = !this._showNestedJson;
  }

  private _renderRowIndex = 0;
  private _totalVisibleRows = 0;

  private generateTree() {
    const reduxState: any = sortKeys(JSON.parse(this.data));
    reduxState.agent?.permissions?.sort((a: any, b: any) => a - b);

    const siteId = +reduxState.agent?.siteId;
    const chatServerUrl = reduxState.config?.settings?.urls?.chatServer;
    const controlPanelUrl = reduxState.config?.settings?.urls?.controlPanel;
    const partnerPortalUrl = getPartnerPortalUrl(controlPanelUrl);
    const partnerId = +reduxState.partner?.partnerId;
    this._tree = jsonToTree(
      this._showNestedJson ? tryParseNestedJson(reduxState) : reduxState,
      [],
      this.initialIndent - 2,
      {
        soundUrl: `${chatServerUrl}/DBResource/DBSound.ashx?soundId={soundId}&siteId=${siteId}`,
        // https://livechat3dash.testing.comm100dev.io/frontEnd/livechatpage/assets/livechat/previewpage/?campaignId=23daa136-1361-44aa-bf52-8dc92d8a3925&siteId=10008&lang=en
        campaignPreviewUrl: `${controlPanelUrl}/frontEnd/livechatpage/assets/livechat/previewpage/?campaignId={campaignId}&siteId=${siteId}&lang=en`,
        // https://dash11.comm100.io/ui/10100000/livechat/campaign/installation/?scopingcampaignid=28f5d50f-45f8-401e-beac-283e2d67a7b3
        controlPanelUrl: `${controlPanelUrl}/ui/${siteId}`,
        partnerPortalUrl: `${partnerPortalUrl}/ui/${partnerId}`,
        siteId,
        partnerId,
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
    .rows {
      width: 100%;
      position: relative;
      outline: none;
    }
    .rows:focus,
    .rows:focus-within {
      outline: none;
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
      flex: none;
    }
    .label {
      display: flex;
      align-items: center;
      gap: 4px;
      height: ${ROW_HEIGHT}px;
      line-height: ${ROW_HEIGHT}px;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
      position: absolute;
      width: 100%;
      box-sizing: border-box;
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
      flex: none;
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
      overflow: hidden;
      text-overflow: ellipsis;
    }
    .key {
      flex: none;
    }
    .key.index {
      color: var(--text-color-secondary);
      text-align: right;
      width: 3ch;
      flex: none;
      margin-right: 1ch;
    }
    .summary {
      overflow: hidden;
      text-overflow: ellipsis;
    }
    .value.key {
      color: var(--syntax-highlight-boolean-color);
    }
    .value.string {
      color: var(--syntax-highlight-string-color);
    }
    .value a {
      color: inherit;
    }
    .value.number .permission {
      color: var(--text-color-secondary);
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

    .label.copied {
      transition: background-color 0.2s ease-in-out;
      background-color: var(--background-color) !important;
    }

    .label:focus {
      outline: none;
    }
    .label:hover {
      background-color: var(--selected-background-color-unfocused);
    }

    .rows:focus-within .label.selected {
      background-color: var(--selected-background-color);
    }

    .label.selected {
      background-color: var(--selected-background-color-unfocused);
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
  `;

  private toggleExpandByPathStr(pathStr: string, forceExpanded?: boolean) {
    const item = getItemByPathStr(this._tree, pathStr);
    if (item && !isLeaf(item)) {
      item.expanded = forceExpanded ?? !item.expanded;
      this.requestUpdate();
    }
  }

  private handleClick(event: MouseEvent) {
    const pathStr = getRowElement(event.target as HTMLElement)?.getAttribute(
      "data-path",
    );
    if (pathStr) {
      this.toggleExpandByPathStr(pathStr);
      this._selectedPath = pathStr;
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
    e.stopPropagation();
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

  private handleFilterInputKeydown(e: KeyboardEvent) {
    e.stopPropagation();
    if (e.key === "Escape") {
      this._showFilter = false;
    }
  }

  private getElementByPathStr(
    pathStr: string | undefined,
  ): HTMLElement | undefined {
    if (!pathStr) return undefined;
    return this.shadowRoot?.querySelector(
      `.label[data-path="${pathStr}"]`,
    ) as HTMLElement;
  }

  private scrollToPath(pathStr: string) {
    if (!this.shadowRoot) return;

    const index = indexOfPathStr(this._tree, this._hasFilter, pathStr);
    if (index === -1) return;

    const itemRange = { top: indexToTop(index), bottom: indexToTop(index + 1) };
    const visibleRange = {
      top: this.shadowRoot.host.scrollTop + ACTION_ROW_HEIGHT,
      bottom: this.shadowRoot.host.scrollTop + this._visibleHeight,
    };

    let newScrollTop: number | undefined;
    if (itemRange.top < visibleRange.top) {
      newScrollTop = itemRange.top - ACTION_ROW_HEIGHT;
    } else if (itemRange.bottom >= visibleRange.bottom) {
      newScrollTop = itemRange.bottom - this._visibleHeight;
    }

    if (newScrollTop !== undefined) {
      this.shadowRoot.host.scrollTop = newScrollTop;
      // need update _visibleStartRowIndex synchronously
      this.handleScroll();
    }
  }

  private handleKeydown(e: KeyboardEvent) {
    e.stopPropagation();

    if (e.key === "ArrowUp" || e.key === "k") {
      e.preventDefault();

      this.selectPreviousPath();
    } else if (e.key === "ArrowDown" || e.key === "j") {
      e.preventDefault();

      this.selectNextPath();
    } else if (e.key === "ArrowLeft" || e.key === "h") {
      e.preventDefault();

      if (this._selectedPath) {
        const item = getItemByPathStr(this._tree, this._selectedPath);
        if (item) {
          if (isLeaf(item) || !item.expanded) {
            this._selectedPath = item.parentPathStr;
            this.toggleExpandByPathStr(this._selectedPath, false);
          } else {
            item.expanded = false;
            this.requestUpdate();
          }
        }
      }
    } else if (e.key === "ArrowRight" || e.key === "l") {
      e.preventDefault();
      if (this._selectedPath)
        this.toggleExpandByPathStr(this._selectedPath, true);
    } else if (e.key === "o" || e.key === "Space") {
      e.preventDefault();

      if (this._selectedPath) this.toggleExpandByPathStr(this._selectedPath);
    } else if (e.key === "y") {
      e.preventDefault();

      if (this._selectedPath) {
        const toCopy = JSON.stringify(
          getItemByPathStr(this._tree, this._selectedPath)?.value,
          null,
          2,
        );
        navigator.clipboard.writeText(toCopy);
        const row = this.getElementByPathStr(this._selectedPath);
        if (row) {
          row.classList.add("copied");
          row.addEventListener(
            "transitionend",
            () => {
              row.classList.remove("copied");
            },
            { once: true },
          );
        }
      }
    } else if (e.key === "d" && e.ctrlKey) {
      e.preventDefault();
      let count = this._visibleRows / 2;
      let cursor = this._selectedPath;
      while (count > 0) {
        const p = getNextItem(this._tree, this._hasFilter, cursor)?.pathStr;
        if (p) cursor = p;
        else break;
        count--;
      }
      this._selectedPath = cursor;
    } else if (e.key === "u" && e.ctrlKey) {
      e.preventDefault();
      let count = this._visibleRows / 2;
      let cursor = this._selectedPath;
      while (count > 0) {
        const p = getPreviousItem(this._tree, this._hasFilter, cursor)?.pathStr;
        if (p) cursor = p;
        else break;
        count--;
      }
      this._selectedPath = cursor;
    } else if (e.key === "G") {
      this._selectedPath = getLastItem(this._tree, this._hasFilter)?.pathStr;
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

  protected renderItem(item: JsonTreeItem): HTMLTemplateResult | undefined {
    const selectedClass = item.pathStr === this._selectedPath ? "selected" : "";
    const top = indexToTop(this._visibleStartRowIndex + this._renderRowIndex);
    const style = `padding-left: ${item.indent}ch;top: ${top}px;`;
    this._renderRowIndex++;

    if (isLeaf(item)) {
      if (typeof item.key === "number") {
        return html`<div
          class="label array-child ${selectedClass}"
          data-path=${item.pathStr}
          style=${style}
          tabindex="0"
        >
          <span class="key index">${item.key}</span>
          ${renderLeafValue(item)}
        </div>`;
      } else {
        return html`<div
          class="label ${selectedClass}"
          data-path=${item.pathStr}
          style=${style}
          tabindex="0"
        >
          ${this.renderTrackingButton(item, "no-expand-arrow")}
          <span class="arrow-right invisible"></span>
          <span class="icon ${item.type}"></span>
          <span class="key">${JsonTree.keyPrefix(item)}</span>
          ${renderLeafValue(item)}
        </div>`;
      }
    }

    const expanded = item.expanded || this._hasFilter;

    return html`
      <button
        class="label ${selectedClass}"
        data-path=${item.pathStr}
        style=${style}
      >
        ${this.renderTrackingButton(item)}
        ${typeof item.key === "number"
          ? html`<span class="key index">${item.key}</span>`
          : undefined}
        ${expanded
          ? html`<span class="arrow-right expanded"></span>`
          : html`<span class="arrow-right"></span>`}
        ${typeof item.key === "number"
          ? undefined
          : html`<span class="icon ${item.type}"></span>`}
        ${expanded
          ? html`<span class="summary"
              >${typeof item.key === "number"
                ? undefined
                : JsonTree.keyPrefix(item)}
              ${Array.isArray(item.value)
                ? html`Array
                    <span class="value count">(${item.value.length})</span>`
                : "Object"}</span
            >`
          : html`<span class="summary"
              >${typeof item.key === "number"
                ? undefined
                : JsonTree.keyPrefix(item)}
              ${getSummary(item)}</span
            >`}
      </button>
    `;
  }

  renderActions() {
    return html`<div
      class="actions"
      style="padding-left: ${this.initialIndent}ch;"
    >
      ${this._showFilter
        ? html`<input
            type="search"
            @input="${this.handleInput}"
            @keydown="${this.handleFilterInputKeydown}"
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

  @query("div.rows")
  private _rowsElement!: HTMLDivElement;

  render() {
    if (!this._tree || !this._tree.children || this._tree.children.length === 0)
      return html``;
    this._renderRowIndex = 0;
    this._totalVisibleRows = totalVisibleRows(this._tree, this._hasFilter);
    const height = ACTION_ROW_HEIGHT + this._totalVisibleRows * ROW_HEIGHT;
    return html`<div
      class="rows"
      style="height: ${height}px;"
      tabindex="0"
      @keydown=${this.handleKeydown}
      @click=${this.handleClick}
    >
      ${this.renderActions()}
      ${repeat(
        visibleItems(
          this._tree,
          this._hasFilter,
          this._visibleStartRowIndex,
          this._visibleStartRowIndex + this._visibleRows,
        ),
        (item) => item.pathStr,
        this.renderItem,
      )}
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
      this._visibleHeight = height;
    });
    observer.observe(host);

    host.addEventListener("scroll", this.handleScroll);
  }

  private handleScroll() {
    this._visibleStartRowIndex = Math.floor(
      this.shadowRoot!.host.scrollTop / ROW_HEIGHT,
    );
  }

  update(changedProperties: PropertyValues): void {
    if (changedProperties.has("_showFilter")) {
      if (!this._showFilter) {
        this._filter = this._input?.value || "";
      }
    } else if (changedProperties.has("_selectedPath")) {
      if (this._selectedPath) this.scrollToPath(this._selectedPath);
    }
    super.update(changedProperties);
  }

  updated(changedProperties: PropertyValues): void {
    super.updated(changedProperties);
    if (changedProperties.has("data")) {
      this.generateTree();
    } else if (changedProperties.has("_showNestedJson")) {
      this.generateTree();
    } else if (changedProperties.has("_selectedPath")) {
      this._rowsElement.focus();
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

const getRowElement = (ele: Node): HTMLElement | undefined => {
  let p: Node | null = ele;
  while (p) {
    if (p instanceof HTMLElement && p.classList.contains("label")) {
      return p;
    }
    p = p.parentNode;
  }
};

const indexToTop = (index: number) => {
  return ACTION_ROW_HEIGHT + index * ROW_HEIGHT;
};
