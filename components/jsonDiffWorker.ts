import { diffString } from "json-diff";

function main() {
  globalThis.addEventListener("message", (e: MessageEvent) => {
    const { source, target } = e.data;
    if (!source || !target) return;

    const t = JSON.parse(target);
    const s = JSON.parse(source);

    // config.salesforce is too large
    // if (t.config.salesforce) delete t.config.salesforce;
    // if (s.config.salesforce) delete s.config.salesforce;

    // TODO: use worker to diff
    const diff = diffString(t, s, {
      color: false
    });

    globalThis.postMessage({
      type: "diffResult",
      payload: diff || "No Changes"
    });
  });
}

main();
