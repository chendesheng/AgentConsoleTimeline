import JSZip from "jszip";

self.onmessage = async (event) => {
  const { dataUrl } = event.data;
  const base64Data = dataUrl.slice(dataUrl.indexOf(",") + 1);

  const jszip = new JSZip();
  const zip = await jszip.loadAsync(base64Data, { base64: true });

  for (const fileName in zip.files) {
    const file = zip.files[fileName];
    if (!file.dir && file.name.endsWith(".har")) {
      const content = await file.async("uint8array");
      self.postMessage({
        fileName,
        content: new TextDecoder().decode(content),
      });
      return;
    }
  }

  throw new Error("No HAR file found");
};
