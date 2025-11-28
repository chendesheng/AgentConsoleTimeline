import { assertEquals } from "jsr:@std/assert";
import { TreeItem, TreeIterator } from "./iterator.ts";
import * as path from "https://deno.land/std@0.224.0/path/mod.ts";

Deno.test("single node tree", () => {
  const tree: TreeItem = {
    value: 0,
  };
  const iter = new TreeIterator(tree);
  assertEquals(iter.current.value, 0);
  iter.next();
  assertEquals(iter.current.value, 0);
  iter.previous();
  assertEquals(iter.current.value, 0);
});

Deno.test("last", () => {
  const tree: TreeItem = {
    children: [
      {
        value: 0,
      },
      {
        value: 1,
      },
    ],
  };
  const iter = new TreeIterator(tree);
  iter.last();
  assertEquals(iter.current.value, 1);
});

Deno.test("first", () => {
  const tree: TreeItem = {
    value: 0,
    children: [{ value: 1 }, { value: 2 }],
  };
  const iter = new TreeIterator(tree);
  assertEquals(iter.current.value, 0);
  iter.next();
  assertEquals(iter.current.value, 1);
  iter.first();
  assertEquals(iter.current.value, 0);
});

Deno.test("first must not be skippped", () => {
  const tree: TreeItem = {
    value: 0,
    children: [{ value: 1 }, { value: 2 }],
  };
  const iter = new TreeIterator(tree, (item) => item.value === 0);
  iter.first();
  assertEquals(iter.current.value, 0);
});

Deno.test("last with skip", () => {
  const tree: TreeItem = {
    children: [{ value: 0 }, { value: 1 }],
  };
  const iter = new TreeIterator(tree, (item) => item.value === 1);
  iter.last();
  assertEquals(iter.current.value, 0);
});

Deno.test("forward", () => {
  const tree: TreeItem = {
    value: -1,
    children: [
      {
        value: 0,
        children: [
          {
            value: 1,
            children: [{ value: 2 }, { value: 3 }],
          },
        ],
      },
      {
        value: 4,
        children: [
          {
            value: 5,
            children: [{ value: 6 }, { value: 7 }],
          },
        ],
      },
    ],
  };
  const iter = new TreeIterator(tree);
  assertEquals(
    iter.forward((item) => {
      if (item.value === 0) return "sibling";
      if (item.value === -1 || item.value === 4) return "child";
      return "stop";
    }),
    true,
  );
  assertEquals(iter.current.value, 5);
});
Deno.test("forward to not exist item", () => {
  const tree: TreeItem = {
    value: -1,
    children: [
      {
        value: 0,
        children: [
          {
            value: 1,
            children: [{ value: 2 }, { value: 3 }],
          },
        ],
      },
      {
        value: 4,
        children: [
          {
            value: 5,
            children: [{ value: 6 }, { value: 7 }],
          },
        ],
      },
    ],
  };
  const iter = new TreeIterator(tree);
  assertEquals(
    iter.forward(() => "child"),
    false,
  );
  assertEquals(iter.current.value, 2);
});

Deno.test("iterate small tree", () => {
  const tree: TreeItem = {
    value: 0,
    children: [
      {
        value: 1,
        children: [
          {
            value: 2,
            children: [{ value: 3 }, { value: 4 }],
          },
        ],
      },
    ],
  };
  const iter = new TreeIterator(tree);
  assertEquals(iter.current.value, 0);
  assertEquals(iter.next(), true);
  assertEquals(iter.current.value, 1);
  assertEquals(iter.next(), true);
  assertEquals(iter.current.value, 2);
  assertEquals(iter.next(), true);
  assertEquals(iter.current.value, 3);
  assertEquals(iter.next(), true);
  assertEquals(iter.current.value, 4);
  assertEquals(iter.next(), false);
  assertEquals(iter.current.value, 4);
  assertEquals(iter.previous(), true);
  assertEquals(iter.current.value, 3);
  assertEquals(iter.previous(), true);
  assertEquals(iter.current.value, 2);
  assertEquals(iter.previous(), true);
  assertEquals(iter.current.value, 1);
  assertEquals(iter.previous(), true);
  assertEquals(iter.current.value, 0);
  assertEquals(iter.previous(), false);
  assertEquals(iter.current.value, 0);
});

Deno.test("iterate large tree", async () => {
  const _p = (file: string) => path.join(import.meta.dirname!, file);
  const json = await Deno.readTextFile(_p("../../deno.lock"));
  const tree = jsonToTree(JSON.parse(json), []);
  const iter = new TreeIterator(tree);

  for (const item of walkTree(tree)) {
    assertEquals(item.path.join("."), iter.current.path.join("."));
    iter.next();
  }
  for (const item of walkTreeReverse(tree)) {
    assertEquals(item.path.join("."), iter.current.path.join("."));
    iter.previous();
  }
});

