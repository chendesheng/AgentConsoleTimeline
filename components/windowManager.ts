import {
  getCurrentWebviewWindow,
  WebviewWindow,
} from "@tauri-apps/api/webviewWindow";

export type PopoutWindow = {
  postMessage: (message: any) => void;
  close: () => void;
  onClose: (fn: () => void) => void;
  reload: (url?: string) => void;
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

  currentWindow.listen("close", () => {
    for (const win of Object.values(popoutWindows)) {
      win.close();
    }
  });
} else {
  window.addEventListener("beforeunload", () => {
    for (const win of Object.values(popoutWindows)) {
      win.close();
    }
  });
}

function openTauriWindow(url: string, name: string): PopoutWindow {
  const win = new WebviewWindow(name, {
    url: `snapshot.html?src=${encodeURIComponent(url)}`,
    width: screen.availWidth * 0.8,
    height: screen.availHeight * 0.8,
    title: "Agent Console Snapshot",
  });

  return {
    postMessage: (message: any) => {
      win.emitTo(win.label, "proxy-message", JSON.stringify(message));
    },
    close: () => {
      win.close();
      deletePopoutWindow(url);
    },
    onClose: (fn: () => void) => {
      win.once("tauri://destroyed", fn);
    },
    reload: (url?: string) => {
      win.emitTo(win.label, "reload", url);
    },
  };
}

function monitorBrowserWindowClose(win: Window, fn: () => void) {
  const poll = () => {
    if (win.closed) {
      fn();
    } else {
      requestAnimationFrame(poll);
    }
  };
  poll();
}

function openBrowserWindow(url: string, name: string): PopoutWindow {
  const win = window.open(url, name)!;
  let src = url;
  return {
    postMessage: (message: any) => {
      win.postMessage(message, "*");
    },
    close: () => {
      win.close();
      deletePopoutWindow(url);
    },
    onClose: (fn: () => void) => {
      monitorBrowserWindowClose(win, fn);
    },
    reload: (url?: string) => {
      if (url) {
        src = url;
        win.location.href = url;
      } else {
        win.location.href = src;
      }
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
