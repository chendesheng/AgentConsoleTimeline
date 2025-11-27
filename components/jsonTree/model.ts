import { HTMLTemplateResult } from "lit";
import { jsonSummary } from "./tokenizer";
import { leafValueRenderer } from "./leafValurRender";

export const ROW_HEIGHT = 18;
export const ACTION_ROW_HEIGHT = 20;

export type TreeItem = {
  expanded?: boolean;
  children?: TreeItem[];
};

export type JsonType =
  | "array"
  | "object"
  | "string"
  | "number"
  | "boolean"
  | "null";

export type JsonTreeItem = Omit<TreeItem, "children"> & {
  path: string[];
  pathStr: string;
  parentPathStr: string;
  key?: string | number;
  value: any;
  type?: JsonType;
  summary?: HTMLTemplateResult;
  children?: JsonTreeItem[];
  hidden?: boolean;
  valueRender?: () => HTMLTemplateResult;
  valueRenderCache?: HTMLTemplateResult;
  indent: number;
};

export function isLeaf(item: TreeItem): boolean {
  return item.children === undefined;
}

export function isRoot(item: JsonTreeItem): boolean {
  return item.key === undefined;
}

export function filterTree(tree: JsonTreeItem, filter: RegExp) {
  tree.hidden = !isMatchTreeItem(tree, filter);

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
  for (const item of walkTreeAll(tree)) {
    item.hidden = false;
  }
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

function isMatchTreeItem(item: JsonTreeItem, filter: RegExp) {
  if (isRoot(item)) return true;

  if (typeof item.key === "number" && filter.source === item.key.toString()) {
    return true;
  } else if (typeof item.key === "string" && filter.test(item.key)) {
    return true;
  } else if (typeof item.value === "string") {
    return filter.test(item.value);
  } else if (
    typeof item.value === "number" ||
    typeof item.value === "boolean"
  ) {
    return filter.source === item.value.toString();
  } else {
    return false;
  }
}

export function getItemByPath(
  tree: JsonTreeItem,
  path: string[],
): JsonTreeItem | undefined {
  let current: JsonTreeItem | undefined = tree;
  for (const key of path) {
    if (!current) break;
    if (current.children) {
      current = current.children.find((child) => {
        if (typeof child.key === "number") {
          return child.key === parseInt(key);
        } else {
          return child.key === key;
        }
      });
    }
  }
  return current;
}

export function getItemByPathStr(
  tree: JsonTreeItem,
  pathStr: string,
): JsonTreeItem | undefined {
  const path = pathStr.split(".");
  return getItemByPath(tree, path);
}

export function setExpanded(tree: JsonTreeItem, expanded: boolean) {
  for (const item of walkTreeIncludeCollapsed(tree)) {
    item.expanded = expanded;
  }
}

function* walkTreeAll(tree: JsonTreeItem): Generator<JsonTreeItem, void, void> {
  if (!isRoot(tree)) yield tree;
  if (tree.children) {
    for (const child of tree.children) {
      yield* walkTreeAll(child);
    }
  }
}

function* walkTreeIncludeCollapsed(
  tree: JsonTreeItem,
): Generator<JsonTreeItem, void, void> {
  if (tree.hidden) return;
  if (!isRoot(tree)) yield tree;
  if (tree.children) {
    for (const child of tree.children) {
      yield* walkTreeIncludeCollapsed(child);
    }
  }
}

function* walkTree(tree: JsonTreeItem): Generator<JsonTreeItem, void, void> {
  if (tree.hidden) return;
  if (!isRoot(tree)) yield tree;
  if (!tree.expanded) return;
  if (tree.children) {
    for (const child of tree.children) {
      yield* walkTree(child);
    }
  }
}

export function getNextItem(
  tree: JsonTreeItem,
  hasFilter: boolean,
  path: string | undefined,
) {
  if (!path) return;

  const iter = hasFilter ? walkTreeIncludeCollapsed(tree) : walkTree(tree);
  while (true) {
    const { value, done } = iter.next();
    if (done) break;
    if (value.pathStr === path) {
      const { done: nextDone, value: nextValue } = iter.next();
      if (nextDone) break;
      return nextValue;
    }
  }
}

export function getPreviousItem(
  tree: JsonTreeItem,
  hasFilter: boolean,
  path: string | undefined,
) {
  if (!path) return;

  const iter = hasFilter ? walkTreeIncludeCollapsed(tree) : walkTree(tree);
  let previous: JsonTreeItem | undefined;
  while (true) {
    const { value, done } = iter.next();

    if (value) {
      if (value.pathStr === path) {
        break;
      }
      previous = value;
    }

    if (done) break;
  }
  return previous;
}

export function getLastItem(tree: JsonTreeItem, hasFilter: boolean) {
  const iter = hasFilter ? walkTreeIncludeCollapsed(tree) : walkTree(tree);
  let last: JsonTreeItem | undefined;
  while (true) {
    const { value, done } = iter.next();
    if (value) last = value;
    if (done) break;
  }
  return last;
}

export function getFirstItem(tree: JsonTreeItem, hasFilter: boolean) {
  const iter = hasFilter ? walkTreeIncludeCollapsed(tree) : walkTree(tree);
  const { value, done } = iter.next();
  if (!done) return value;
}

export function totalRows(item: JsonTreeItem, hasFilter: boolean): number {
  const iter = hasFilter ? walkTreeIncludeCollapsed(item) : walkTree(item);
  let count = 0;
  for (const _ of iter) {
    count++;
  }
  return count;
}

export function* visibleItems(
  tree: JsonTreeItem,
  hasFilter: boolean,
  startIndex: number,
  endIndex: number,
) {
  let i = 0;
  const iter = hasFilter ? walkTreeIncludeCollapsed(tree) : walkTree(tree);
  for (const item of iter) {
    if (i >= startIndex && i < endIndex) {
      yield item;
    }
    i++;
  }
}

export function indexOfPathStr(
  tree: JsonTreeItem,
  hasFilter: boolean,
  pathStr: string,
) {
  let i = 0;
  const iter = hasFilter ? walkTreeIncludeCollapsed(tree) : walkTree(tree);
  for (const item of iter) {
    if (item.pathStr === pathStr) {
      return i;
    }
    i++;
  }
  return -1;
}

export function getSummary(item: JsonTreeItem): HTMLTemplateResult {
  if (item.summary) return item.summary;
  item.summary = jsonSummary(item.value);
  return item.summary;
}

export function renderLeafValue(
  item: JsonTreeItem,
): HTMLTemplateResult | undefined {
  if (item.valueRenderCache) return item.valueRenderCache;
  item.valueRenderCache = item.valueRender?.();
  return item.valueRenderCache;
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
  if (json !== null && Array.isArray(json)) {
    const children = json.map((value, index) =>
      jsonToTree(value, [...path, index.toString()], nextIndent, {
        ...options,
        parentJson: json,
      }),
    );
    return {
      indent,
      children,
      value: json,
      key,
      path,
      pathStr,
      parentPathStr,
      type: "array",
    };
  } else if (json !== null && typeof json === "object") {
    const children = Object.entries(json).map(
      ([key, value]): JsonTreeItem =>
        jsonToTree(value, [...path, key], nextIndent, {
          ...options,
          parentJson: json,
        }),
    );
    return {
      indent,
      children,
      value: json,
      key,
      path,
      pathStr,
      parentPathStr,
      type: "object",
    };
  } else {
    return {
      indent,
      value: json,
      key,
      path,
      pathStr,
      parentPathStr,
      type: jsonType(json),
      valueRender: () => leafValueRenderer(json, pathStr, options),
    };
  }
};
