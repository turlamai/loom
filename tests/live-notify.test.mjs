import test from "node:test";
import assert from "node:assert/strict";
import {subscribeLive} from "../loom/assets/live-notify.mjs";
globalThis.document={baseURI:"https://example.test/"};
globalThis.location=new URL(document.baseURI);
const config={endpoint:"/notify",id:"a".repeat(64),csrf:"b".repeat(64)};
test("changed and timeout both refresh state; disposal stops polling",async()=>{
  let polls=0, reads=0;
  let finish;
  const done=new Promise(resolve=>{finish=resolve;});
  globalThis.fetch=async(url,opts)=>{
    assert.equal(url.origin,location.origin);
    assert.equal(opts.headers["X-Loom-CSRF"],config.csrf);
    assert.deepEqual(JSON.parse(opts.body),{id:config.id});
    assert.equal(opts.method,"POST");
    return {status:200,json:async()=>({status:++polls===1?"changed":"timeout"})};
  };
  const sub=subscribeLive({...config,refresh:async()=>{
    if(++reads===2){sub.dispose();finish();}
    return true;
  },onError:finish});
  await Promise.race([done,new Promise((_,reject)=>{const t=setTimeout(()=>reject(new Error("poll timeout")),2000);t.unref();})]);
  await new Promise(resolve=>setTimeout(resolve,150));
  assert.equal(polls,2);assert.equal(reads,2);
});
test("authorization failure stops subscription",async()=>{
  let calls=0;
  globalThis.fetch=async()=>{calls++;return {status:403};};
  let finish;
  const done=new Promise(resolve=>{finish=resolve;});
  const sub=subscribeLive({...config,refresh:async()=>{throw new Error("unexpected refresh");},onError:finish});
  const err=await done;
  assert.match(err.message,/rejected/);
  await new Promise(resolve=>setTimeout(resolve,150));
  assert.equal(calls,1);sub.dispose();
});
test("cross-origin notification endpoint rejected",()=>{
  assert.throws(()=>subscribeLive({...config,endpoint:"https://other.test/",refresh:async()=>true}));
});
