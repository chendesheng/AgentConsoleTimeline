import { defineConfig } from "vite";
import elmPlugin from "vite-plugin-elm";
import monacoEditorPlugin from "vite-plugin-monaco-editor-esm";

export default defineConfig({
  plugins: [elmPlugin({ debug: false }), monacoEditorPlugin({})],
  build: {
    rollupOptions: {
      input: ["./index.html", "./snapshot.html"],
    },
  },
});
