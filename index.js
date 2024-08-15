import "./components/jsonTree";
import "./components/agentConsoleSnapshot";
import "./components/agentConsoleSnapshotPlayer";
import "./components/resizeDivier";
import "./components/monacoEditor";
import { Elm } from "./src/Main.elm";

const app = Elm.Main.init();
app.ports.scrollIntoView.subscribe((id) => {
  document.getElementById(id)?.scrollIntoView({ block: "nearest" });
});
