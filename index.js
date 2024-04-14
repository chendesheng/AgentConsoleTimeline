import "@alenaksu/json-viewer";
import "./components/agentConsoleSnapshot";
import "./components/codeEditor";
import { Elm } from "./src/Main.elm";

Elm.Main.init({ node: document.body });
