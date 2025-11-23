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
import showIcon from "../assets/images/show.svg";
import { sort as sortKeys } from "json-keys-sort";

type TreeItem = {
  expanded?: boolean;
  children?: TreeItem[];
};

type JsonType = "array" | "object" | "string" | "number" | "boolean" | "null";

type JsonTreeItem = Omit<TreeItem, "children"> & {
  path: string[];
  key?: string;
  value: any;
  type?: JsonType;
  summary: HTMLTemplateResult;
  children?: JsonTreeItem[];
  isArrayChild?: boolean;
  hidden?: boolean;
  valueRender?: HTMLTemplateResult;
};

function isLeaf(item: TreeItem): boolean {
  return item.children === undefined;
}

function getItemByPath(
  tree: JsonTreeItem,
  path: string[],
): JsonTreeItem | undefined {
  let current: JsonTreeItem | undefined = tree;
  for (const key of path) {
    if (!current) break;
    if (current.children) {
      current = current.children.find((child) => child.key === key);
    }
  }
  return current;
}

function setExpanded(tree: JsonTreeItem, expanded: boolean) {
  tree.expanded = expanded;
  tree.children?.forEach((child) => {
    setExpanded(child, expanded);
  });
}

function escapeRegExp(str: string) {
  return str.replace(/[-\/\\^$*+?.()|[\]{}]/g, "\\$&");
}

function isMatchTreeItem(item: JsonTreeItem, filter: RegExp) {
  if (item.key) {
    if (item.isArrayChild && filter.source === item.key) {
      return true;
    } else if (!item.isArrayChild && filter.test(item.key)) {
      return true;
    } else if (typeof item.value === "string") {
      return filter.test(item.value);
    } else if (typeof item.value === "number") {
      return filter.source === item.value.toString();
    } else if (typeof item.value === "boolean") {
      return filter.source === item.value.toString();
    } else {
      return false;
    }
  } else {
    return true;
  }
}

function filterTree(tree: JsonTreeItem, filter: RegExp) {
  if (tree.children && tree.children.length > 0) {
    for (const child of tree.children) {
      filterTree(child, filter);
    }
    tree.hidden = !isMatchTreeItem(tree, filter);
    if (tree.hidden) {
      tree.hidden = tree.children.every((child) => child.hidden);
    }
  } else if (tree.key) {
    tree.hidden = !isMatchTreeItem(tree, filter);
  }
}

function clearFilter(tree: JsonTreeItem) {
  tree.hidden = false;
  tree.children?.forEach(clearFilter);
}

const jsonType = (json: any): JsonType => {
  if (json === null) {
    return "null";
  } else if (Array.isArray(json)) {
    return "array";
  } else if (typeof json === "object" && json !== null) {
    return "object";
  } else if (typeof json === "string") {
    return "string";
  } else if (typeof json === "number") {
    return "number";
  } else if (typeof json === "boolean") {
    return "boolean";
  } else {
    throw new Error(`Unknown JSON type: ${typeof json}`);
  }
};

function tokenizeJson(
  json: any,
  callback: (
    type: "key" | "value" | ":" | "," | "[" | "]" | "{" | "}" | "ellipsis",
    text: any,
  ) => "stop" | undefined,
) {
  if (json === undefined) {
    return callback("value", json);
  } else if (typeof json === "string") {
    return callback("value", JSON.stringify(json));
  } else if (typeof json === "boolean") {
    return callback("value", json);
  } else if (typeof json === "number") {
    return callback("value", json);
  } else if (json === null) {
    return callback("value", null);
  } else if (Array.isArray(json)) {
    callback("[", "[");
    let i = 0;
    for (; i < json.length; i++) {
      let next = tokenizeJson(json[i], callback);
      if (i < json.length - 1) {
        next = callback(",", ", ");
      }
      if (next === "stop") break;
    }
    if (i < json.length - 1) {
      callback("ellipsis", "\u2026");
    }
    callback("]", "]");
  } else if (typeof json === "object") {
    callback("{", "{");
    const entries = Object.entries(json);
    let i = 0;
    for (; i < entries.length; i++) {
      const [key, value] = entries[i]!;
      let next = callback("key", key);
      next = callback(":", ": ");
      if (next === "stop") break;
      next = tokenizeJson(value, callback);
      if (i < entries.length - 1) {
        next = callback(",", ", ");
      }
      if (next === "stop") break;
    }
    if (i < entries.length - 1) {
      callback("ellipsis", "\u2026");
    }
    callback("}", "}");
  }
}

