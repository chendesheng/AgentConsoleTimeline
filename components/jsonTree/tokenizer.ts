import { html, HTMLTemplateResult } from "lit";

function getClass(
  type: "key" | "value" | ":" | "," | "[" | "]" | "{" | "}" | "ellipsis",
  value: any,
) {
  if (type === "key") return "value key";
  if (type === "value") {
    if (value === null) return "value null";
    if (value === undefined) return "value undefined";
    if (typeof value === "string") return "value string";
    if (typeof value === "number") return "value number";
    if (typeof value === "boolean") return "value boolean";
    return "value";
  }
  if (type === ":") return "";
  if (type === ",") return "";
  if (type === "[") return "";
  if (type === "]") return "";
  if (type === "{") return "";
  if (type === "}") return "";
  if (type === "ellipsis") return "";
  return "";
}

function tokenizeJson(
  json: any,
  callback: (
    type: "key" | "value" | ":" | "," | "[" | "]" | "{" | "}" | "ellipsis",
    text: any,
  ) => "stop" | undefined,
) {
  if (json === undefined) {
    return callback("value", json);
  } else if (typeof json === "string") {
    return callback("value", JSON.stringify(json));
  } else if (typeof json === "boolean") {
    return callback("value", json);
  } else if (typeof json === "number") {
    return callback("value", json);
  } else if (json === null) {
    return callback("value", null);
  } else if (Array.isArray(json)) {
    callback("[", "[");
    let i = 0;
    for (; i < json.length; i++) {
      let next = tokenizeJson(json[i], callback);
      if (i < json.length - 1) {
        next = callback(",", ", ");
      }
      if (next === "stop") break;
    }
    if (i < json.length - 1) {
      callback("ellipsis", "\u2026");
    }
    callback("]", "]");
  } else if (typeof json === "object") {
    callback("{", "{");
    const entries = Object.entries(json);
    let i = 0;
    for (; i < entries.length; i++) {
      const [key, value] = entries[i]!;
      let next = callback("key", key);
      next = callback(":", ": ");
      if (next === "stop") break;
      next = tokenizeJson(value, callback);
      if (i < entries.length - 1) {
        next = callback(",", ", ");
      }
      if (next === "stop") break;
    }
    if (i < entries.length - 1) {
      callback("ellipsis", "\u2026");
    }
    callback("}", "}");
  }
}

export const jsonSummary = (json: any): HTMLTemplateResult[] => {
  let length = 0;
  let spans: HTMLTemplateResult[] = [];

  tokenizeJson(json, (type, val) => {
    const text =
      val === null ? "null" : val === undefined ? "undefined" : val.toString();
    length += text.length;

    spans.push(html`<span class="${getClass(type, val)}">${text}</span>`);

    if (length > 300) {
      return "stop";
    }
    return undefined;
  });

  return spans;
};
