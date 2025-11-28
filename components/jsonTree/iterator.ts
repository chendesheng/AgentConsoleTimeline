export type TreeItem = {
  children?: TreeItem[];
  [key: string]: any;
};

// multi-way tree iterator
export class TreeIterator<T extends { children?: T[] } = TreeItem> {
  private _tree: T;
  private _indexPath: number[];

  private _skip?: (item: T) => boolean;
  private _skipChildren?: (item: T) => boolean;

  constructor(
    tree: T,
    skip?: (item: T) => boolean,
    skipChildren?: (item: T) => boolean,
  ) {
    this._tree = tree;
    this._indexPath = [0];
    this._skip = skip;
    this._skipChildren = skipChildren;
  }

  private isSkip(item: T) {
    return this._skip?.(item) ?? false;
  }

  private getParentItem() {
    let item: T | undefined = this._tree;
    for (let i = 0; i < this._indexPath.length - 1; i++) {
      item = item.children?.[this._indexPath[i]];
      if (!item) break;
    }
    return item;
  }

  private getItem() {
    let item: T | undefined = this._tree;
    for (const i of this._indexPath) {
      item = item.children?.[i];
      if (!item) break;
    }
    return item;
  }

  private goToParent() {
    if (this._indexPath.length === 1) return false;
    this._indexPath.pop();
    return true;
  }

  private goToChild() {
    const item = this.getItem();
    if (!item) return false;
    if (
      !item.children ||
      item.children.length === 0 ||
      this._skipChildren?.(item)
    )
      return false;

    const i = this.skipForward(item.children, 0);
    if (i === -1) return false;
    this._indexPath.push(i);
    return true;
  }

  private goToRightMostChild() {
    const item = this.getItem();
    if (!item) return false;
    if (
      !item.children ||
      item.children.length === 0 ||
      this._skipChildren?.(item)
    )
      return false;

    const i = this.skipBackward(item.children, item.children.length - 1);
    if (i === -1) return false;
    this._indexPath.push(i);
    return true;
  }

  private goToRightMostDescendant() {
    if (!this.goToRightMostChild()) return false;
    while (this.goToRightMostChild());
  }

  private skipForward(children: T[] | undefined, i: number) {
    if (!children) return -1;
    while (i < children.length) {
      if (this.isSkip(children[i])) {
        i++;
      } else {
        return i;
      }
    }
    return -1;
  }

  private skipBackward(children: T[] | undefined, i: number) {
    if (!children) return -1;
    while (i >= 0) {
      if (this.isSkip(children[i])) {
        i--;
      } else {
        break;
      }
    }
    return i;
  }

  private goToRightSibling() {
    const i = this._indexPath[this._indexPath.length - 1];
    const j = this.skipForward(this.getParentItem()?.children, i + 1);
    if (j === -1) return false;
    this._indexPath[this._indexPath.length - 1] = j;
    return true;
  }

  private goToLeftSibling() {
    const i = this._indexPath[this._indexPath.length - 1];
    const j = this.skipBackward(this.getParentItem()?.children, i - 1);
    if (j === -1) return false;
    this._indexPath[this._indexPath.length - 1] = j;
    return true;
  }

  next() {
    if (this.goToChild()) return true;
    if (this.goToRightSibling()) return true;

    const indexPath = this._indexPath.slice();
    while (this.goToParent()) {
      if (this.goToRightSibling()) return true;
    }
    this._indexPath = indexPath;
    return false;
  }

  previous() {
    if (this.goToLeftSibling()) {
      this.goToRightMostDescendant();
      return true;
    }

    if (this.goToParent()) return true;
    return false;
  }

  first() {
    this._indexPath = [];
    this.goToChild();
  }

  last() {
    this._indexPath = [];
    this.goToRightMostDescendant();
  }

  forward(fn: (item: T, indexPath: number[]) => "sibling" | "child" | "stop") {
    while (true) {
      const item = this.current;
      switch (fn(item, this._indexPath)) {
        case "sibling":
          this.goToRightSibling();
          break;
        case "child":
          this.goToChild();
          break;
        case "stop":
          return item;
      }
    }
  }

  get current() {
    return this.getItem()!;
  }

  get indexPath() {
    return this._indexPath;
  }
}
