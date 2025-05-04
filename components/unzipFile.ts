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
    return new CustomEvent("change", { detail: await unzipFiles(file) });
  } else {
    return new CustomEvent("change", { detail: file });
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

  return toFile(files[0]);
}

async function toFile(file: JSZip.JSZipObject) {
  const content = await file.async("uint8array");
  return new File([content], file.name);
}
