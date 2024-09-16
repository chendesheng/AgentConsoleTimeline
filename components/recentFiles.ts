import * as idb from "idb";
import { md5 } from "js-md5";

async function openRecentFilesDb() {
  return idb.openDB("recent-files", 1, {
    upgrade(db) {
      db.createObjectStore("list", { keyPath: "key" });
      db.createObjectStore("content", { keyPath: "key" });
    },
  });
}

export async function getRecentFiles() {
  const db = await openRecentFilesDb();
  const list = await db.getAll("list");
  list.sort((a, b) => b.lastOpenTime - a.lastOpenTime);
  return list;
}

export async function getFileContent(key: string) {
  const db = await openRecentFilesDb();
  const { content } = await db.get("content", key);
  return content;
}

export async function saveRecentFile(fileName: string, content: string) {
  const key = md5(content);

  const db = await openRecentFilesDb();

  const tx = db.transaction(["list", "content"], "readwrite");
  const listStore = tx.objectStore("list");
  const contentStore = tx.objectStore("content");

  const exists = !!(await listStore.getKey(key));
  await listStore.put({ key, fileName, lastOpenTime: Date.now() });

  const files = await listStore.getAll();
  if (!exists) await contentStore.put({ key, content });

  if (files.length > 10) {
    files.sort((a, b) => a.lastOpenTime - b.lastOpenTime);
    for (const { key: toDelete } of files.slice(10)) {
      await listStore.delete(toDelete);
      await contentStore.delete(toDelete);
    }
  }

  await tx.done;
}

export async function clearRecentFile() {
  const db = await openRecentFilesDb();
  const tx = db.transaction(["list", "content"], "readwrite");
  const listStore = tx.objectStore("list");
  const contentStore = tx.objectStore("content");

  await listStore.clear();
  await contentStore.clear();

  await tx.done;
}

export async function deleteRecentFile(key: string) {
  const db = await openRecentFilesDb();
  const tx = db.transaction(["list", "content"], "readwrite");
  const listStore = tx.objectStore("list");
  const contentStore = tx.objectStore("content");

  await listStore.delete(key);
  await contentStore.delete(key);

  await tx.done;
}
