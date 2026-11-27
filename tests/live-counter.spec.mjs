import {test, expect} from "@playwright/test";
test("counter updates without navigation and isolates browser sessions", async ({page,browser})=>{
  await page.goto("http://127.0.0.1:18881/");
  await expect(page.locator("html")).toHaveAttribute("data-live-ready","true");
  await expect(page.locator("#count")).toHaveText("0");
  await page.evaluate(()=>{window.__loomSentinel=42});
  await page.getByRole("button",{name:"Increment"}).click();
  await expect(page.locator("#count")).toHaveText("1");
  await expect.poll(()=>page.evaluate(()=>window.__loomSentinel)).toBe(42);
  const other=await browser.newContext();
  try {
    const p=await other.newPage();
    await p.goto("http://127.0.0.1:18881/");
    await expect(p.locator("html")).toHaveAttribute("data-live-ready","true");
    await expect(p.locator("#count")).toHaveText("0");
    await p.getByRole("button",{name:"Decrement"}).click();
    await expect(p.locator("#count")).toHaveText("-1");
    await expect(page.locator("#count")).toHaveText("1");
  } finally {await other.close();}
  await page.getByRole("button",{name:"Decrement"}).click();
  await expect(page.locator("#count")).toHaveText("0");
  await expect(page.locator("#error")).toHaveText("");
});

test("live update preserves focused input, selection and node identity",async ({page})=>{
 await page.goto("http://127.0.0.1:18881/");
 await expect(page.locator("html")).toHaveAttribute("data-live-ready","true");
 const draft=page.locator("#draft");
 await draft.fill("unfinished draft");
 await draft.evaluate(n=>{n.focus();n.setSelectionRange(2,7);window.__draft=n;});
 await page.getByRole("button",{name:"Increment"}).evaluate(n=>n.click());
 await expect(page.locator("#count")).toHaveText("1");
 await expect(draft).toHaveValue("unfinished draft");
 await expect(draft).toBeFocused();
 expect(await draft.evaluate(n=>[n===window.__draft,n.selectionStart,n.selectionEnd])).toEqual([true,2,7]);
});

test("lost event response recovers without replaying mutation",async ({page})=>{
  await page.goto("http://127.0.0.1:18881/");
  await expect(page.locator("html")).toHaveAttribute("data-live-ready","true");
  await page.route("**/live",async route=>{
    const response=await route.fetch();
    expect(response.status()).toBe(200);
    await route.abort();
  });
  await page.getByRole("button",{name:"Increment"}).click();
  await expect(page.locator("#error")).not.toHaveText("");
  await expect(page.locator("#count")).toHaveText("0");
  await page.unroute("**/live");
  await page.getByRole("button",{name:"Refresh state"}).click();
  await expect(page.locator("#count")).toHaveText("1");
  await expect(page.locator("#error")).toHaveText("");
  await page.getByRole("button",{name:"Increment"}).click();
  await expect(page.locator("#count")).toHaveText("2");
});

test("automatic recovery reads snapshots but never replays an event",async ({page})=>{
 await page.goto("http://127.0.0.1:18881/?auto=1");
 await expect(page.locator("html")).toHaveAttribute("data-live-ready","true");
 let events=0, snapshots=0;
 await page.route("**/live",async route=>{
   events++;
   const response=await route.fetch();
   expect(response.status()).toBe(200);
   await route.abort();
 });
 await page.route("**/live/snapshot",async route=>{
   snapshots++;
   if(snapshots===1) await route.abort();
   else await route.continue();
 });
 await page.getByRole("button",{name:"Increment"}).click();
 await expect(page.locator("#error")).not.toHaveText("");
 await page.getByRole("button",{name:"Increment"}).click();
 await expect(page.locator("#count")).toHaveText("1");
 await expect(page.locator("#error")).toHaveText("");
 expect(events).toBe(1);
 expect(snapshots).toBe(2);
});
