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
// Reuse compatible nodes in place. Explicit keys identify stable siblings.
// Validate the complete incoming tree before touching the mounted DOM.
function key(node) {
  return node.nodeType === 1 ? node.getAttribute("data-live-key") : null;
}
function compatible(old, next) {
  return old.nodeType === next.nodeType &&
    (old.nodeType === 3 || (old.nodeName === next.nodeName && key(old) === key(next) &&
     (old.nodeName !== "INPUT" || old.type === next.type)));
}
function checkKeys(node) {
  const seen = new Set();
  for (const child of node.childNodes) {
    const k = key(child);
    if (k !== null && seen.has(k)) throw new Error("duplicate live key");
    if (k !== null) seen.add(k);
    checkKeys(child);
  }
}
function patch(old, next) {
  if (old.nodeType === 3) {
    if (old.nodeValue !== next.nodeValue) old.nodeValue = next.nodeValue;
    return;
  }
  const isInput = old.nodeName === "INPUT" || old.nodeName === "TEXTAREA";
  const priorDefault = old.defaultValue;
  const priorChecked = old.defaultChecked;
  const focused = old === document.activeElement;
  for (const name of old.getAttributeNames())
    if (!next.hasAttribute(name)) old.removeAttribute(name);
  for (const name of next.getAttributeNames())
    if (old.getAttribute(name) !== next.getAttribute(name)) old.setAttribute(name, next.getAttribute(name));
  patchChildren(old, next);
  // Unchanged server defaults preserve local editing; changed defaults
  // explicitly reset the control, except for file inputs.
  if (isInput && old.type !== "file" && priorDefault !== next.defaultValue)
    old.value = next.defaultValue;
  if (old.nodeName === "INPUT" && priorChecked !== next.defaultChecked)
    old.checked = next.defaultChecked;
  // Reused focused controls normally retain focus and selection natively.
  if (focused && document.activeElement !== old && old.isConnected) old.focus({preventScroll:true});
}
function patchChildren(parent, next) {
  const incoming = Array.from(next.childNodes);
  const remaining = new Set(parent.childNodes);
  const keyed = new Map(Array.from(remaining).filter(n=>key(n)!==null).map(n=>[key(n),n]));
  let cursor = parent.firstChild;
  for (const fresh of incoming) {
    const k = key(fresh);
    const candidate = k !== null ? keyed.get(k) : cursor;
    if (candidate && remaining.has(candidate) && compatible(candidate,fresh)) {
      if (candidate !== cursor) parent.insertBefore(candidate,cursor);
      patch(candidate,fresh);
      remaining.delete(candidate);
      cursor = candidate.nextSibling;
    } else {
      parent.insertBefore(fresh,cursor);
      cursor = fresh.nextSibling;
    }
  }
  for (const node of remaining) node.remove();
}
export function updateTree(root, tree) {
  const next = buildTree(tree);
  checkKeys(next);
  // A fragment wrapper lets the same reconciliation algorithm manage the
  // rendered root while keeping the stable transport host outside it.
  const wrapper = document.createElement("div");
  wrapper.append(next);
  patchChildren(root, wrapper);
}

export function attachLive(root, {endpoint, snapshotEndpoint, id, version, csrf, onError = console.error}) {
  const url = new URL(endpoint, document.baseURI);
  if (url.origin !== location.origin || !["http:", "https:"].includes(url.protocol)) throw new Error("invalid endpoint");
  if (!/^[0-9a-f]{64}$/.test(id) || !/^[0-9a-f]{64}$/.test(csrf) || !Number.isSafeInteger(version) || version < 0)
    throw new Error("invalid live configuration");
  const snapshotURL = snapshotEndpoint ? new URL(snapshotEndpoint, document.baseURI) : null;
  if (snapshotURL && (snapshotURL.origin !== location.origin || !["http:", "https:"].includes(snapshotURL.protocol))) throw new Error("invalid snapshot endpoint");
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
      if (disposed) return false;
      updateTree(root, data.view);
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
  async function resync() {
    if (disposed || busy || !snapshotURL) return false;
    busy = true;
    root.setAttribute("aria-busy", "true");
    try {
      const response = await fetch(snapshotURL, {
        method:"POST", credentials:"same-origin", redirect:"error", cache:"no-store",
        headers:{"Content-Type":"application/json","X-Loom-CSRF":csrf},
        body:JSON.stringify({id}), signal:controller.signal
      });
      if (response.status !== 200) throw new Error("snapshot HTTP " + response.status);
      const data = await response.json();
      if (data.status !== "ok" || !Number.isSafeInteger(data.version) || data.version < version)
        throw new Error("invalid snapshot");
      if (disposed) return false;
      updateTree(root,data.view);
      version = data.version;
      return true;
    } catch(error) {
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
  return {dispatch, resync, dispose() {
    disposed = true; controller.abort(); root.removeEventListener("click", click);
    root.removeAttribute("aria-busy");
  }};
}
