import {test,expect} from "@playwright/test";
test("independent sessions share task changes without navigation",async({page,browser})=>{
  const other=await browser.newContext();
  try {
    const peer=await other.newPage();
    await Promise.all([page.goto("http://127.0.0.1:18882/"),peer.goto("http://127.0.0.1:18882/")]);
    for(const p of [page,peer]){
      await expect(p.locator("html")).toHaveAttribute("data-live-ready","true");
      await p.evaluate(()=>{window.__sentinel=42;});
    }
    const title="Shared task "+Date.now();
    await page.getByLabel("New task").fill(title);
    await page.getByRole("button",{name:"Add",exact:true}).click();
    const row=p=>p.locator("li").filter({hasText:title});
    await expect(row(page)).toContainText("Open",{timeout:10000});
    await expect(row(peer)).toContainText("Open",{timeout:10000});
    await peer.getByLabel("New task").fill("Unsubmitted draft");
    await row(peer).getByRole("button",{name:"Toggle"}).click();
    await expect(row(page)).toContainText("Done",{timeout:10000});
    await expect(row(peer)).toContainText("Done",{timeout:10000});
    await expect(peer.getByLabel("New task")).toHaveValue("Unsubmitted draft");
    await row(page).getByRole("button",{name:"Delete"}).click();
    await expect(row(page)).toHaveCount(0,{timeout:10000});
    await expect(row(peer)).toHaveCount(0,{timeout:10000});
    for(const p of [page,peer])expect(await p.evaluate(()=>window.__sentinel)).toBe(42);
  } finally {await other.close();}
});
