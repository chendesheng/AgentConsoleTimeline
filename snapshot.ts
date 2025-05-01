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
  const iframe = createIframe(src);
  iframe.onload = () => {
    if (iframe.title) currentWindow.setTitle(iframe.title);

    mainWindow.emit(
      "proxy-message",
      JSON.stringify({ type: "waitForReduxState" }),
    );
  };
  document.body.appendChild(iframe);

  currentWindow.once("close", () => {
    mainWindow.emit("snapshot-window-closed", src);
  });

  currentWindow.listen("proxy-message", (event) => {
    if (event.payload && iframe) {
      iframe.contentWindow?.postMessage(
        JSON.parse(event.payload as string),
        "*",
      );
    }
  });
}

main();
