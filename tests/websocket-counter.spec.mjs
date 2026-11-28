import {test, expect} from "@playwright/test";
const base = "http://127.0.0.1:18884";
test("real socket bind, events, stale version and snapshot", async ({page}) => {
  await page.goto(base);
  const result = await page.evaluate(async () => {
    const session = JSON.parse(document.body.innerText);
    const ws = new WebSocket("ws://127.0.0.1:18885/live");
    try {
      await new Promise((resolve,reject) => {
        ws.onopen = resolve; ws.onerror = reject;
      });
      const send = message => new Promise((resolve,reject) => {
        const timer = setTimeout(() => reject(new Error("message timeout")),5000);
        ws.onmessage = e => {clearTimeout(timer); resolve(JSON.parse(e.data));};
        ws.onclose = () => {clearTimeout(timer); reject(new Error("unexpected close"));};
        ws.send(JSON.stringify(message));
      });
      const bind = await send({type:"bind",...session});
      const event = {type:"event",version:0,event:"inc",payload:null};
      return [bind,await send(event),await send(event),await send({type:"snapshot"})];
    } finally { ws.close(); }
  });
  expect(result.map(x=>[x.status,x.version])).toEqual([["ok",0],["ok",1],["stale",1],["ok",1]]);
});
test("rejects cross-session binding", async ({browser}) => {
  const a = await browser.newContext(), b = await browser.newContext();
  try {
    const pa = await a.newPage(), pb = await b.newPage();
    await pa.goto(base); await pb.goto(base);
    const id = JSON.parse(await pa.locator("body").innerText()).id;
    const error = await pb.evaluate(async id => {
      const own = JSON.parse(document.body.innerText);
      const ws = new WebSocket("ws://127.0.0.1:18885/live");
      return await new Promise((resolve,reject) => {
        const timer = setTimeout(()=>{ws.close();reject(new Error("timeout"));},5000);
        ws.onopen = ()=>ws.send(JSON.stringify({type:"bind",id,csrf:own.csrf}));
        ws.onmessage = e => {clearTimeout(timer);resolve(JSON.parse(e.data).error);ws.close();};
        ws.onerror = () => {clearTimeout(timer);reject(new Error("socket error"));};
      });
    },id);
    expect(error).toBe("instance-not-found");
  } finally {await a.close();await b.close();}
});

test("rejects unexpected Origin even with a valid session cookie", async ({page}) => {
  await page.goto(base);
  // Cookies are scoped to the host, not the port. The alternate HTTP
  // listener therefore presents the same cookie but a different Origin.
  const foreign = "http://127.0.0.1:18881/origin-probe";
  // Isolate the server Origin policy from the other application's CSP.
  // Only the document is synthetic; the WebSocket handshake is real.
  const before = await page.context().cookies(base);
  expect(before.some(c => c.name === "loom-dev-session")).toBe(true);
  await page.route(foreign, route => route.fulfill({
    contentType: "text/html", body: "<!doctype html><title>Origin probe</title>"
  }));
  await page.goto(foreign);
  expect(await page.evaluate(() => location.origin)).toBe("http://127.0.0.1:18881");
  expect(await page.context().cookies(base)).toEqual(before);
  const code = await page.evaluate(() => new Promise((resolve,reject) => {
    const ws = new WebSocket("ws://127.0.0.1:18885/live");
    const timer = setTimeout(()=>{ws.close();reject(new Error("origin rejection timeout"));},5000);
    ws.onclose = e => {clearTimeout(timer);resolve(e.code);};
  }));
  expect(code).toBe(1008);
});
test("rejects a socket without an HTTP session", async ({page}) => {
  await page.goto(base);
  await page.context().clearCookies();
  const code = await page.evaluate(() => new Promise((resolve,reject) => {
    const ws = new WebSocket("ws://127.0.0.1:18885/live");
    const timer = setTimeout(()=>{ws.close();reject(new Error("session rejection timeout"));},5000);
    ws.onclose = e => {clearTimeout(timer);resolve(e.code);};
  }));
  expect(code).toBe(1008);
});

test("DOM runtime binds, renders events, recovers and preserves state", async ({page}) => {
  await page.goto(base);
  await page.evaluate(async () => {
    const session=JSON.parse(document.body.innerText);
    const root=document.createElement("div");
    root.id="socket-root";
    document.body.replaceChildren(root);
    // The fixture exposes a separate loopback socket port. A test-only
    // constructor maps the logical same-origin endpoint to that listener.
    const Native=window.WebSocket;
    class FixtureSocket extends Native {
      constructor(url){super("ws://127.0.0.1:18885"+new URL(url).pathname);window.lastSocket=this;}
    }
    window.WebSocket=FixtureSocket;
    const {attachLiveSocket}=await import("/assets/live-socket-dom.mjs");
    window.recoveries=0;
    window.heartbeatRequests=0;
    const send=Native.prototype.send;
    FixtureSocket.prototype.send=function(raw){
      if(JSON.parse(raw).type==="snapshot")window.heartbeatRequests++;
      return send.call(this,raw);
    };
    window.socketClient=attachLiveSocket(root,{endpoint:"/live",...session,
      heartbeat:1000,onRecovered:()=>window.recoveries++,onError:()=>{}});
    if(!await window.socketClient.connected)throw new Error("initial bind failed");
  });
  await expect(page.locator("#socket-root p")).toHaveText("0");
  expect(await page.evaluate(()=>window.socketClient.dispatch("inc"))).toBe(true);
  await expect(page.locator("#socket-root p")).toHaveText("1");
  await expect.poll(()=>page.evaluate(()=>window.heartbeatRequests)).toBeGreaterThan(0);
  await expect(page.locator("#socket-root")).not.toHaveAttribute("aria-busy","true");
  await page.evaluate(()=>window.lastSocket.close());
  await expect.poll(()=>page.evaluate(()=>window.recoveries)).toBe(2);
  await expect(page.locator("#socket-root p")).toHaveText("1");
  expect(await page.evaluate(()=>window.socketClient.dispatch("inc"))).toBe(true);
  await expect(page.locator("#socket-root p")).toHaveText("2");
  await page.evaluate(()=>window.socketClient.dispose());
  expect(await page.evaluate(()=>window.socketClient.dispatch("inc"))).toBe(false);
});
