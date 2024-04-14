/**
 * @name Xcode
 */
import { tags as t } from "@lezer/highlight";
import { createTheme } from "@uiw/codemirror-themes";

export default createTheme({
  theme: "dark",
  settings: {
    gutterBackground: "var(--background-color)",
    gutterBorder: "var(--text-color-quaternary)",
    gutterForeground: "hsl(0, 0%, 57%)",
    fontFamily: "inherit",
    background: "var(--background-color)",
    foreground: "#CECFD0",
    caret: "hsl(0, 0%, var(--foreground-lightness))",
    selection: "#727377",
    selectionMatch: "#727377",
    lineHighlight: "#ffffff0f",
  },
  styles: [
    {
      tag: [t.comment, t.quote],
      color: "var(--syntax-highlight-comment-color)",
    },
    {
      tag: [t.keyword],
      color: "var(--syntax-highlight-symbol-color)",
      fontWeight: "bold",
    },
    { tag: [t.string, t.meta], color: "var(--syntax-highlight-string-color)" },
    { tag: [t.typeName], color: "#DABAFF" },
    { tag: [t.number], color: "var(--syntax-highlight-number-color)" },
    { tag: [t.bool], color: "var(--syntax-highlight-boolean-color)" },
    { tag: [t.definition(t.variableName)], color: "#6BDFFF" },
    { tag: [t.regexp, t.link], color: "var(--syntax-highlight-regexp-color)" },
  ],
});
