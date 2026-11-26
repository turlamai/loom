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
