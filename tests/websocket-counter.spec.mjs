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
  await page.goto("http://127.0.0.1:18881/");
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
