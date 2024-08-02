import "@alenaksu/json-viewer";
import "./components/agentConsoleSnapshot";
import "./components/codeEditor";
import "./components/resizeDivier";
import "./components/jsonDiff";
import { Elm } from "./src/Main.elm";

Elm.Main.init({ node: document.getElementById("app") });
