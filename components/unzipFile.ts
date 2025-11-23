import JSZip from "jszip";
import { diff } from "jsondiffpatch";

export async function unzipFilesAndCreateCustomEvent(files: FileList) {
  const file = files?.[0];
  if (!file) {
    return new CustomEvent("error", {
      detail: "Open failed: no file selected",
    });
  }

  if (file.name.endsWith(".zip") && file.size > 1024 * 1024 * 100) {
    return new CustomEvent("error", {
      detail: "Open failed: zip file is too large (> 100 MB)",
    });
  }

  if (file.name.endsWith(".zip")) {
    return await toJsonFile(await unzipFiles(file));
  } else {
    return await toJsonFile(file);
  }
}

// FIXME: the redux state be json parsed more than once
export function analysis(json: any) {
  try {
    const visitors: Map<
      string,
      { id: string; name: string; chatIds: Set<string>; siteId?: number }
    > = new Map();
    for (const entry of json.log.entries) {
      if (entry.request.url.startsWith("/redux/state")) {
        const state = getState(entry);
        for (const visitor of Object.values(state.visitor.visitors) as any[]) {
          const existingVisitor = visitors.get(visitor.id);
          if (existingVisitor) {
            if (visitor.chatId) existingVisitor.chatIds.add(visitor.chatId);
            existingVisitor.siteId = visitor.siteId;
            existingVisitor.name = visitor.latestName;
          } else {
            visitors.set(visitor.id, {
              id: visitor.id,
              name: visitor.latestName,
              chatIds: new Set([visitor.chatId].filter(Boolean)),
              siteId: visitor.siteId,
            });
          }
        }
      }
    }
    json.log.comment = JSON.stringify({
      visitors: Array.from(visitors.values()).sort((a, b) =>
        a.name.localeCompare(b.name),
      ),
    });
    // console.log(json.log.comment);
    let prevStateEntry;
    for (const entry of json.log.entries) {
      if (entry.request.url === "/redux/state") {
        if (prevStateEntry) {
          const prevState = getState(prevStateEntry);
          const state = getState(entry);
          const delta = diff(prevState, state);
          const relatedVisitorIds = getRelatedVisitorIds(
            JSON.stringify(delta),
            visitors,
          );
          const changedPaths: string[] = [];
          getJsonPaths(delta, changedPaths);
          // console.log("changedPaths", changedPaths);
          if (relatedVisitorIds.length > 0 || changedPaths.length > 0) {
            entry.comment = JSON.stringify({ relatedVisitorIds, changedPaths });
            // console.log("related visitor ids", relatedVisitorIds);
          }
        }

        prevStateEntry = entry;
      } else if (entry.request.url.startsWith("/redux/")) {
        const action = entry.request.text ?? entry.request.postData?.text;
        const relatedVisitorIds = getRelatedVisitorIds(action, visitors);
        if (relatedVisitorIds.length > 0) {
          entry.comment = JSON.stringify({ relatedVisitorIds });
          // console.log("related visitor ids2", relatedVisitorIds);
        }
      }
    }
    return json;
  } catch (e: any) {
    console.warn(`analysis failed: ${e}`);
    return json;
  }
}

function getState(entry: any) {
  return JSON.parse(entry.response.content.text);
}

function getRelatedVisitorIds(
  action: string,
  visitors: Map<string, { id: string; chatIds: Set<string> }>,
) {
  const relatedVisitorIds = [];
  for (const visitor of visitors.values()) {
    if (action.includes(visitor.id)) {
      relatedVisitorIds.push(visitor.id);
    } else if (
      Array.from(visitor.chatIds).some((chatId) => action.includes(chatId))
    ) {
      relatedVisitorIds.push(visitor.id);
    }
  }
  return relatedVisitorIds;
}

async function toJsonFile(file: File) {
  try {
    const text = await file.text();
    return new CustomEvent("change", {
      detail: {
        name: file.name,
        text,
        json: analysis(JSON.parse(text)),
      },
    });
  } catch (e) {
    return new CustomEvent("error", {
      detail: "Open failed: invalid JSON file",
    });
  }
}

export async function unzipFiles(file: File) {
  const jszip = new JSZip();
  const zip = await jszip.loadAsync(file);

  const files = Object.values(zip.files).filter((file) => !file.dir);
  for (const file of files) {
    if (file.name.endsWith(".har")) {
      return toFile(file);
    }
  }

  for (const file of files) {
    if (file.name.endsWith(".json")) {
      return toFile(file);
    }
  }

  return toFile(files[0]);
}

async function toFile(file: JSZip.JSZipObject) {
  const content = await file.async("uint8array");
  return new File([new Uint8Array(content)], file.name);
}

function getJsonPaths(json: any, result: string[], p: string[] = []) {
  if (Array.isArray(json)) {
    // this is leaf
    result.push(p.join("."));
  } else if (typeof json === "object") {
    if (json._t === "a") {
      // array diff
      result.push(p.join("."));
      return;
    }

    for (const key of Object.keys(json)) {
      p.push(key);
      getJsonPaths(json[key], result, p);
      p.pop();
    }
  } else {
    // this should not happen
    result.push(p.join("."));
  }
}
