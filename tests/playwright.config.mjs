import {defineConfig} from "@playwright/test";
export default defineConfig({
  testDir: ".", testMatch:["live-counter.spec.mjs","live-taskboard.spec.mjs","websocket-counter.spec.mjs"], workers:1,
  use:{browserName:"chromium",headless:true},
  webServer:[{command:"racket examples/live-counter/app.rkt",cwd:"..",url:"http://127.0.0.1:18881/",env:{LOOM_LIVE_PORT:"18881"},reuseExistingServer:false,timeout:60000},
  {command:"racket examples/live-taskboard/app.rkt",cwd:"..",url:"http://127.0.0.1:18882/",env:{LOOM_LIVE_BOARD_PORT:"18882"},reuseExistingServer:false,timeout:60000},
  {command:"racket examples/websocket-counter/app.rkt",cwd:"..",url:"http://127.0.0.1:18884/",reuseExistingServer:false,timeout:60000}]
});
