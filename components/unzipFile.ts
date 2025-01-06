import Worker from "./unzipFile.worker.ts?worker";

export async function unzipFile(
  dataUrl: string,
): Promise<{ fileName: string; content: string }> {
  const worker = new Worker();
  worker.postMessage({ dataUrl });

  return new Promise((resolve, reject) => {
    worker.onmessage = (event) => {
      resolve(event.data);
    };

    worker.onerror = (event) => {
      console.error(event);
      reject(event.error.toString());
    };
  });
}
