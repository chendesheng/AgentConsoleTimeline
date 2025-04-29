/// <reference path="./index.d.ts" />
/// <reference types="vite/types/importMeta.d.ts" />

import "./components/jsonTree";
import "./components/agentConsoleSnapshot";
import "./components/agentConsoleSnapshotPlayer";
import "./components/resizeDivider";
import "./components/monacoEditor";
import "./components/openFileButton";
import "./components/dropZipFile";
import {
  saveRecentFile,
  getFileContent,
  getRecentFiles,
  clearRecentFile,
  deleteRecentFile,
} from "./components/recentFiles";
import { Elm } from "./src/Main.elm";

declare global {
  var popoutWindow: Window | null;
}

async function main() {
  const recentFiles = await getRecentFiles();

  const app = Elm.Main.init({
    node: document.getElementById("app")!,
    flags: {
      recentFiles,
      remoteAddress:
        import.meta.env.REMOTE_ADDRESS ?? "agentconsoledebugger.deno.dev",
    },
  });

  app.ports.saveRecentFile.subscribe(({ fileName, fileContent }) => {
    saveRecentFile(fileName, fileContent);
  });

  app.ports.getFileContent.subscribe(async (fileName) => {
    const content = await getFileContent(fileName);
    app.ports.gotFileContent.send(content);
  });

  app.ports.clearRecentFiles.subscribe(async () => {
    await clearRecentFile();
  });

  app.ports.deleteRecentFile.subscribe(async (key) => {
    await deleteRecentFile(key);
  });

  app.ports.closePopoutWindow.subscribe(() => {
    globalThis.popoutWindow?.close();
    globalThis.popoutWindow = null;
  });

  // app.ports.getRecentFiles.subscribe(async () => {
  //   const recentFiles = await getRecentFiles();
  //   app.ports.gotRecentFiles.send(recentFiles);
  // });

  window.onbeforeunload = () => {
    if (globalThis.popoutWindow) {
      globalThis.popoutWindow.close();
    }
  };

  let socket: WebSocket;
  app.ports.connectRemoteSource.subscribe((url) => {
    if (socket) {
      socket.close();
    }

    socket = new WebSocket(url);
    socket.onopen = (event) => {
      // console.log('onopen', event);
      socket.send(
        JSON.stringify({
          type: "connect",
        }),
      );
    };

    const harEntryQueue: any[] = [];
    socket.onmessage = (event) => {
      // console.log('got message', event.data);

      const data = JSON.parse(event.data);
      if (data.type === "harLog") {
        app.ports.gotRemoteHarLog.send(JSON.stringify({ log: data.payload }));
      } else if (data.type === "harEntry") {
        harEntryQueue.push(data.payload);
        setTimeout(() => {
          app.ports.gotRemoteHarEntry.send(JSON.stringify(harEntryQueue));
          harEntryQueue.splice(0, harEntryQueue.length);
        }, 50);
      }
    };

    socket.onclose = (event) => {
      // console.log(`remote source ${url} closed`);
      app.ports.gotRemoteClose.send(url);
    };
  });
}

main();
