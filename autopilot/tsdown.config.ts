import { defineConfig } from "tsdown";

export default defineConfig({
  entry: ["src/handler.ts"],
  format: "esm",
  target: "node22",
  outDir: "dist",
  clean: true,
  dts: false,
});