function getClass(
  type: "key" | "value" | ":" | "," | "[" | "]" | "{" | "}" | "ellipsis",
  value: any,
) {
  if (type === "key") return "value key";
  if (type === "value") {
    if (value === null) return "value null";
    if (value === undefined) return "value undefined";
    if (typeof value === "string") return "value string";
    if (typeof value === "number") return "value number";
    if (typeof value === "boolean") return "value boolean";
    return "value";
  }
  if (type === ":") return "";
  if (type === ",") return "";
  if (type === "[") return "";
  if (type === "]") return "";
  if (type === "{") return "";
  if (type === "}") return "";
  if (type === "ellipsis") return "";
  return "";
}

const jsonSummary = (json: any): HTMLTemplateResult => {
  let length = 0;
  let spans: HTMLTemplateResult[] = [];

  tokenizeJson(json, (type, val) => {
    const text =
      val === null ? "null" : val === undefined ? "undefined" : val.toString();
    length += text.length;

    spans.push(html`<span class="${getClass(type, val)}">${text}</span>`);

    // TODO: limit length base on the width of the container
    if (length > 100) {
      return "stop";
    }
    return undefined;
  });

  return html`<span>${spans}</span>`;
};

function leafValueRenderer(
  value: JsonType,
  soundUrl: string,
  path: string[],
): HTMLTemplateResult {
  const lastPath = path[path.length - 1];
  if (typeof value === "string") {
    if (
      URL.canParse(value) &&
      (/Global\/agents\/[0-9a-fA-F-]+\/avatar/i.test(value) ||
        /.svg$/.test(value))
    ) {
      return html`<a class="avatar" href="${value}" target="_blank"
        ><img src="${value}" height="${ROW_HEIGHT}"
      /></a>`;
    } else if (URL.canParse(value)) {
      return html`<span class="value string"
        >"<a href="${value}" target="_blank">${value}</a>"</span
      >`;
    } else if (
      lastPath === "agentConsoleLogoCodeSnippet" ||
      lastPath === "controlPanelLogoCodeSnippet"
    ) {
      const anchorName = `--preview-${lastPath}`;
      const id = `html-preview-${lastPath}`;
      return html`<span class="value ${jsonType(value)}"
        ><button
          popovertarget="${id}"
          class="preview"
          style="anchor-name: ${anchorName};"
        ></button>
        <div
          id="${id}"
          class="html-preview ${lastPath}"
          style="position-anchor: ${anchorName}; top: calc(anchor(bottom) + 4px); left: anchor(left);"
          popover="auto"
          .innerHTML=${value}
        ></div>
        ${JSON.stringify(value)}</span
      >`;
    } else if (
      lastPath === "notificationIcon" ||
      lastPath === "ico" ||
      lastPath === "faviconImage"
    ) {
      return html`<img
        class="image-preview"
        src="${`data:image/png;base64,${value}`}"
        height="${ROW_HEIGHT}"
      />`;
    } else if (
      /^#[0-9a-fA-F]{6}$/.test(value) ||
      /^#[0-9a-fA-F]{3}$/.test(value) ||
      /^rgba\(\s*[0-9]+,\s*[0-9]+,\s*[0-9]+,\s*[0-9.]+\s*\)$/.test(value) ||
      /^rgb\(\s*[0-9]+,\s*[0-9]+,\s*[0-9]+\s*\)$/.test(value)
    ) {
      // FIXME: add alpha
      return html`<input
          type="color"
          value="${value.startsWith("rgb")
            ? rgbaToHex(value)
            : expandHex(value)}"
        /><span class="value ${jsonType(value)}"
          >${JSON.stringify(value)}</span
        >`;
    } else if (
      ((path[0] === "config" ||
        path[1] === "settings" ||
        path[2]?.startsWith("sound")) &&
        lastPath === "id") ||
      ((path[0] === "config" || path[1] === "preference") &&
        lastPath.endsWith("SoundId"))
    ) {
      return html`<button
          class="play-sound"
          @click=${(e: MouseEvent) => {
            const button = e.currentTarget as HTMLButtonElement;
            button.classList.toggle("playing");

            const audio = document.createElement("audio");
            audio.src = soundUrl.replace("{soundId}", value);
            audio.onended = () => button.classList.remove("playing");
            audio.onerror = () => button.classList.remove("playing");
            audio.play();
          }}
        ></button
        ><span class="value ${jsonType(value)}"
          >${JSON.stringify(value)}</span
        >`;
    }
  }

  return html`<span class="value ${jsonType(value)}"
    >${JSON.stringify(value)}</span
  >`;
}

