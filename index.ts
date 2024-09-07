/// <reference path="./index.d.ts" />

import "./components/jsonTree";
import "./components/agentConsoleSnapshot";
import "./components/agentConsoleSnapshotPlayer";
import "./components/resizeDivier";
import "./components/monacoEditor";
import {
  saveRecentFile,
  getFileContent,
  getRecentFiles,
  clearRecentFile,
} from "./components/recentFiles";
import { Elm } from "./src/Main.elm";

async function main() {
  const recentFiles = await getRecentFiles();

  const app = Elm.Main.init({
    node: document.getElementById("app")!,
    flags: { recentFiles },
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

  // app.ports.getRecentFiles.subscribe(async () => {
  //   const recentFiles = await getRecentFiles();
  //   app.ports.gotRecentFiles.send(recentFiles);
  // });
}

main();
