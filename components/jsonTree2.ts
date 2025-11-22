import {
  css,
  html,
  HTMLTemplateResult,
  LitElement,
  PropertyValues,
  unsafeCSS,
} from "lit";
import { customElement, property, state } from "lit/decorators.js";
import typeIcons from "../assets/images/TypeIcons.svg";

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

const jsonToTree = (
  json: object,
  path: string[] = [],
  isArrayChild: boolean = false,
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
    };
  } else if (Array.isArray(json)) {
    return {
      children: json.map((value, index) =>
        jsonToTree(value, [...path, index.toString()], true),
      ),
      value: json,
      key,
      path,
      summary: jsonSummary(json),
      type: "array",
      isArrayChild,
    };
  } else if (typeof json === "object" && json !== null) {
    return {
      children: Object.entries(json).map(
        ([key, value]): JsonTreeItem => jsonToTree(value, [...path, key]),
      ),
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
    };
  }
};

@customElement("json-tree2")
export class JsonTree2 extends LitElement {
  @property({ type: String })
  data: string = "";

  @state()
  private _tree!: JsonTreeItem;

  private generateTree() {
    this._tree = jsonToTree(JSON.parse(this.data));
    this._tree.expanded = true;
    console.log(this._tree);
  }

  static styles = css`
    :host {
      padding: 1ch;
      display: flex;
      flex-direction: column;
      gap: 0.3em;
    }
    button {
      all: unset;
      cursor: pointer;
    }
    .label {
      display: flex;
      align-items: center;
      gap: 4px;
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

  protected renderLabel(item: JsonTreeItem, indent: number): any {
    if (isLeaf(item)) {
      if (item.isArrayChild) {
        return html`<div
          class="label array-child"
          style="margin-left: ${indent}ch"
        >
          <span class="key index">${item.key}</span>
          <span class="value ${item.type}">${JSON.stringify(item.value)}</span>
        </div>`;
      } else {
        return html`<div class="label" style="margin-left: ${indent}ch">
          <span class="arrow-right invisible"></span>
          <span class="icon ${item.type}"></span>
          <span class="key">${item.key ? `${item.key}: ` : ""}</span>
          <span class="value ${item.type}">${JSON.stringify(item.value)}</span>
        </div>`;
      }
    }

    return html`
      <button
        data-path=${item.path.join(".")}
        class="label"
        @click=${this.#handleClick}
        style="margin-left: ${indent}ch"
      >
        ${item.isArrayChild
          ? html`<span class="key index">${item.key}</span>`
          : undefined}
        ${item.expanded
          ? html`<span class="arrow-right expanded"></span>`
          : html`<span class="arrow-right"></span>`}
        ${item.isArrayChild
          ? undefined
          : html`<span class="icon ${item.type}"></span>`}
        ${item.expanded
          ? html`<span
              >${item.isArrayChild
                ? undefined
                : item.key
                ? `${item.key}: `
                : undefined}
              ${Array.isArray(item.value)
                ? html`Array
                    <span class="value count">(${item.value.length})</span>`
                : "Object"}</span
            >`
          : html`<span
              >${item.isArrayChild
                ? undefined
                : item.key
                ? `${item.key}: `
                : undefined}
              ${item.summary}</span
            >`}
      </button>
    `;
  }

  protected renderItem(item: JsonTreeItem, indent: number): any {
    return html`${this.renderLabel(item, indent)}
    ${item.children && item.expanded
      ? item.children.map((child) =>
          this.renderItem(child, indent + (item.isArrayChild ? 5 : 2)),
        )
      : null}`;
  }

  render() {
    if (!this._tree) return html``;
    const children = this._tree.children;
    return children && children.length > 0
      ? html`${children.map((child) => this.renderItem(child, 0))}`
      : null;
  }

  connectedCallback(): void {
    super.connectedCallback();
    this.generateTree();
  }

  updated(changedProperties: PropertyValues): void {
    super.updated(changedProperties);
    if (changedProperties.has("data")) {
      this.generateTree();
    }
  }
}