function expandHex(hex: string) {
  if (hex.length === 4) {
    return `#${hex[1]}${hex[1]}${hex[2]}${hex[2]}${hex[3]}${hex[3]}`;
  }
  return hex;
}

function rgbaToHex(rgba: string) {
  const [r, g, b] = rgba.match(/\d+/g)!.map(Number);
  return `#${r.toString(16)}${g.toString(16)}${b.toString(16)}`;
}

const jsonToTree = (
  json: object,
  path: string[],
  isArrayChild: boolean,
  soundUrl: string,
): JsonTreeItem => {
  const key = path[path.length - 1];
  if (json === null) {
    return {
      value: json,
      key,
      path,
      summary: jsonSummary(json),
      type: "null",
      isArrayChild,
      valueRender: html`<span class="value null">null</span>`,
    };
  } else if (Array.isArray(json)) {
    const children = json.map((value, index) =>
      jsonToTree(value, [...path, index.toString()], true, soundUrl),
    );
    return {
      children,
      value: json,
      key,
      path,
      summary: jsonSummary(json),
      type: "array",
      isArrayChild,
    };
  } else if (typeof json === "object" && json !== null) {
    const children = Object.entries(json).map(
      ([key, value]): JsonTreeItem =>
        jsonToTree(value, [...path, key], false, soundUrl),
    );
    return {
      children,
      value: json,
      key,
      path,
      summary: jsonSummary(json),
      type: "object",
      isArrayChild,
    };
  } else {
    return {
      value: json,
      key,
      path,
      summary: jsonSummary(json),
      type: jsonType(json),
      isArrayChild,
      valueRender: leafValueRenderer(json, soundUrl, path),
    };
  }
};

const ROW_HEIGHT = 18;
const ACTION_ROW_HEIGHT = 20;

@customElement("json-tree2")
export class JsonTree2 extends LitElement {
  @property({ type: String })
  data: string = "";

  @state()
  private _tree!: JsonTreeItem;
  @state()
  private _showFilter = false;
  @query("input")
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
  private _visibleRows = 100;
  private _renderRowIndex = 0;
  private _totalVisibleRows = 0;

  private generateTree() {
    const reduxState = JSON.parse(this.data);
    const siteId = reduxState.agent?.siteId;
    const chatServerUrl = reduxState.config?.settings?.urls?.chatServer;
    this._tree = jsonToTree(
      sortKeys(reduxState),
      [],
      false,
      `${chatServerUrl}/DBResource/DBSound.ashx?soundId={soundId}&siteId=${siteId}`,
    );
    this._tree.expanded = true;
    this._showFilter = false;
    console.log(this._tree);
  }

