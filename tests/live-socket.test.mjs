import {test} from "node:test";
import assert from "node:assert/strict";
import {connectLiveSocket} from "../loom/assets/live-socket.mjs";

class FakeSocket {
  static OPEN=1;
  static instances=[];
  constructor(url){this.url=String(url);this.readyState=0;this.sent=[];FakeSocket.instances.push(this);}
  open(){this.readyState=1;this.onopen?.();}
  send(raw){this.sent.push(JSON.parse(raw));}
  reply(result){this.onmessage?.({data:JSON.stringify(result)});}
  close(){this.readyState=3;}
  fail(){this.readyState=3;this.onclose?.();}
}
globalThis.location=new URL("https://example.test/app");
globalThis.WebSocket=FakeSocket;
const opts={endpoint:"/live",id:"a".repeat(64),csrf:"b".repeat(64),timeout:100};
async function bind(client){
  const promise=client.reconnect();
  const ws=FakeSocket.instances.at(-1);
  ws.open();await Promise.resolve();
  assert.equal(ws.sent[0].type,"bind");
  ws.reply({status:"ok",version:0});
  await promise;return ws;
}
test("rejects foreign origins, insecure schemes and malformed credentials",()=>{
  for(const endpoint of ["wss://other.test/live","ws://example.test/live","wss://user@example.test/live","/live#fragment"])
    assert.throws(()=>connectLiveSocket({...opts,endpoint}));
  assert.throws(()=>connectLiveSocket({...opts,id:123}));
});
test("serializes requests and never replays uncertain events on reconnect",async()=>{
  const client=connectLiveSocket(opts);
  try{
    const ws=await bind(client);
    assert.equal(ws.url,"wss://example.test/live");
    const event=client.dispatch(0,"inc");
    await assert.rejects(client.snapshot(),/busy/);
    ws.fail();await assert.rejects(event,/closed/);
    const next=await bind(client);
    assert.deepEqual(next.sent.map(x=>x.type),["bind"]);
    const snapshot=client.snapshot();
    next.reply({status:"ok",version:1});
    assert.equal((await snapshot).version,1);
  }finally{client.dispose();}
});
test("snapshot timeout disconnects and permits recovery",async()=>{
  let disconnects=0;
  const client=connectLiveSocket({...opts,onDisconnect:()=>disconnects++});
  try{
    const ws=await bind(client);
    await assert.rejects(client.snapshot(),/timeout/);
    assert.equal(ws.readyState,3);
    assert.equal(disconnects,1);
    await bind(client);
    client.disconnect();
    assert.equal(disconnects,1);
  }finally{client.dispose();}
});
test("idle disconnect notifies exactly once; disposal rejects pending request",async()=>{
  let disconnects=0;
  const client=connectLiveSocket({...opts,onDisconnect:()=>disconnects++});
  const ws=await bind(client);
  ws.fail();ws.fail();assert.equal(disconnects,1);
  await bind(client);
  const pending=client.snapshot();
  client.dispose();await assert.rejects(pending,/Disposed/);
  assert.equal(disconnects,1);
  await assert.rejects(client.reconnect());
});
