import {defineConfig} from "@playwright/test";
export default defineConfig({
  testDir: ".", testMatch:"live-counter.spec.mjs", workers:1,
  use:{browserName:"chromium",headless:true},
  webServer:{command:"racket examples/live-counter/app.rkt",cwd:"..",url:"http://127.0.0.1:18881/",env:{LOOM_LIVE_PORT:"18881"},reuseExistingServer:false,timeout:60000}
});
