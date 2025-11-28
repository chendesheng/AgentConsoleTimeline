import { HTMLTemplateResult } from "lit";
import { jsonSummary } from "./tokenizer";
import { leafValueRenderer } from "./leafValurRender";
import { TreeIterator } from "./iterator";

export const ROW_HEIGHT = 18;
export const ACTION_ROW_HEIGHT = 20;

export type JsonType =
  | "array"
  | "object"
  | "string"
  | "number"
  | "boolean"
  | "null";

export class JsonTreeItem {
  children?: JsonTreeItem[];
  valueRender?: () => HTMLTemplateResult;
  private _valueRenderCache?: HTMLTemplateResult;

  private _decendentsCount?: number;
  private _decendentsCountIncludeCollapsed?: number;
  private _hidden?: boolean;
  private _expanded: boolean = false;
  private _summary?: HTMLTemplateResult[];
  constructor(
    public type: JsonType,
    public key: string | number | undefined,
    public indent: number,
    public path: string[],
    public pathStr: string,
    public parentPathStr: string,
    public value: any,
  ) {}

  get expanded(): boolean {
    return this._expanded;
  }

  set expanded(value: boolean) {
    if (this._expanded === value) return;
    this._expanded = value;
    this._decendentsCount = undefined;
  }

  get hidden(): boolean {
    return this._hidden ?? false;
  }

  set hidden(value: boolean) {
    if (this._hidden === value) return;
    this._hidden = value;
    this._decendentsCount = undefined;
    this._decendentsCountIncludeCollapsed = undefined;
  }

  renderLeafValue(): HTMLTemplateResult | undefined {
    if (this._valueRenderCache) return this._valueRenderCache;
    this._valueRenderCache = this.valueRender?.();
    return this._valueRenderCache;
  }

  get isLeaf(): boolean {
    return this.children === undefined;
  }

  get isRoot(): boolean {
    return this.key === undefined;
  }

  get summary(): HTMLTemplateResult[] {
    if (this._summary) return this._summary;
    this._summary = jsonSummary(this.value);
    return this._summary;
  }

  private calcDecendentsCount(includeCollapsed: boolean) {
    if (this.hidden) {
      return 0;
    } else if (this.isLeaf) {
      return 1;
    } else if (!this.expanded && !includeCollapsed) {
      return 1;
    } else {
      return (
        this.children?.reduce((acc, child) => acc + child.decendentsCount, 1) ??
        1
      );
    }
  }

  get decendentsCount(): number {
    if (this._decendentsCount === undefined) {
      this._decendentsCount = this.calcDecendentsCount(false);
    }
    return this._decendentsCount;
  }

  resetDecendentsCountCache() {
    this._decendentsCount = undefined;
  }

  get decendentsCountIncludeCollapsed(): number {
    if (this._decendentsCountIncludeCollapsed === undefined) {
      this._decendentsCountIncludeCollapsed = this.calcDecendentsCount(true);
    }
    return this._decendentsCountIncludeCollapsed;
  }

  resetDecendentsCountIncludeCollapsedCache() {
    this._decendentsCountIncludeCollapsed = undefined;
  }

  isMatchTreeItem(filter: RegExp) {
    if (this.isRoot) return true;

    if (typeof this.key === "number" && filter.source === this.key.toString()) {
      return true;
    } else if (typeof this.key === "string" && filter.test(this.key)) {
      return true;
    } else if (typeof this.value === "string") {
      return filter.test(this.value);
    } else if (
      typeof this.value === "number" ||
      typeof this.value === "boolean"
    ) {
      return filter.source === this.value.toString();
    } else {
      return false;
    }
  }
}

export function filterTree(tree: JsonTreeItem, filter: RegExp) {
  tree.hidden = !tree.isMatchTreeItem(filter);

  if (tree.children) {
    for (const child of tree.children) {
      filterTree(child, filter);
    }

    if (tree.hidden) {
      tree.hidden = tree.children.every((child) => child.hidden);
    }
  }
}

export function clearFilter(tree: JsonTreeItem) {
  const iter = createIterator(tree, false);
  do {
    iter.current.hidden = false;
  } while (iter.next());
}

export function jsonType(json: any): JsonType {
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
}

function getItemsOfPath(tree: JsonTreeItem, path: string[]) {
  let current: JsonTreeItem | undefined = tree;
  const result: JsonTreeItem[] = [tree];
  for (const key of path) {
    if (current.children) {
      current = current.children.find((child) => {
        if (typeof child.key === "number") {
          return child.key === parseInt(key);
        } else {
          return child.key === key;
        }
      });
    }
    if (!current) break;
    result.push(current);
  }
  return result;
}

export function getItemByPath(
  tree: JsonTreeItem,
  path: string[],
): JsonTreeItem | undefined {
  const items = getItemsOfPath(tree, path);
  return items[items.length - 1];
}

export function getItemByPathStr(
  tree: JsonTreeItem,
  pathStr: string,
): JsonTreeItem | undefined {
  const path = pathStr.split(".");
  return getItemByPath(tree, path);
}

