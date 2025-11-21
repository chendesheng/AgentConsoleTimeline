import { css, html, LitElement, PropertyValues } from "lit";
import { customElement, property } from "lit/decorators";

type TreeItem = {
  icon: string;
  label: string;
  expanded?: boolean;
  children?: TreeItem[];
  depth?: number;
};

type JsonTreeItem = Omit<TreeItem, "children"> & {
  key?: string;
  value: any;
  children?: JsonTreeItem[];
};

const jsonToTree = (json: object, key?: string): JsonTreeItem => {
  if (json === undefined) {
    return {
      icon: "📄",
      label: "undefined",
      value: json,
      key,
    };
  } else if (Array.isArray(json)) {
    return {
      icon: "📄",
      label: JSON.stringify(json),
      children: json.map((value, index) => jsonToTree(value, index.toString())),
      value: json,
      key,
    };
  } else if (typeof json === "object") {
    return {
      icon: "📄",
      label: `${key}:${JSON.stringify(json)}`,
      children: Object.entries(json).map(
        ([key, value]): JsonTreeItem => jsonToTree(value, key),
      ),
      value: json,
      key,
    };
  } else {
    return {
      icon: "📄",
      label: `${key}:${JSON.stringify(json)}`,
      value: json,
      key,
    };
  }
};

@customElement("json-tree2")
export class JsonTree2 extends LitElement {
  @property({ type: String })
  data: string = "";

  private tree!: JsonTreeItem;

  static styles = css``;

  protected renderLabel(item: JsonTreeItem): any {
    return html`
      <div class="item">
        ${item.expanded
          ? html`<div class="expanded">▼</div>`
          : html`<div class="collapsed">▶</div>`}
        <div class="label">${item.label}</div>
      </div>
    `;
  }

  protected renderItem(item: JsonTreeItem): any {
    return html`<div role="treeitem">
      ${this.renderLabel(item)}
      <div class="children">
        ${item.children && item.expanded
          ? item.children.map((child) => this.renderItem(child))
          : null}
      </div>
    </div>`;
  }

  render() {
    return this.renderItem(this.tree);
  }

  updated(changedProperties: PropertyValues) {
    if (changedProperties.has("data")) {
      this.tree = jsonToTree(JSON.parse(this.data));
    }
  }
}
