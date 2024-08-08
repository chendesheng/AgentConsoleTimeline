import "@alenaksu/json-viewer";
import "./components/agentConsoleSnapshot";
import "./components/resizeDivier";
import "./components/monacoEditor";
import { Elm } from "./src/Main.elm";

Elm.Main.init({ node: document.getElementById("app") });
