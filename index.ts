/// <reference path="./index.d.ts" />
/// <reference types="vite/types/importMeta.d.ts" />

import "./components/jsonTree";
import "./components/agentConsoleSnapshot";
import "./components/agentConsoleSnapshotPlayer";
import "./components/resizeDivider";
import "./components/monacoEditor";
import "./components/openFileButton";
import "./components/dropZipFile";
import "./components/exportButton";
import { analysis, unzipFiles } from "./components/unzipFile";
import "./components/hexEditor";
import {
  saveRecentFile,
  getFileContent,
  getRecentFiles,
  clearRecentFile,
  deleteRecentFile,
  getFileName,
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
      remoteSession: new URLSearchParams(window.location.search).get(
        "remoteSession",
      ),
    },
  });

  app.ports.saveRecentFile.subscribe(({ fileName, fileContent }) => {
    saveRecentFile(fileName, fileContent);
  });

  app.ports.getFileContent.subscribe(async (key) => {
    const content = await getFileContent(key);
    const name = await getFileName(key);
    app.ports.gotFileContent.send({
      name,
      text: content,
      json: analysis(JSON.parse(content)),
    });
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
    const remoteHar = new RemoteHar(app.ports, url);

    if (url.startsWith("wss://") || url.startsWith("ws://")) {
      if (socket) {
        socket.close();
      }

      socket = new WebSocket(url);
      socket.onopen = () => {
        // console.log('onopen', event);
        socket.send(
          JSON.stringify({
            type: "connect",
          }),
        );
      };

      socket.onmessage = (event: MessageEvent) => {
        // console.log('got message', event.data);

        const data = JSON.parse(event.data);
        if (data.type === "harLog") {
          remoteHar.harLog(data.payload);
        } else if (data.type === "harEntry") {
          remoteHar.harEntry(data.payload);
        }
      };

      socket.onclose = () => {
        // console.log(`remote source ${url} closed`);
        remoteHar.close();
      };
    } else if (window.opener) {
      window.opener.postMessage({ type: "connect" }, "*");

      const checkClosedTimer = setInterval(() => {
        if (window.opener?.closed) {
          remoteHar.close();
          clearInterval(checkClosedTimer);
        }
      }, 100);

      window.onmessage = (event: MessageEvent) => {
        if (event.data.type === "harLog") {
          remoteHar.harLog(event.data.payload);
        } else if (event.data.type === "harEntry") {
          remoteHar.harEntry(event.data.payload);
        }
      };
    }
  });

  window.onmessage = async (event: MessageEvent) => {
    if (event.data.type === "open") {
      if (event.data.filename && event.data.content) {
        let content: string;
        if (event.data.content instanceof ArrayBuffer) {
          const file = await unzipFiles(
            new File([event.data.content], event.data.filename),
          );
          content = await file.text();
        } else {
          content = event.data.content;
        }

        app.ports.gotFileContent.send({
          name: event.data.filename,
          text: content,
          json: analysis(JSON.parse(content)),
        });
      }
    }
  };

  if (window.opener) {
    window.opener.postMessage({ type: "ready" }, "*");
  }
}

main();

class RemoteHar {
  private harEntryQueue: any[] = [];

  constructor(private readonly ports: any, private readonly url: string = "") {}

  harLog(log: any) {
    this.ports.gotRemoteHarLog.send(JSON.stringify({ log }));
  }

  harEntry(entry: any) {
    this.harEntryQueue.push(entry);
    setTimeout(() => {
      this.ports.gotRemoteHarEntry.send(JSON.stringify(this.harEntryQueue));
      this.harEntryQueue.splice(0, this.harEntryQueue.length);
    }, 50);
  }

  close() {
    this.ports.gotRemoteClose.send(this.url);
  }
}