function getItemByIndex(
  tree: JsonTreeItem,
  index: number,
  hasFilter: boolean,
): JsonTreeItem | undefined {
  if (tree.children) {
    let i = 0;
    for (const child of tree.children) {
      const j = i + child.decendentsCount;

      if (i === index) {
        return child;
      } else if (i < index && index < j) {
        return getItemByIndex(child, index - i - 1, hasFilter);
      }

      i += child.decendentsCount;
    }
  }
}

export function setItemExpanded(
  tree: JsonTreeItem,
  pathStr: string,
  expanded: boolean,
) {
  const path = pathStr.split(".");
  let parents: JsonTreeItem[] = getItemsOfPath(tree, path);
  let current: JsonTreeItem | undefined = parents[parents.length - 1];

  if (current.expanded === expanded) return;
  current.expanded = expanded;
  for (const parent of parents) {
    parent.resetDecendentsCountCache();
  }
}

export function setExpanded(tree: JsonTreeItem, expanded: boolean) {
  tree.expanded = tree.isRoot ? true : expanded;
  tree.resetDecendentsCountCache();

  if (tree.children) {
    for (const child of tree.children) {
      setExpanded(child, expanded);
    }
  }
}

function createIterator(tree: JsonTreeItem, hasFilter: boolean) {
  return new TreeIterator(
    tree,
    (item) => !!item.hidden,
    (item) => {
      if (hasFilter) return false;
      return !item.expanded;
    },
  );
}

export function getIterator(
  tree: JsonTreeItem,
  hasFilter: boolean,
  startPath?: string,
) {
  const iter = createIterator(tree, hasFilter);

  if (startPath) {
    const path = startPath.split(".");
    iter.forward((item, indexPath) => {
      if (item.key!.toString() === path[0]) {
        path.shift();
        if (path.length === 0) return "stop";
        return "child";
      }
      return "sibling";
    });
  }
  return iter;
}

export function getNextItem(
  tree: JsonTreeItem,
  hasFilter: boolean,
  path: string | undefined,
) {
  if (!path) return;
  const iter = getIterator(tree, hasFilter, path);
  !iter.next() && iter.first();
  return iter.current;
}

export function getPreviousItem(
  tree: JsonTreeItem,
  hasFilter: boolean,
  path: string | undefined,
) {
  if (!path) return;
  const iter = getIterator(tree, hasFilter, path);
  !iter.previous() && iter.last();
  return iter.current;
}

export function getLastItem(tree: JsonTreeItem, hasFilter: boolean) {
  const iter = createIterator(tree, hasFilter);
  iter.last();
  return iter.current;
}

export function getFirstItem(tree: JsonTreeItem, hasFilter: boolean) {
  const iter = createIterator(tree, hasFilter);
  iter.first();
  return iter.current;
}

export function totalRows(item: JsonTreeItem, hasFilter: boolean): number {
  const count = hasFilter
    ? item.decendentsCountIncludeCollapsed
    : item.decendentsCount;
  return count - 1;
}

export function* sliceItems(
  tree: JsonTreeItem,
  hasFilter: boolean,
  startIndex: number,
  length: number,
) {
  const startItem = getItemByIndex(tree, startIndex, hasFilter);
  if (!startItem) return;

  const iter = getIterator(tree, hasFilter, startItem.pathStr);
  for (let i = 0; i < length; i++) {
    yield iter.current;
    if (!iter.next()) break;
  }
}

export function indexOfPathStr(
  tree: JsonTreeItem,
  hasFilter: boolean,
  pathStr: string,
) {
  const iter = getIterator(tree, hasFilter, pathStr);
  let current = tree;
  let result = 0;
  for (let i = 0; i < iter.indexPath.length; i++) {
    const index = iter.indexPath[i];
    for (let j = 0; j < index; j++) {
      result += current.children![j].decendentsCount;
    }
    result += 1;
    current = current.children![index];
  }
  return result - 1;
}

export const jsonToTree = (
  json: object,
  path: string[],
  indent: number,
  options: {
    soundUrl: string;
    campaignPreviewUrl: string;
    controlPanelUrl: string;
    partnerPortalUrl: string;
    siteId: number;
    partnerId: number;
    parentJson?: object;
  },
): JsonTreeItem => {
  const key = Array.isArray(options.parentJson)
    ? parseInt(path[path.length - 1])
    : path[path.length - 1];
  const parentPathStr = path.slice(0, -1).join(".");
  const pathStr = [parentPathStr, key?.toString()].filter(Boolean).join(".");
  const nextIndent = Array.isArray(options.parentJson)
    ? indent + options.parentJson.length.toString().length + 5
    : indent + 2;

  const item = new JsonTreeItem(
    jsonType(json),
    key,
    indent,
    path,
    pathStr,
    parentPathStr,
    json,
  );
  if (item.isRoot) {
    item.expanded = true;
  }

  if (json !== null && Array.isArray(json)) {
    const children = json.map((value, index) =>
      jsonToTree(value, [...path, index.toString()], nextIndent, {
        ...options,
        parentJson: json,
      }),
    );
    item.children = children;
    return item;
  } else if (json !== null && typeof json === "object") {
    const children = Object.entries(json).map(
      ([key, value]): JsonTreeItem =>
        jsonToTree(value, [...path, key], nextIndent, {
          ...options,
          parentJson: json,
        }),
    );
    item.children = children;
    return item;
  } else {
    item.valueRender = () => leafValueRenderer(json, pathStr, options);
    return item;
  }
};
