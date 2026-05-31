import { analysis } from "./harAnalysis";

type JsonFilePayload = {
  name: string;
  text: string;
  json: any;
};

type ParseRequest = {
  name: string;
  text: string;
};

type ParseResponse =
  | { ok: true; file: JsonFilePayload }
  | { ok: false; error: string };

const ctx = globalThis as unknown as {
  onmessage: ((event: MessageEvent<ParseRequest>) => void) | null;
  postMessage: (message: ParseResponse) => void;
};

ctx.onmessage = (event: MessageEvent<ParseRequest>) => {
  try {
    const { name, text } = event.data;
    const response: ParseResponse = {
      ok: true,
      file: {
        name,
        text,
        json: analysis(JSON.parse(text)),
      },
    };
    ctx.postMessage(response);
  } catch (_error) {
    const response: ParseResponse = {
      ok: false,
      error: "Open failed: invalid JSON file",
    };
    ctx.postMessage(response);
  }
};
