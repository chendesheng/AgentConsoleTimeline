import JSZip from "jszip";

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

export function analysis(json: any) {
  try {
    const visitors: Map<string, { id: string; name: string }> = new Map();
    for (const entry of json.log.entries) {
      if (entry.request.url.startsWith("/redux/state")) {
        const state = JSON.parse(entry.response.content.text);
        for (const visitor of Object.values(state.visitor.visitors) as any[]) {
          visitors.set(visitor.id, {
            id: visitor.id,
            name: visitor.latestName,
          });
        }
      }
    }
    json.log.comment = JSON.stringify({
      visitors: Array.from(visitors.values()).sort((a, b) =>
        a.name.localeCompare(b.name),
      ),
    });
    console.log(json.log.comment);
    return json;
  } catch (e: any) {
    console.warn(`analysis failed: ${e}`);
    return json;
  }
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

async function unzipFiles(file: File) {
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
  return new File([content], file.name);
}
