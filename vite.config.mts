import { defineConfig } from "vite";
import elmPlugin from "vite-plugin-elm";

export default defineConfig({
  plugins: [elmPlugin({ debug: false })],
  server: {
    proxy: {
      "/session": {
        target: "ws://localhost:5174/",
        changeOrigin: true,
        ws: true
      },
      "/connect": {
        target: "ws://localhost:5174/",
        changeOrigin: true,
        ws: true
      }
    }
  }
});