  static styles = css`
    :host {
      display: flex;
      flex-direction: column;
      gap: 0.3em;
      position: relative;
    }
    :host > div {
      width: calc(100% - 2ch);
      position: absolute;
      left: 2ch;
    }
    button {
      all: unset;
      cursor: pointer;
    }
    a.avatar {
      font-size: 0;
      height: ${ROW_HEIGHT}px;
    }
    .label {
      display: flex;
      align-items: center;
      gap: 4px;
      height: ${ROW_HEIGHT}px;
      line-height: ${ROW_HEIGHT}px;
      white-space: nowrap;
      position: absolute;
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
      height: 12px;
      padding-top: 8px;
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
      border-radius: 4px;
      box-shadow: 0px 0px 4px 0px black;
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
      position: relative;
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
  `;

  #handleClick(event: MouseEvent) {
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
    const filter = new RegExp(escapeRegExp(input.value), "i");
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
          ?.map((child) => JsonTree2.totalVisibleRows(child, hasFilter))
          .reduce((acc, child) => acc + child, 0) ?? 0;
    }
    return height;
  }

  protected renderLabel(item: JsonTreeItem, indent: number): any {
    if (this._renderRowIndex < this._visibleStartRowIndex) return;
    if (this._renderRowIndex > this._visibleStartRowIndex + this._visibleRows)
      return;

    const top = ACTION_ROW_HEIGHT + (this._renderRowIndex - 1) * ROW_HEIGHT;

    if (isLeaf(item)) {
      if (item.isArrayChild) {
        return html`<div
          class="label array-child"
          style="margin-left: ${indent}ch; top: ${top}px;"
        >
          <span class="key index">${item.key}</span>
          ${item.valueRender}
        </div>`;
      } else {
        return html`<div
          class="label"
          style="margin-left: ${indent}ch; top: ${top}px;"
        >
          <span class="arrow-right invisible"></span>
          <span class="icon ${item.type}"></span>
          <span class="key">${JsonTree2.keyPrefix(item)}</span>
          ${item.valueRender}
        </div>`;
      }
    }

    const expanded = item.expanded || this._hasFilter;

    return html`
      <button
        data-path=${item.path.join(".")}
        class="label"
        @click=${this.#handleClick}
        style="margin-left: ${indent}ch; top: ${top}px;"
      >
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
              >${item.isArrayChild ? undefined : JsonTree2.keyPrefix(item)}
              ${Array.isArray(item.value)
                ? html`Array
                    <span class="value count">(${item.value.length})</span>`
                : "Object"}</span
            >`
          : html`<span
              >${item.isArrayChild ? undefined : JsonTree2.keyPrefix(item)}
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
      ? item.children
          .map((child) =>
            this.renderItem(child, indent + (item.isArrayChild ? 5 : 2)),
          )
          .filter(Boolean)
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
            <button tabindex="0" @click=${this.handleCopy}>Copy</button
            >&nbsp;<button tabindex="0" @click=${this.handleCollapseAll}>
              Collapse</button
            >&nbsp;<button tabindex="0" @click=${this.handleExpandAll}>
              Expand</button
            >&nbsp;<button tabindex="0" @click=${this.handleShowFilter}>
              Filter
            </button>
          `}
    </div>`;
  }

  render() {
    if (!this._tree || !this._tree.children || this._tree.children.length === 0)
      return html``;
    const children = this._tree.children;
    this._renderRowIndex = 0;
    this._totalVisibleRows = JsonTree2.totalVisibleRows(
      this._tree,
      this._hasFilter,
    );
    const height = ACTION_ROW_HEIGHT + this._totalVisibleRows * ROW_HEIGHT + 10;
    return html`<div style="height: ${height}px;">
      ${this.renderActions()}
      ${children.map((child) => this.renderItem(child, 0)).filter(Boolean)}
    </div>`;
  }

  connectedCallback(): void {
    super.connectedCallback();
    this.generateTree();

    const host = this.shadowRoot!.host;
    // monitor shadowRoot size change
    const observer = new ResizeObserver((e) => {
      const height = e[0].contentBoxSize[0].blockSize;
      this._visibleRows = Math.ceil(height / ROW_HEIGHT);
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
