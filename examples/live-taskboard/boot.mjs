import {attachLive} from "/live.mjs";
import {subscribeLive} from "/live-notify.mjs";
const root=document.querySelector("#live");
const title=document.querySelector("#title");
const error=document.querySelector("#error");
const id=root.dataset.id, csrf=root.dataset.csrf;
const client=attachLive(root,{
  endpoint:"/live",snapshotEndpoint:"/snapshot",id,csrf,
  version:Number(root.dataset.version),autoRecover:true,
  onError:()=>{error.textContent="Update failed; synchronizing state.";},
  onRecovered:()=>{error.textContent="";}
});
const subscription=subscribeLive({
  endpoint:"/notify",id,csrf,refresh:()=>client.resync(),
  onError:()=>{}
});
async function add(){
  const value=title.value;
  if(!value.trim()||value.trim().length>200)return;
  if(await client.dispatch("add",value)){
    if(title.value===value) title.value="";
    error.textContent="";
  }
}
document.querySelector("#add").addEventListener("click",add);
title.addEventListener("keydown",e=>{if(e.key==="Enter"){e.preventDefault();add();}});
window.addEventListener("pagehide",()=>{subscription.dispose();client.dispose();},{once:true});
document.documentElement.dataset.liveReady="true";
