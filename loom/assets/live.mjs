// Loom live browser runtime: no dependencies, no HTML string insertion.
const tags = new Set("main header footer nav section article aside div span p h1 h2 h3 h4 h5 h6 ul ol li dl dt dd a img button label input textarea select option table caption thead tbody tr th td strong em small code pre blockquote br hr figure figcaption".split(" "));
const attrs = new Set("id class title lang dir role name value type href src alt width height placeholder for checked disabled selected required autocomplete colspan rowspan scope tabindex".split(" "));
const voids = new Set(["img","input","br","hr"]);
function safeURL(value) {
  if (/[\x00-\x20\x7f\\]/.test(value) || value.startsWith("//")) return false;
  const url = new URL(value, document.baseURI);
  return ["http:", "https:"].includes(url.protocol);
}
export function buildTree(tree, depth = 0, budget = {left: 5000}) {
  if (--budget.left < 0 || depth > 64) throw new Error("render tree limit");
  if (typeof tree === "string") return document.createTextNode(tree);
  if (!tree || !tags.has(tree.tag) || !tree.attrs || Array.isArray(tree.attrs) ||
      typeof tree.attrs !== "object" || !Array.isArray(tree.children)) throw new Error("invalid tree");
  if (voids.has(tree.tag) && tree.children.length) throw new Error("invalid void element");
  const node = document.createElement(tree.tag);
  for (const [name, value] of Object.entries(tree.attrs)) {
    if (typeof value !== "string" || !(attrs.has(name) || /^(aria|data)-[a-z][a-z0-9-]*$/.test(name)))
      throw new Error("invalid attribute");
    if ((name === "href" || name === "src") && !safeURL(value)) throw new Error("unsafe URL");
    node.setAttribute(name, value);
  }
  for (const child of tree.children) node.append(buildTree(child, depth + 1, budget));
  return node;
}
export function attachLive(root, {endpoint, id, version, csrf, onError = console.error}) {
  const url = new URL(endpoint, document.baseURI);
  if (url.origin !== location.origin || !["http:", "https:"].includes(url.protocol)) throw new Error("invalid endpoint");
  if (!/^[0-9a-f]{64}$/.test(id) || !/^[0-9a-f]{64}$/.test(csrf) || !Number.isSafeInteger(version) || version < 0)
    throw new Error("invalid live configuration");
  let busy = false, disposed = false;
  const controller = new AbortController();
  async function dispatch(event, payload = null) {
    if (disposed || busy) return false;
    if (!/^[a-z][a-z0-9_-]{0,63}$/.test(event)) throw new Error("invalid event");
    busy = true;
    root.setAttribute("aria-busy", "true");
    try {
      const response = await fetch(url, {
        method: "POST", credentials: "same-origin", redirect: "error", cache: "no-store",
        headers: {"Content-Type": "application/json", "X-Loom-CSRF": csrf},
        body: JSON.stringify({id, version, event, payload}), signal: controller.signal
      });
      if (![200,409].includes(response.status)) throw new Error("live HTTP " + response.status);
      const data = await response.json();
      if (!Number.isSafeInteger(data.version) || data.version < version ||
          data.status !== (response.status === 200 ? "ok" : "stale")) throw new Error("invalid response");
      const node = buildTree(data.view);
      if (disposed) return false;
      root.replaceChildren(node);
      version = data.version;
      return response.status === 200;
    } catch (error) {
      if (!disposed) onError(error);
      return false;
    } finally {
      busy = false;
      if (!disposed) root.removeAttribute("aria-busy");
    }
  }
  function click(e) {
    const button = e.target instanceof Element && e.target.closest("button[data-live-event]");
    if (!button || !root.contains(button)) return;
    e.preventDefault();
    dispatch(button.dataset.liveEvent, button.dataset.livePayload ?? null).catch(onError);
  }
  root.addEventListener("click", click);
  return {dispatch, dispose() {
    disposed = true; controller.abort(); root.removeEventListener("click", click);
    root.removeAttribute("aria-busy");
  }};
}
