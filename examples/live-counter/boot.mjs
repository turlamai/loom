import {attachLive} from "/live.mjs";
const root = document.querySelector("#live");
const client = attachLive(root, {
  endpoint: "/live", snapshotEndpoint: "/live/snapshot", autoRecover: new URLSearchParams(location.search).has("auto"),
  onRecovered: () => { document.querySelector("#error").textContent = ""; }, id: root.dataset.id, csrf: root.dataset.csrf,
  version: Number(root.dataset.version),
  onError: () => { document.querySelector("#error").textContent = "Update failed. Refresh state before trying again."; }
});
document.documentElement.dataset.liveReady = "true";

document.querySelector("#resync").addEventListener("click", async () => {
  if (await client.resync()) document.querySelector("#error").textContent = "";
});