function* walkTree(tree: TreeItem): Generator<TreeItem, void, void> {
  yield tree;
  if (tree.children) {
    for (const child of tree.children) {
      yield* walkTree(child);
    }
  }
}

function* walkTreeReverse(tree: TreeItem): Generator<TreeItem, void, void> {
  if (tree.children) {
    for (let i = tree.children.length - 1; i >= 0; i--) {
      const child = tree.children[i];
      yield* walkTreeReverse(child);
    }
  }
  yield tree;
}

type JsonType =
  | { [key: string]: JsonType }
  | JsonType[]
  | number
  | string
  | boolean
  | null;

const jsonToTree = (json: JsonType, path: string[]): TreeItem => {
  if (json != null && Array.isArray(json)) {
    return {
      path,
      children: json.map((value: JsonType, index: number) =>
        jsonToTree(value, [...path, index.toString()]),
      ),
    };
  } else if (json != null && typeof json === "object") {
    return {
      path,
      children: Object.entries(json).map(([key, value]) =>
        jsonToTree(value, [...path, key]),
      ),
    };
  } else {
    return { path, value: json };
  }
};
Deno.test("iterate with skip leaf", () => {
  const tree: TreeItem = {
    value: 0,
    children: [
      {
        value: 1,
        children: [
          {
            value: 2,
            children: [{ value: 3 }, { value: 4 }],
          },
        ],
      },
    ],
  };
  const iter = new TreeIterator(tree, (item) => item.value === 3);
  assertEquals(iter.current.value, 0);
  iter.next();
  assertEquals(iter.current.value, 1);
  iter.next();
  assertEquals(iter.current.value, 2);
  iter.next();
  assertEquals(iter.current.value, 4);
  iter.next();
  assertEquals(iter.current.value, 4);
  iter.previous();
  assertEquals(iter.current.value, 2);
  iter.previous();
  assertEquals(iter.current.value, 1);
  iter.previous();
  assertEquals(iter.current.value, 0);
  iter.previous();
});

Deno.test("iterate with skip", () => {
  const tree: TreeItem = {
    value: 0,
    children: [
      {
        value: 1,
        children: [
          {
            value: 2,
            children: [{ value: 3 }, { value: 4 }],
          },
        ],
      },
      {
        value: 5,
        children: [
          {
            value: 6,
          },
        ],
      },
    ],
  };
  const iter = new TreeIterator(tree, (item) => item.value === 2);
  assertEquals(iter.current.value, 0);
  assertEquals(iter.next(), true);
  assertEquals(iter.current.value, 1);
  assertEquals(iter.next(), true);
  assertEquals(iter.current.value, 5);
  assertEquals(iter.next(), true);
  assertEquals(iter.current.value, 6);
  assertEquals(iter.next(), false);

  assertEquals(iter.current.value, 6);
  assertEquals(iter.previous(), true);
  assertEquals(iter.current.value, 5);
  assertEquals(iter.previous(), true);
  assertEquals(iter.current.value, 1);
  assertEquals(iter.previous(), true);
  assertEquals(iter.current.value, 0);
  assertEquals(iter.previous(), false);
});

Deno.test("iterate with skip children", () => {
  const tree: TreeItem = {
    value: 0,
    children: [
      {
        value: 1,
        children: [
          {
            value: 2,
            children: [{ value: 3 }, { value: 4 }],
          },
        ],
      },
      {
        value: 5,
        children: [
          {
            value: 6,
          },
        ],
      },
    ],
  };
  const iter = new TreeIterator(tree, undefined, (item) => item.value === 2);
  assertEquals(iter.current.value, 0);
  assertEquals(iter.next(), true);
  assertEquals(iter.current.value, 1);
  assertEquals(iter.next(), true);
  assertEquals(iter.current.value, 2);
  assertEquals(iter.next(), true);
  assertEquals(iter.current.value, 5);
  assertEquals(iter.next(), true);
  assertEquals(iter.current.value, 6);
  assertEquals(iter.next(), false);

  assertEquals(iter.current.value, 6);
  assertEquals(iter.previous(), true);
  assertEquals(iter.current.value, 5);
  assertEquals(iter.previous(), true);
  assertEquals(iter.current.value, 2);
  assertEquals(iter.previous(), true);
  assertEquals(iter.current.value, 1);
  assertEquals(iter.previous(), true);
  assertEquals(iter.current.value, 0);
  assertEquals(iter.previous(), false);
});
