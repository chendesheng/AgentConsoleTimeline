import {
  extractArchiveFile,
  getArchiveErrorMessage,
  isArchiveFileName,
} from "./js7z";
import JsonFileWorker from "./jsonFileWorker?worker";

type JsonFilePayload = {
  name: string;
  text: string;
  json: any;
};

type ParseResponse =
  | { ok: true; file: JsonFilePayload }
  | { ok: false; error: string };

export async function unzipFilesAndCreateCustomEvent(files: FileList) {
  const file = files?.[0];
  if (!file) {
    return new CustomEvent("error", {
      detail: "Open failed: no file selected",
    });
  }

  if (isArchiveFileName(file.name) && file.size > 1024 * 1024 * 100) {
    return new CustomEvent("error", {
      detail: "Open failed: archive file is too large (> 100 MB)",
    });
  }

  if (isArchiveFileName(file.name)) {
    try {
      return await toJsonFile(await unzipFiles(file));
    } catch (error) {
      return new CustomEvent("error", {
        detail: `Open failed: ${getArchiveErrorMessage(error)}`,
      });
    }
  } else {
    return await toJsonFile(file);
  }
}

export async function parseJsonFile(
  name: string,
  text: string,
): Promise<JsonFilePayload> {
  const worker = new JsonFileWorker();

  return await new Promise((resolve, reject) => {
    worker.onmessage = (event: MessageEvent<ParseResponse>) => {
      worker.terminate();

      if (event.data.ok) {
        resolve(event.data.file);
      } else {
        reject(new Error(event.data.error));
      }
    };

    worker.onerror = (event) => {
      worker.terminate();
      reject(
        new Error(event.message || "Open failed: could not parse JSON file"),
      );
    };

    worker.postMessage({ name, text });
  });
}

async function toJsonFile(file: File) {
  try {
    const text = await file.text();
    return new CustomEvent("change", {
      detail: await parseJsonFile(file.name, text),
    });
  } catch (e) {
    return new CustomEvent("error", {
      detail:
        e instanceof Error ? e.message : "Open failed: invalid JSON file",
    });
  }
}

export async function unzipFiles(file: File) {
  return await extractArchiveFile(file);
}
