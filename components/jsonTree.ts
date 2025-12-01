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
  private _scrollTop = 0;
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

  private get _totalRows(): number {
    return totalRows(this._tree, this._expandAll);
  }

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
    this._selectedPath = undefined;

    if (this._tree.getDecendentsCount(true) < 200) {
      setExpanded(this._tree, true);
    }
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
      border: none;
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
    ::highlight(search-result-highlight) {
      background-color: var(--search-highlight-background-color-active);
      color: var(--search-highlight-text-color-active);
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
    this._scrollTop = 0;
  }

  private handleClick(event: MouseEvent) {
    (event.currentTarget as HTMLElement).focus();

    const rowElement = getRowElement(event.target as HTMLElement);
    if (!rowElement) return;

    if (hasParent(rowElement, "breadcrumb")) {
      if (!this.shadowRoot) return;
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

  private handleShowSearchInput(forward: boolean = true) {
    if (this._showFilter) return;
    this._searchForward = forward;
    this._showSearch = true;
    this._pendingSearchSavedScrollTop = this._scrollTop;
  }

  private handleFilterInputKeydown(e: KeyboardEvent) {
    e.stopPropagation();
    if (e.key === "Escape") {
      this._showFilter = false;
    }
  }

  @state()
  private _pendingSearchResult?: TreeIterator<JsonTreeItem>;
  @state()
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
      this._selectedPath = this._pendingSearchResult.current.pathStr;
      this.requestUpdate();
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
    if (this._pendingSearchSavedScrollTop)
      this._scrollTop = this._pendingSearchSavedScrollTop;
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
    } else {
      this._pendingSearchResult = undefined;
      this.restorePendingSearchExpanded();
      this.restorePendingSearchScrollTop();
    }
  }

  private createHighlightRange(node: Text, re: RegExp) {
    const m = node.textContent?.match(re);
    if (!m || m.index === undefined) return;

    const rg = document.createRange();
    rg.setStart(node, m.index);
    rg.setEnd(node, m.index + m[0].length);
    return rg;
  }

  private highlightAllSearchResult() {
    CSS.highlights.delete("search-result-highlight");
    if (!this._pendingSearchResult) return;

    const document = this._rowsElement.ownerDocument;
    const domWalker = document.createTreeWalker(
      this._rowsElement,
      NodeFilter.SHOW_TEXT,
      {
        acceptNode: (node) => {
          if (node instanceof Text) {
            if (hasParent(node, "summary")) {
              return NodeFilter.FILTER_SKIP;
            }
            return NodeFilter.FILTER_ACCEPT;
          }

          return NodeFilter.FILTER_SKIP;
        },
      },
    );

    const re = createRegex(this._search);
    const rgs = [];
    while (domWalker.nextNode()) {
      const rg = this.createHighlightRange(domWalker.currentNode as Text, re);
      if (rg) rgs.push(rg);
    }

    const highlight = new Highlight(...rgs);
    CSS.highlights.set("search-result-highlight", highlight);
  }

  private highlightPendingSearchResult() {
    CSS.highlights.delete("search-result-highlight");

    if (!this._pendingSearchResult) return;
    const ele = this.getElementByPathStr(
      this._pendingSearchResult.current.pathStr,
    );
    if (!ele) return;
    const document = ele.ownerDocument;
    const domWalker = document.createTreeWalker(ele, NodeFilter.SHOW_TEXT, {
      acceptNode: (node) => {
        if (node instanceof Text) {
          return NodeFilter.FILTER_ACCEPT;
        }
        return NodeFilter.FILTER_SKIP;
      },
    });

    const re = createRegex(this._search);
    while (domWalker.nextNode()) {
      const rg = this.createHighlightRange(domWalker.currentNode as Text, re);
      if (rg) {
        const highlight = new Highlight(rg);
        CSS.highlights.set("search-result-highlight", highlight);
        break;
      }
    }
  }

  private handleSearchInput(e: Event) {
    e.stopPropagation();

    if (!this._showSearch) return;
    const input = e.target as HTMLInputElement;
    this._search = input.value;
  }

  private handleSearchInputKeydown(e: KeyboardEvent) {
    if (e.key === "Escape") {
      e.stopPropagation();
      e.preventDefault();

      this.restorePendingSearchExpanded();
      this.restorePendingSearchScrollTop();
      this._pendingSearchResult = undefined;
      this._showSearch = false;
    } else if (e.key === "Enter") {
      e.stopPropagation();
      e.preventDefault();

      this.acceptPendingSearchResult();
    }
  }

  private getElementByPathStr(
    pathStr: string | undefined,
  ): HTMLElement | undefined {
    if (!pathStr) return undefined;
    return this.shadowRoot?.querySelector(
      `.rows > .label[data-path="${pathStr}"]`,
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
      top: this._scrollTop + ACTION_ROW_HEIGHT + BREADCRUMB_ROW_HEIGHT,
      bottom: this._scrollTop + this._visibleHeight,
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
      this._scrollTop = newScrollTop;
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
    if (e.target instanceof HTMLInputElement) return;

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
    this._rowsElement.focus();

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
    const startRowIndex = scrollTopToRowIndex(this._scrollTop);
    const selectedClass = item.pathStr === this._selectedPath ? "selected" : "";
    const top = this.indexToTop(startRowIndex + index);
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
            <button
              tabindex="0"
              class="search"
              @click=${this.handleShowSearchInput}
            >
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
      (this.showBreadcrumb ? BREADCRUMB_ROW_HEIGHT : 0)
    );
  }

  private getTotalHeight(): number {
    return this.getStickyHeight() + this._totalRows * ROW_HEIGHT;
  }

  render() {
    if (!this._tree || !this._tree.children || this._tree.children.length === 0)
      return html``;
    const height = this.getTotalHeight();
    const startRowIndex = scrollTopToRowIndex(this._scrollTop);
    const visibleItems = Array.from(
      sliceItems(this._tree, this._expandAll, startRowIndex, this._visibleRows),
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
        action: () => this.handleShowSearchInput(true),
      },
      {
        keys: ["?"],
        action: () => this.handleShowSearchInput(false),
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
      {
        keys: ["ctrl+y"],
        action: () => {
          if (this.shadowRoot) {
            const index = scrollTopToRowIndex(this._scrollTop);
            if (index > 0) {
              this._scrollTop = (index - 1) * ROW_HEIGHT;
            }
          }
        },
      },
      {
        keys: ["ctrl+e"],
        action: () => {
          if (this.shadowRoot) {
            const index = scrollTopToRowIndex(this._scrollTop);
            if (index < this._totalRows - this._visibleRows) {
              this._scrollTop = (index + 1) * ROW_HEIGHT;
            }
          }
        },
      },
    );
  }

  protected firstUpdated(_changedProperties: PropertyValues): void {
    if (
      this.shadowRoot?.host?.ownerDocument?.activeElement?.classList.contains(
        "detail-header-tab",
      )
    ) {
      this._rowsElement.focus();
    }
  }

  disconnectedCallback(): void {
    super.disconnectedCallback();
    if (!this.shadowRoot) return;
    this.shadowRoot.host.removeEventListener("scroll", this.handleScroll);
  }

  private handleScroll() {
    if (!this.shadowRoot) return;

    this._scrollTop = this.shadowRoot.host.scrollTop;
  }

  update(changedProperties: PropertyValues): void {
    if (changedProperties.has("_showFilter")) {
      if (!this._showFilter) {
        this._filter = this._filterInput?.value || "";
      }
    }

    if (changedProperties.has("_showSearch")) {
      if (!this._showSearch) {
        this._search = this._searchInput?.value || "";
      }
    }

    if (changedProperties.has("_search")) {
      this.runSearch(this._searchForward);
    }

    if (changedProperties.has("_selectedPath")) {
      if (this._selectedPath) this.scrollToPath(this._selectedPath);
    }

    super.update(changedProperties);
  }

  updated(changedProperties: PropertyValues): void {
    super.updated(changedProperties);
    if (
      changedProperties.has("data") ||
      changedProperties.has("_showNestedJson")
    ) {
      this.generateTree();
    }

    if (
      changedProperties.has("_scrollTop") &&
      this.shadowRoot &&
      this._scrollTop !== undefined
    ) {
      this.shadowRoot.host.scrollTop = this._scrollTop;
    }

    if (changedProperties.has("_showFilter")) {
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
        if (changedProperties.get("_showFilter")) {
          this._filterButton?.focus();
          clearFilter(this._tree);
          this.requestUpdate();
        }
      }
    }

    if (changedProperties.has("_showSearch")) {
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
        if (this._selectedPath) this.scrollToPath(this._selectedPath);
      } else {
        if (changedProperties.get("_showSearch")) {
          this._searchButton?.focus();
        }
      }
    }

    if (this._showSearch) {
      this.highlightPendingSearchResult();
    } else {
      this.highlightAllSearchResult();
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

const scrollTopToRowIndex = (scrollTop: number) => {
  return Math.max(0, Math.floor(scrollTop / ROW_HEIGHT));
};
