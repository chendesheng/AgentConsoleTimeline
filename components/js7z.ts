import type { MainModule } from "js7z-tools";
import js7zSingleThreadScriptUrl from "../assets/js7z-st/js7z.js?url";
import js7zSingleThreadWasmUrl from "../assets/js7z-st/js7z.wasm?url";
import js7zModuleUrl from "js7z-tools/js7z.mjs?url";
import js7zWasmUrl from "js7z-tools/js7z.wasm?url";

type JS7zFile = {
  name: string;
  content: Uint8Array;
};

type JS7zRuntime = MainModule & {
  onAbort: (reason: unknown) => void;
  onExit: (exitCode: number) => void;
};

type JS7zFactory = (options?: unknown) => Promise<MainModule>;

class JS7zArchiveError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "JS7zArchiveError";
  }
}

declare global {
  interface Window {
    JS7z?: JS7zFactory;
  }
}

let singleThreadLoadPromise: Promise<JS7zFactory> | undefined;

export function isArchiveFileName(fileName: string) {
  const lowerName = fileName.toLowerCase();
  return lowerName.endsWith(".zip") || lowerName.endsWith(".7z");
}

export async function extractArchiveFile(file: File) {
  const archiveName = sanitizeArchiveMemberName(file.name) || "archive";
  const archivePath = `/in/${archiveName}`;

  const files = await runJS7z(
    async (js7z) => {
      mkdirTree(js7z, "/in");
      mkdirTree(js7z, "/out");
      mkdirTree(js7z, parentPath(archivePath));
      js7z.FS.writeFile(archivePath, new Uint8Array(await file.arrayBuffer()));
    },
    ["x", archivePath, "-o/out", "-y"],
    (js7z) => listFiles(js7z, "/out"),
  );

  const selectedFile =
    findFileByExtension(files, ".har") ??
    findFileByExtension(files, ".json") ??
    files[0];

  if (!selectedFile) {
    throw new JS7zArchiveError("archive has no files");
  }

  return new File([new Uint8Array(selectedFile.content)], selectedFile.name);
}

export async function create7zArchive(fileName: string, fileContent: string) {
  const innerName = sanitizeArchiveMemberName(fileName) || "export.har";
  const innerPath = `/in/${innerName}`;

  const archive = await runJS7z(
    (js7z) => {
      mkdirTree(js7z, "/in");
      mkdirTree(js7z, "/out");
      mkdirTree(js7z, parentPath(innerPath));
      js7z.FS.writeFile(innerPath, new TextEncoder().encode(fileContent));
      js7z.FS.chdir("/in");
    },
    ["a", "-t7z", "-mx=9", "/out/archive.7z", innerName],
    (js7z) => js7z.FS.readFile("/out/archive.7z"),
  );

  return new Blob([new Uint8Array(archive)], {
    type: "application/x-7z-compressed",
  });
}

export function getArchiveErrorMessage(error: unknown) {
  if (error instanceof Error) return error.message;
  return String(error);
}

async function runJS7z<T>(
  prepare: (js7z: MainModule) => void | Promise<void>,
  args: string[],
  collect: (js7z: MainModule) => T,
) {
  const stderr: string[] = [];
  const js7z = await createJS7z(stderr);

  await prepare(js7z);

  return await new Promise<T>((resolve, reject) => {
    const runtime = js7z as JS7zRuntime;

    runtime.onAbort = (reason: unknown) => {
      reject(new JS7zArchiveError(formatFailure("aborted", stderr, reason)));
    };
    runtime.onExit = (exitCode: number) => {
      if (exitCode === 0) {
        try {
          resolve(collect(js7z));
        } catch (error) {
          reject(error);
        }
      } else {
        reject(new JS7zArchiveError(formatFailure(`exit ${exitCode}`, stderr)));
      }
    };

    try {
      runtime.callMain(args);
    } catch (error: any) {
      if (error?.name !== "ExitStatus") {
        reject(error);
      }
    }
  });
}

async function createJS7z(stderr: string[]) {
  const useMultiThread = typeof SharedArrayBuffer === "function";
  const JS7z = useMultiThread
    ? ((await import(/* @vite-ignore */ js7zModuleUrl)) as {
        default: JS7zFactory;
      }).default
    : await loadSingleThreadJS7z();
  const wasmUrl = useMultiThread ? js7zWasmUrl : js7zSingleThreadWasmUrl;

  return await JS7z({
    locateFile: (path: string) => (path.endsWith(".wasm") ? wasmUrl : path),
    ...(useMultiThread ? { mainScriptUrlOrBlob: js7zModuleUrl } : {}),
    print: () => undefined,
    printErr: (text: string) => {
      stderr.push(text);
    },
  });
}

async function loadSingleThreadJS7z() {
  singleThreadLoadPromise ??= loadScript(js7zSingleThreadScriptUrl).then(() => {
    if (!window.JS7z) {
      throw new JS7zArchiveError("failed to load single-thread JS7z");
    }

    return window.JS7z;
  });

  return await singleThreadLoadPromise;
}

async function loadScript(src: string) {
  await new Promise<void>((resolve, reject) => {
    const script = document.createElement("script");

    script.src = src;
    script.async = true;
    script.onload = () => resolve();
    script.onerror = () => {
      reject(new JS7zArchiveError(`failed to load JS7z script: ${src}`));
    };

    document.head.append(script);
  });
}

function formatFailure(status: string, stderr: string[], reason?: unknown) {
  const detail = stderr.join("\n").trim() || (reason ? String(reason) : "");
  return detail ? `7z ${status}: ${detail}` : `7z ${status}`;
}

function findFileByExtension(files: JS7zFile[], extension: string) {
  return files.find((file) => file.name.toLowerCase().endsWith(extension));
}

function listFiles(js7z: MainModule, path: string, prefix = ""): JS7zFile[] {
  const entries = js7z.FS.readdir(path).filter(
    (entry: string) => entry !== "." && entry !== "..",
  );
  const files: JS7zFile[] = [];

  for (const entry of entries) {
    const childPath = `${path}/${entry}`;
    const childName = prefix ? `${prefix}/${entry}` : entry;
    const stat = js7z.FS.stat(childPath, false);

    if (js7z.FS.isDir(stat.mode)) {
      files.push(...listFiles(js7z, childPath, childName));
    } else {
      files.push({
        name: childName,
        content: js7z.FS.readFile(childPath),
      });
    }
  }

  return files;
}

function sanitizeArchiveMemberName(fileName: string) {
  return fileName
    .replace(/\\/g, "/")
    .split("/")
    .filter((part) => part && part !== "." && part !== "..")
    .join("/");
}

function parentPath(path: string) {
  const index = path.lastIndexOf("/");
  return index <= 0 ? "/" : path.slice(0, index);
}

function mkdirTree(js7z: MainModule, path: string) {
  if (path === "/") return;

  const parts = path.split("/").filter(Boolean);
  let current = "";
  for (const part of parts) {
    current += `/${part}`;
    try {
      js7z.FS.mkdir(current);
    } catch (_error) {
      // Existing directories are fine; later FS calls surface real path errors.
    }
  }
}
