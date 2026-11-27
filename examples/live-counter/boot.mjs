import {attachLive} from "/live.mjs";
const root = document.querySelector("#live");
attachLive(root, {
  endpoint: "/live", id: root.dataset.id, csrf: root.dataset.csrf,
  version: Number(root.dataset.version),
  onError: () => { document.querySelector("#error").textContent = "Update failed. Reload the page."; }
});
document.documentElement.dataset.liveReady = "true";
