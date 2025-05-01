import {
  getCurrentWebviewWindow,
  WebviewWindow,
} from "@tauri-apps/api/webviewWindow";

export type PopoutWindow = {
  postMessage: (message: any) => void;
  close: () => void;
  onClose: (fn: () => void) => void;
  onLoad: (fn: () => void) => void;
  reload: (url: string) => void;
};

declare global {
  interface Window {
    isTauri?: boolean;
  }
}

if (window.isTauri) {
  const currentWindow = getCurrentWebviewWindow();
  currentWindow.listen("proxy-message", (event) => {
    if (event.payload) {
      window.postMessage(JSON.parse(event.payload as string), "*");
    }
  });
}

function openTauriWindow(url: string, name: string): PopoutWindow {
  const win = new WebviewWindow(name, {
    url: `snapshot.html?src=${encodeURIComponent(url)}`,
    x: 0,
    y: 0,
    width: 800,
    height: 600,
    title: "Agent Console Snapshot",
  });

  return {
    postMessage: (message: any) => {
      win.emit("proxy-message", JSON.stringify(message));
    },
    close: () => {
      win.close();
      deletePopoutWindow(url);
    },
    onClose: (fn: () => void) => {
      win.once("tauri://destroyed", fn);
    },
    onLoad: (fn: () => void) => {},
    reload: (url: string) => {
      // todo
    },
  };
}

function openBrowserWindow(url: string, name: string): PopoutWindow {
  const win = window.open(url, name)!;
  return {
    postMessage: (message: any) => {
      win.postMessage(message, "*");
    },
    close: () => {
      win.close();
      deletePopoutWindow(url);
    },
    onClose: (fn: () => void) => {
      win.onbeforeunload = fn;
    },
    onLoad: (fn: () => void) => {
      win.onload = fn;
    },
    reload: (url: string) => {
      // todo
    },
  };
}

const popoutWindows: Record<string, PopoutWindow> = {};

export function openWindow(url: string, name: string) {
  let win: PopoutWindow;
  if (window.isTauri) {
    win = openTauriWindow(url, name);
  } else {
    win = openBrowserWindow(url, name);
  }

  popoutWindows[new URL(url).pathname] = win;
  return win;
}

export function getPopoutWindow(url: string): PopoutWindow | undefined {
  return popoutWindows[new URL(url).pathname];
}

function deletePopoutWindow(url: string) {
  delete popoutWindows[new URL(url).pathname];
}
