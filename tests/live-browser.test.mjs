import test from "node:test";
import assert from "node:assert/strict";
import {buildTree, attachLive, updateTree} from "../loom/assets/live.mjs";
class Node {
  constructor(tag, text) { this.tag = tag; this.text = text; this.attrs = {}; this.children = []; this.parent = null; }
  get nodeType() { return this.tag === null ? 3 : 1; }
  get nodeName() { return this.tag?.toUpperCase() ?? "#text"; }
  get nodeValue() { return this.text; }
  set nodeValue(v) { this.text = v; }
  get childNodes() { return this.children; }
  get firstChild() { return this.children[0] ?? null; }
  get nextSibling() { return this.parent?.children[this.parent.children.indexOf(this)+1] ?? null; }
  getAttribute(k) { return this.attrs[k] ?? null; }
  getAttributeNames() { return Object.keys(this.attrs); }
  hasAttribute(k) { return Object.hasOwn(this.attrs,k); }
  remove() { if (this.parent) { this.parent.children.splice(this.parent.children.indexOf(this),1); this.parent=null; } }
  insertBefore(n, cursor) { if (n===cursor) return; n.remove(); this.children.splice(cursor===null?this.children.length:this.children.indexOf(cursor),0,n); n.parent=this; }
  setAttribute(k,v) { this.attrs[k]=v; }
  removeAttribute(k) { delete this.attrs[k]; }
  append(n) { this.insertBefore(n,null); }
  replaceChildren(n) { this.children=[n]; }
  addEventListener() {}
  removeEventListener() {}
}
globalThis.document = {baseURI:"https://example.test/", createElement:t=>new Node(t), createTextNode:t=>new Node(null,t)};
globalThis.location = new URL(document.baseURI);
const tree = {tag:"div",attrs:{},children:["<script>alert(1)</script>"]};
test("safe text nodes and rejected executable content", ()=>{
  assert.equal(buildTree(tree).children[0].text,tree.children[0]);
  for (const bad of [{tag:"script",attrs:{},children:[]},{tag:"img",attrs:{onerror:"x"},children:[]},{tag:"a",attrs:{href:"javascript:alert(1)"},children:[]}])
    assert.throws(()=>buildTree(bad));
});
test("version synchronization and stale response",async ()=>{
  const root = new Node("div");
  let calls=0;
  globalThis.fetch=async (url,opts)=>{
    const message=JSON.parse(opts.body);
    assert.equal(message.version,calls===0?0:1);
    assert.equal(opts.headers["X-Loom-CSRF"],"b".repeat(64));
    calls++;
    return {status:calls===1?200:409,json:async()=>({version:calls,status:calls===1?"ok":"stale",view:tree})};
  };
  const client=attachLive(root,{endpoint:"/live",id:"a".repeat(64),csrf:"b".repeat(64),version:0,onError:e=>{throw e;}});
  assert.equal(await client.dispatch("inc"),true);
  assert.equal(await client.dispatch("inc"),false);
  assert.equal(root.children[0].children[0].text,tree.children[0]);
  client.dispose();
  assert.equal(await client.dispatch("inc"),false);
});
test("cross origin endpoint rejected",()=>{
  assert.throws(()=>attachLive(new Node("div"),{endpoint:"https://other.test/live",id:"a".repeat(64),csrf:"b".repeat(64),version:0}));
});

test("keyed reorder keeps node identity and rejects duplicate keys before mutation",()=>{
 const root=new Node("div");
 const item=k=>({tag:"p",attrs:{"data-live-key":k},children:[k]});
 const view=children=>({tag:"div",attrs:{},children});
 updateTree(root,view([item("a"),item("b")]));
 const [a,b]=root.children[0].children;
 updateTree(root,view([item("b"),item("a")]));
 assert.equal(root.children[0].children[0],b);
 assert.equal(root.children[0].children[1],a);
 assert.throws(()=>updateTree(root,view([item("a"),item("a")])));
 assert.equal(root.children[0].children[0],b);
});
