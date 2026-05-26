import { defineConfig } from "vite";
import elmPlugin from "vite-plugin-elm";
import monacoEditorPlugin from "vite-plugin-monaco-editor-esm";
import type { Plugin } from "vite";

const crossOriginIsolationHeaders = {
  "Cross-Origin-Opener-Policy": "same-origin",
  "Cross-Origin-Embedder-Policy": "require-corp",
};

function monacoWorkerHeadersPlugin(): Plugin {
  return {
    name: "monaco-worker-headers",
    configureServer(server) {
      server.middlewares.use((req, res, next) => {
        if (req.url?.startsWith("/monacoeditorwork/")) {
          for (const [name, value] of Object.entries(
            crossOriginIsolationHeaders,
          )) {
            res.setHeader(name, value);
          }
          res.setHeader("Cross-Origin-Resource-Policy", "same-origin");
        }
        next();
      });
    },
  };
}

export default defineConfig({
  plugins: [
    elmPlugin({ debug: false }),
    monacoWorkerHeadersPlugin(),
    monacoEditorPlugin({}),
  ],
  server: {
    headers: crossOriginIsolationHeaders,
  },
  preview: {
    headers: crossOriginIsolationHeaders,
  },
  worker: {
    format: "es",
  },
  build: {
    rollupOptions: {
      input: ["./index.html", "./snapshot.html"],
    },
  },
});
