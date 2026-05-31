import { create7zArchive, getArchiveErrorMessage } from "./js7z";

type ExportRequest = {
  fileName: string;
  fileContent: string;
};

type ExportResponse =
  | { ok: true; blob: Blob }
  | { ok: false; error: string };

const ctx = globalThis as unknown as {
  onmessage: ((event: MessageEvent<ExportRequest>) => void) | null;
  postMessage: (message: ExportResponse) => void;
};

ctx.onmessage = (event: MessageEvent<ExportRequest>) => {
  const { fileName, fileContent } = event.data;

  create7zArchive(fileName, fileContent)
    .then((blob) => {
      ctx.postMessage({ ok: true, blob });
    })
    .catch((error) => {
      ctx.postMessage({
        ok: false,
        error: `Export failed: ${getArchiveErrorMessage(error)}`,
      });
    });
};
