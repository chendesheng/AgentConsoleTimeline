import {
  getAllWebviewWindows,
  getCurrentWebviewWindow,
} from "@tauri-apps/api/webviewWindow";

function createIframe(src: string) {
  const iframe = document.createElement("iframe");
  iframe.src = src;
  iframe.allow = "clipboard-read; clipboard-write";
  return iframe;
}

async function main() {
  const currentWindow = getCurrentWebviewWindow();

  const wins = await getAllWebviewWindows();
  const mainWindow = wins.find((win) => win.label === "main")!;

  const src = new URL(location.href).searchParams.get("src")!;
  currentWindow.setTitle(src);
  const iframe = createIframe(src);

  // forward message from iframe to main window
  globalThis.addEventListener("message", (event) => {
    // console.log("message", event);
    mainWindow.emit("proxy-message", JSON.stringify(event.data));
  });

  document.body.appendChild(iframe);

  currentWindow.once("close", () => {
    mainWindow.emit("snapshot-window-closed", src);
  });

  // forward message from main window to iframe
  currentWindow.listen("proxy-message", (event) => {
    if (event.payload && iframe) {
      iframe.contentWindow?.postMessage(
        JSON.parse(event.payload as string),
        "*",
      );
    }
  });

  currentWindow.listen("reload", (event) => {
    const src = event.payload as string;
    if (iframe.contentWindow) {
      currentWindow.setTitle(src);
      iframe.contentWindow.location.href = src;
    }
  });
}

main();
