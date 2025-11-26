import { HTMLTemplateResult } from "lit";

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
  key?: string;
  value: any;
  type?: JsonType;
  summary: HTMLTemplateResult;
  children?: JsonTreeItem[];
  isArrayChild: boolean;
  hidden?: boolean;
  valueRender?: HTMLTemplateResult;
  indent: number;
};

export function isLeaf(item: TreeItem): boolean {
  return item.children === undefined;
}

export function filterTree(tree: JsonTreeItem, filter: RegExp) {
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

export function clearFilter(tree: JsonTreeItem) {
  tree.hidden = false;
  tree.children?.forEach(clearFilter);
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

export function getItemByPath(
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

export function getItemByPathStr(
  tree: JsonTreeItem,
  pathStr: string,
): JsonTreeItem | undefined {
  const path = pathStr.split(".");
  return getItemByPath(tree, path);
}

export function setExpanded(tree: JsonTreeItem, expanded: boolean) {
  tree.expanded = expanded;
  tree.children?.forEach((child) => {
    setExpanded(child, expanded);
  });
}

function* walkTreeIncludeCollapsed(
  tree: JsonTreeItem,
): Generator<JsonTreeItem, void, void> {
  if (tree.hidden) return;
  yield tree;
  if (tree.children) {
    for (const child of tree.children) {
      yield* walkTreeIncludeCollapsed(child);
    }
  }
}

function* walkTree(tree: JsonTreeItem): Generator<JsonTreeItem, void, void> {
  if (tree.hidden) return;
  yield tree;
  if (tree.expanded && tree.children) {
    for (const child of tree.children) {
      yield* walkTree(child);
    }
  }
}

export function getNextItem(tree: JsonTreeItem, path: string | undefined) {
  if (!path) return;

  const iter = walkTree(tree);
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

export function getPreviousItem(tree: JsonTreeItem, path: string | undefined) {
  if (!path) return;

  const iter = walkTree(tree);
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

export function getLastItem(tree: JsonTreeItem) {
  const iter = walkTree(tree);
  let last: JsonTreeItem | undefined;
  while (true) {
    const { value, done } = iter.next();
    if (value) last = value;
    if (done) break;
  }
  return last;
}

export function getFirstItem(tree: JsonTreeItem) {
  const iter = walkTree(tree);
  iter.next();

  const { value, done } = iter.next();
  if (!done) return value;
}

export function totalVisibleRows(
  item: JsonTreeItem,
  hasFilter: boolean,
): number {
  const iter = hasFilter ? walkTreeIncludeCollapsed(item) : walkTree(item);
  let count = 0;
  for (const _ of iter) {
    count++;
  }
  return count;
}

export function* visibleItems(
  tree: JsonTreeItem,
  startIndex: number,
  endIndex: number,
) {
  let i = 0;
  const iter = walkTree(tree);
  const { done } = iter.next();
  if (done) return;

  for (const item of iter) {
    if (i >= startIndex && i < endIndex) {
      yield item;
    }
    i++;
  }
}

export function indexOfPathStr(tree: JsonTreeItem, pathStr: string) {
  let i = 0;
  for (const item of walkTree(tree)) {
    if (item.pathStr === pathStr) {
      return i;
    }
    i++;
  }
  return -1;
}
