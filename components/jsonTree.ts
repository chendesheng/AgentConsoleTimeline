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
  BREADCRUMB_ROW_HEIGHT,
  clearFilter,
  filterTree,
  getFirstItem,
  getItemByPathStr,
  getLastItem,
  getNextItem,
  getPreviousItem,
  indexOfPathStr,
  JsonTreeItem,
  ROW_HEIGHT,
  setExpanded,
  totalRows,
  jsonToTree,
  getIterator,
  setItemExpanded,
  sliceItems,
  searchTree,
} from "./jsonTree/model";
import { tryParseNestedJson } from "./jsonTree/nested";
import { productionPlatformsPrefixes } from "./domains";
import { KeymapManager } from "./jsonTree/keymap";
import { TreeIterator } from "./jsonTree/iterator";

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

  @property({ type: Boolean })
  showBreadcrumb = true;
  @property({ type: Boolean })
  showActions = true;

  @state()
  private _tree!: JsonTreeItem;
  @state()
  private _showFilter = false;
  @query("div.actions input.filter")
  private _filterInput?: HTMLInputElement;
  @state()
  private _filter = "";
  @query("div.actions button.filter")
  private _filterButton?: HTMLButtonElement;

  private get _expandAll() {
    return this._showFilter;
  }

  @state()
  private _showSearch = false;
  @state()
  private _search = "";
  private _searchForward = true;
  @query("div.actions input.search")
  private _searchInput?: HTMLInputElement;
  @query("div.actions button.search")
  private _searchButton?: HTMLButtonElement;
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
      this._expandAll,
      this._selectedPath,
    )?.pathStr;
  }

  private selectPreviousPath() {
    this._selectedPath = getPreviousItem(
      this._tree,
      this._expandAll,
      this._selectedPath,
    )?.pathStr;
  }

  @state()
  private _showNestedJson: boolean = false;
  private handleParseNestedJson() {
    this._showNestedJson = !this._showNestedJson;
  }

  private _totalRows = 0;

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
    this._showFilter = false;
    this._showSearch = false;
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
      width: ${ROW_HEIGHT}px;
      height: ${ROW_HEIGHT}px;
      display: block;
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
    .label img {
      display: block;
      width: ${ROW_HEIGHT - 2}px;
      height: ${ROW_HEIGHT - 2}px;
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
      background: url("${unsafeCSS(
        typeIcons,
      )}#TimelineRecordCSSAnimation-dark");
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

    .breadcrumb {
      position: sticky;
      top: ${ACTION_ROW_HEIGHT}px;
      z-index: 1;
      display: flex;
      flex-direction: row;
      border-bottom: 1px solid var(--border-color);
      background-color: var(--background-color);
      align-items: center;
      height: ${BREADCRUMB_ROW_HEIGHT - 1}px;
      gap: 1ch;
    }
    .breadcrumb .label {
      opacity: 0.7;
    }
    .breadcrumb .label:focus,
    .breadcrumb .label:hover {
      opacity: 1;
    }
    .breadcrumb .label {
      top: unset !important;
      position: unset !important;
      width: unset !important;
      background-color: unset !important;
      padding-left: 0 !important;
    }

    .breadcrumb .label .key.index {
      width: unset !important;
    }

    .breadcrumb .label:first-child {
      padding-left: 0;
    }
    .breadcrumb .label button.tracking {
      display: none;
    }
    .breadcrumb .label.selected {
      background-color: unset !important;
    }
    .search-result {
      position: absolute;
      height: ${ROW_HEIGHT}px;
      line-height: ${ROW_HEIGHT}px;
      display: flex;
      align-items: center;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }
    .search-result-highlight {
      background: var(--search-highlight-background-color-active);
      color: var(--search-highlight-text-color-active);
      pointer-events: none;
      user-select: none;
    }
  `;

  private toggleExpandByPathStr(pathStr?: string, forceExpanded?: boolean) {
    if (!pathStr) return;
    const item = getItemByPathStr(this._tree, pathStr);
    if (item && !item.isLeaf) {
      setItemExpanded(this._tree, pathStr, forceExpanded ?? !item.expanded);
      this.requestUpdate();
    }
  }

  private scrollToTop() {
    if (!this.shadowRoot) return;
    this.shadowRoot.host.scrollTop = 0;
    this.handleScroll();
  }

  private handleClick(event: MouseEvent) {
    const rowElement = getRowElement(event.target as HTMLElement);
    if (!rowElement) return;

    if (hasParent(rowElement, "breadcrumb")) {
      if (!this.shadowRoot) return;
      this._rowsElement.focus();
      const pathStr = rowElement.getAttribute("data-path")!;
      if (pathStr === "") this.scrollToTop(); // root item
      else this.scrollToPath(pathStr, "top");
      return;
    }

    const pathStr = rowElement.getAttribute("data-path");
    if (pathStr) {
      this.toggleExpandByPathStr(pathStr);
      this._selectedPath = pathStr;
    }
  }

  private copySelectedValue() {
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
  private handleFilterInput(e: Event) {
    e.stopPropagation();
    if (!this._showFilter) return;
    if (this._filterInput?.value?.length === 0) {
      clearFilter(this._tree);
      this.requestUpdate();
      return;
    }

    const input = e.target as HTMLInputElement;
    filterTree(this._tree, createRegex(input.value));
    this.requestUpdate();
  }

  private handleShowFilter() {
    if (this._showSearch) return;
    this._showFilter = true;
  }

  private handleShowSearch(forward: boolean = true) {
    if (this._showFilter) return;
    this._searchForward = forward;
    this._showSearch = true;
  }

  private handleFilterInputKeydown(e: KeyboardEvent) {
    e.stopPropagation();
    if (e.key === "Escape") {
      this._showFilter = false;
    }
  }

  @state()
  private _pendingSearchResult?: TreeIterator<JsonTreeItem>;
  private _pendingSearchSavedExpanded?: [JsonTreeItem, boolean][];
  private _pendingSearchSavedScrollTop?: number;

  private acceptPendingSearchResult() {
    this._showSearch = false;
    this._pendingSearchSavedExpanded = undefined;
    if (this._pendingSearchResult) {
      for (const item of this._pendingSearchResult.pathItems.slice(0, -1)) {
        item.expanded = true;
        item.resetDecendentsCountCache();
      }
      this.requestUpdate();
      this._selectedPath = this._pendingSearchResult.current.pathStr;
    }
  }

  private restorePendingSearchExpanded() {
    if (this._pendingSearchSavedExpanded) {
      for (const [item, expanded] of this._pendingSearchSavedExpanded) {
        item.expanded = expanded;
        item.resetDecendentsCountCache();
      }

      this._pendingSearchSavedExpanded = undefined;
      this.requestUpdate();
    }
  }

  private restorePendingSearchScrollTop() {
    if (this.shadowRoot && this._pendingSearchSavedScrollTop)
      this.shadowRoot.host.scrollTop = this._pendingSearchSavedScrollTop;
    this._pendingSearchSavedScrollTop = undefined;
  }

  private runSearch(forward: boolean, accept?: boolean) {
    if (this._search.length === 0) {
      this.restorePendingSearchExpanded();
      this.restorePendingSearchScrollTop();
      return;
    }

    const iter = searchTree(
      this._tree,
      createRegex(this._search),
      forward,
      this._selectedPath,
    );

    if (accept) {
      if (iter) {
        this._pendingSearchResult = iter;
        this.acceptPendingSearchResult();
      }
    } else if (iter) {
      this._pendingSearchSavedScrollTop = this.shadowRoot?.host.scrollTop;
      // restore expanded state
      this.restorePendingSearchExpanded();

      const items = iter.pathItems.slice(0, -1);
      this._pendingSearchSavedExpanded = items.map((item) => [
        item,
        item.expanded,
      ]);
      for (const item of items) {
        item.expanded = true;
        item.resetDecendentsCountCache();
      }

      this._pendingSearchResult = iter;
      this.scrollToPath(iter.current.pathStr);
    }
  }

  private handleSearchInput(e: Event) {
    e.stopPropagation();
    if (!this._showSearch) return;
    const input = e.target as HTMLInputElement;
    this._search = input.value;
  }

  private handleSearchInputKeydown(e: KeyboardEvent) {
    e.stopPropagation();
    if (e.key === "Escape") {
      this.restorePendingSearchExpanded();
      this.restorePendingSearchScrollTop();
      this._pendingSearchResult = undefined;
      this._showSearch = false;
    } else if (e.key === "Enter") {
      this.acceptPendingSearchResult();
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

  private scrollToPath(
    pathStr: string,
    position?: "top" | "center" | "bottom",
  ) {
    if (!this.shadowRoot) return;

    const index = indexOfPathStr(this._tree, this._expandAll, pathStr);
    if (index === -1) return;

    const itemRange = {
      top: this.indexToTop(index),
      bottom: this.indexToTop(index + 1),
    };
    const visibleRange = {
      top:
        this.shadowRoot.host.scrollTop +
        ACTION_ROW_HEIGHT +
        BREADCRUMB_ROW_HEIGHT,
      bottom: this.shadowRoot.host.scrollTop + this._visibleHeight,
    };

    let newScrollTop: number | undefined;

    if (position === "top") {
      newScrollTop = itemRange.top - this.getStickyHeight();
    } else if (position === "center") {
      newScrollTop = itemRange.top - this._visibleHeight / 2 + ROW_HEIGHT / 2;
    } else if (position === "bottom") {
      newScrollTop = itemRange.bottom - this._visibleHeight;
    } else {
      if (itemRange.top < visibleRange.top) {
        newScrollTop = itemRange.top - this.getStickyHeight();
      } else if (itemRange.bottom >= visibleRange.bottom) {
        newScrollTop = itemRange.bottom - this._visibleHeight;
      }
    }

    if (newScrollTop !== undefined) {
      this.shadowRoot.host.scrollTop = newScrollTop;
      // need update _visibleStartRowIndex synchronously
      this.handleScroll();
    }
  }

  private keymapManager = new KeymapManager();

  private handleArrowLeftKey() {
    if (this._selectedPath) {
      const item = getItemByPathStr(this._tree, this._selectedPath);
      if (item) {
        if (item.isLeaf || !item.expanded) {
          this._selectedPath = item.parentPathStr;
          this.toggleExpandByPathStr(this._selectedPath, false);
        } else if (!item.isRoot) {
          item.expanded = false;
          this.requestUpdate();
        }
      }
    }
  }

  private handleCopy() {
    navigator.clipboard.writeText(this.data);
  }

  private scrollDownHalfPage() {
    let count = this._visibleRows / 2;
    const iter = getIterator(this._tree, this._expandAll, this._selectedPath);
    while (count > 0) {
      count--;
      if (!iter.next()) break;
    }
    this._selectedPath = iter.current.pathStr;
  }

  private scrollUpHalfPage() {
    let count = this._visibleRows / 2;
    const iter = getIterator(this._tree, this._expandAll, this._selectedPath);
    while (count > 0) {
      count--;
      if (!iter.previous()) break;
    }
    if (iter.current.isRoot) {
      iter.next();
    }
    this._selectedPath = iter.current.pathStr;
  }

  private handleKeydown(e: KeyboardEvent) {
    if (this.keymapManager.handleKeydown(e)) {
      e.preventDefault();
      e.stopPropagation();
    }
  }

  private goToFirstItem() {
    this._selectedPath = getFirstItem(this._tree, this._expandAll)?.pathStr;
  }

  private goToLastItem() {
    this._selectedPath = getLastItem(this._tree, this._expandAll)?.pathStr;
  }

  private handleFilterInputBlur(e: Event) {
    if (this._filterInput?.value?.length === 0) {
      this._showFilter = false;
    }
  }

  private handleSearchInputBlur(e: Event) {
    if (this._searchInput?.value?.length === 0) {
      this._showSearch = false;
    }
  }

  private centerSelectedItem() {
    if (!this.shadowRoot) return;
    if (!this._selectedPath) return;
    this.scrollToPath(this._selectedPath, "center");
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

  protected renderItem(
    item: JsonTreeItem,
    index: number,
  ): HTMLTemplateResult | undefined {
    const selectedClass = item.pathStr === this._selectedPath ? "selected" : "";
    const top = this.indexToTop(this._visibleStartRowIndex + index);
    const style = `padding-left: ${item.indent}ch;top: ${top}px;`;

    if (item.isLeaf) {
      if (typeof item.key === "number") {
        return html`<div
          class="label array-child ${selectedClass}"
          data-path=${item.pathStr}
          style=${style}
          tabindex="0"
        >
          <span class="key index" style="width: ${item.numberKeyWidth}ch;"
            >${item.key}</span
          >
          ${item.renderLeafValue()}
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
          ${item.renderLeafValue()}
        </div>`;
      }
    }

    const expanded = item.expanded || this._expandAll;

    return html`
      <button
        class="label ${selectedClass}"
        data-path=${item.pathStr}
        style=${style}
      >
        ${this.renderTrackingButton(item)}
        ${typeof item.key === "number"
          ? html`<span
              class="key index"
              style="width: ${item.numberKeyWidth}ch;"
              >${item.key}</span
            >`
          : undefined}
        ${expanded
          ? html`<span class="arrow-right expanded"></span>`
          : html`<span class="arrow-right"></span>`}
        <span class="icon ${item.type}"></span>
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
              ${item.summary}</span
            >`}
      </button>
    `;
  }

  renderPendingSearchResult(visibleItems: JsonTreeItem[]) {
    if (!this._pendingSearchResult) return;
    const item = this._pendingSearchResult.current;
    if (!visibleItems.includes(item)) return;

    const index = indexOfPathStr(this._tree, this._expandAll, item.pathStr);
    console.log("index", index, "pathStr", item.pathStr);
    const top = this.indexToTop(index);
    const style = `padding-left: calc(${item.indent}ch + 1.2em + 16px);top: ${top}px;`;
    const re = createRegex(this._search);

    const keyPrefix = JsonTree.keyPrefix(item)!;
    const keyIndex = keyPrefix?.match(re)?.index;
    if (keyIndex !== undefined) {
      return html`
        <div class="search-result" style=${style}>
          <span style="visibility: hidden;"
            >${keyPrefix.slice(0, keyIndex)}</span
          ><span class="search-result-highlight"
            >${keyPrefix.slice(keyIndex, keyIndex + this._search.length)}</span
          >
        </div>
      `;
    }

    if (item.isLeaf) {
      const valueIndex = (item.value.toString() as string).match(re)?.index;
      if (valueIndex !== undefined) {
        return html`
          <div class="search-result" style=${style}>
            <span style="visibility: hidden;"
              >${JsonTree.keyPrefix(item)}${item.value
                .toString()
                .slice(0, index)}</span
            ><span class="search-result-highlight"
              >${item.value
                .toString()
                .slice(index, index + this._search.length)}</span
            >
          </div>
        `;
      }
    }
  }

  renderActions() {
    return html`<div
      class="actions"
      style="padding-left: ${this.initialIndent}ch;"
    >
      ${this._showFilter
        ? html`<input
            class="filter"
            type="search"
            @input="${this.handleFilterInput}"
            @keydown="${this.handleFilterInputKeydown}"
            @blur="${this.handleFilterInputBlur}"
            placeholder="Filter"
          />`
        : this._showSearch
        ? html`<input
            class="search"
            type="search"
            @input="${this.handleSearchInput}"
            @keydown="${this.handleSearchInputKeydown}"
            @blur="${this.handleSearchInputBlur}"
            placeholder="Search"
          />`
        : html`
            <button tabindex="0" @click=${this.handleCopy}>Copy</button>
            <button tabindex="0" @click=${this.handleCollapseAll}>
              Collapse
            </button>
            <button tabindex="0" @click=${this.handleExpandAll}>Expand</button>
            <button tabindex="0" class="filter" @click=${this.handleShowFilter}>
              Filter
            </button>
            <button tabindex="0" class="search" @click=${this.handleShowSearch}>
              Search
            </button>
            <button tabindex="0" @click=${this.handleParseNestedJson}>
              ${this._showNestedJson ? "⊟Nested" : "⊞Nested"}
            </button>
          `}
    </div>`;
  }

  renderBreadcrumb() {
    if (!this.shadowRoot) return;

    let pathStr = this._selectedPath;
    if (this._showSearch && this._pendingSearchResult) {
      pathStr = this._pendingSearchResult.current.pathStr;
    }

    if (!pathStr) return;

    const iter = getIterator(this._tree, this._expandAll, pathStr);
    if (!iter) return;

    const items = iter.current.isNoOrHideChildren(this._expandAll)
      ? iter.pathItems.slice(0, -1)
      : iter.pathItems;
    if (items.length === 0) return;
    return html`
      <div class="breadcrumb" style="padding-left: ${this.initialIndent}ch;">
        ${repeat(items, (item) => item.pathStr, this.renderItem)}
      </div>
    `;
  }

  @query("div.rows")
  private _rowsElement!: HTMLDivElement;

  private getStickyHeight(): number {
    return (
      (this.showActions ? ACTION_ROW_HEIGHT : 0) +
      (this.showBreadcrumb && !!this._selectedPath ? BREADCRUMB_ROW_HEIGHT : 0)
    );
  }

  render() {
    if (!this._tree || !this._tree.children || this._tree.children.length === 0)
      return html``;
    this._totalRows = totalRows(this._tree, this._expandAll);
    const height = this.getStickyHeight() + this._totalRows * ROW_HEIGHT;
    const visibleItems = Array.from(
      sliceItems(
        this._tree,
        this._expandAll,
        this._visibleStartRowIndex,
        this._visibleRows,
      ),
    );
    return html`<div
      class="rows"
      style="height: ${height}px;"
      tabindex="0"
      @keydown=${this.handleKeydown}
      @click=${this.handleClick}
    >
      ${this.showActions ? this.renderActions() : undefined}
      ${this.showBreadcrumb ? this.renderBreadcrumb() : undefined}
      ${repeat(visibleItems, (item) => item.pathStr, this.renderItem)}
      ${this.renderPendingSearchResult(visibleItems)}
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

    this.keymapManager.register(
      {
        keys: ["ArrowUp"],
        action: () => this.selectPreviousPath(),
      },
      {
        keys: ["k"],
        action: () => this.selectPreviousPath(),
      },
      {
        keys: ["ArrowDown"],
        action: () => this.selectNextPath(),
      },
      {
        keys: ["j"],
        action: () => this.selectNextPath(),
      },
      {
        keys: ["ArrowLeft"],
        action: () => this.handleArrowLeftKey(),
      },
      {
        keys: ["h"],
        action: () => this.handleArrowLeftKey(),
      },
      {
        keys: ["ArrowRight"],
        action: () => this.toggleExpandByPathStr(this._selectedPath, true),
      },
      {
        keys: ["l"],
        action: () => this.toggleExpandByPathStr(this._selectedPath, true),
      },
      {
        keys: ["o"],
        action: () => this.toggleExpandByPathStr(this._selectedPath),
      },
      {
        keys: ["Space"],
        action: () => this.toggleExpandByPathStr(this._selectedPath),
      },
      {
        keys: ["y", "y"],
        action: () => this.copySelectedValue(),
      },
      {
        keys: ["ctrl+d"],
        action: () => this.scrollDownHalfPage(),
      },
      {
        keys: ["ctrl+u"],
        action: () => this.scrollUpHalfPage(),
      },
      {
        keys: ["g", "g"],
        action: () => this.goToFirstItem(),
      },
      {
        keys: ["G"],
        action: () => this.goToLastItem(),
      },
      {
        keys: ["z", "z"],
        action: () => this.centerSelectedItem(),
      },
      {
        keys: ["/"],
        action: () => this.handleShowSearch(true),
      },
      {
        keys: ["?"],
        action: () => this.handleShowSearch(false),
      },
      {
        keys: ["n"],
        action: () => {
          this.runSearch(this._searchForward, true);
        },
      },
      {
        keys: ["N"],
        action: () => {
          this.runSearch(!this._searchForward, true);
        },
      },
      {
        keys: ["Escape"],
        action: () => {
          if (this._pendingSearchResult) {
            this._pendingSearchResult = undefined;
          }
        },
      },
    );
  }

  private handleScroll() {
    this._visibleStartRowIndex = Math.floor(
      this.shadowRoot!.host.scrollTop / ROW_HEIGHT,
    );
  }

  update(changedProperties: PropertyValues): void {
    if (changedProperties.has("_showFilter")) {
      if (!this._showFilter) {
        this._filter = this._filterInput?.value || "";
      }
    } else if (changedProperties.has("_showSearch")) {
      if (!this._showSearch) {
        this._search = this._searchInput?.value || "";
      }
    } else if (changedProperties.has("_search")) {
      this.runSearch(this._searchForward);
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
      if (this._selectedPath) this.scrollToPath(this._selectedPath);
    } else if (changedProperties.has("_showFilter")) {
      if (this._showFilter) {
        if (this._filterInput) {
          this._filterInput.focus();
          if (this._filter.length > 0) {
            this._filterInput.value = this._filter;
            // apply filter by triggering input event
            this._filterInput.dispatchEvent(
              new Event("input", { bubbles: true }),
            );
            this._filterInput.select();
          }
        }
      } else {
        this._filterButton?.focus();
        clearFilter(this._tree);
        this.requestUpdate();
      }
    } else if (changedProperties.has("_showSearch")) {
      if (this._showSearch) {
        if (this._searchInput) {
          this._searchInput.focus();
          if (this._search.length > 0) {
            this._searchInput.value = this._search;
            this._searchInput.dispatchEvent(
              new Event("input", { bubbles: true }),
            );
            this._searchInput.select();
          }
        }
        if (this._selectedPath) this.scrollToPath(this._selectedPath, "center");
      } else {
        this._searchButton?.focus();
        this.requestUpdate();
      }
    }
  }
  private indexToTop(index: number): number {
    return this.getStickyHeight() + index * ROW_HEIGHT;
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

const hasParent = (ele: Node, parentClass: string) => {
  let p: Node | null = ele;
  while (p) {
    if (p instanceof HTMLElement && p.classList.contains(parentClass)) {
      return true;
    }
    p = p.parentNode;
  }
  return false;
};

const createRegex = (value: string) => {
  const hasCapitalLetter = value.match(/[A-Z]/);
  return new RegExp(escapeRegExp(value), hasCapitalLetter ? "" : "i");
};
