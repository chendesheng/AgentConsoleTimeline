import { defineConfig } from "vite";
import elmPlugin from "vite-plugin-elm";

export default defineConfig({
  plugins: [elmPlugin({ debug: false })],
  build: {
    rollupOptions: {
      input: ["./index.html", "./snapshot.html"],
    },
  },
});
