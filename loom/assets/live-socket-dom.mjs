import {updateTree} from "./live.mjs";
import {connectLiveSocket} from "./live-socket.mjs";

// A failed or ambiguous mutation is never replayed. Only a fresh bind
// and authoritative render can re-enable dispatch.
export function attachLiveSocket(root,{endpoint,id,csrf,version=0,timeout=5000,
    onError=console.error,onRecovered=()=>{},autoRecover=true}){
  const transport=connectLiveSocket({endpoint,id,csrf,timeout});
  const delays=[250,1000,3000];
  let disposed=false,busy=false,ready=false,timer=null,attempts=0;
  function apply(data){
    if(!["ok","stale"].includes(data.status)||!Number.isSafeInteger(data.version)||data.version<version)
      throw new Error("Invalid live socket result");
    if(disposed)return false;
    updateTree(root,data.view);version=data.version;return true;
  }
  function schedule(){
    if(!autoRecover||disposed||ready||timer!==null||attempts>=delays.length)return;
    timer=setTimeout(()=>{timer=null;attempts++;void resync();},delays[attempts]);
  }
  async function run(action){
    if(disposed||busy)return false;
    busy=true;root.setAttribute("aria-busy","true");
    try{return await action();}
    catch(error){
      ready=false;transport.disconnect();
      if(!disposed)onError(error);
      return false;
    }finally{
      busy=false;if(!disposed){root.removeAttribute("aria-busy");schedule();}
    }
  }
  async function resync(){
    return run(async()=>{
      ready=false;transport.disconnect();
      const data=await transport.reconnect();
      if(!apply(data))return false;
      ready=true;attempts=0;
      if(timer!==null){clearTimeout(timer);timer=null;}
      onRecovered();return true;
    });
  }
  async function dispatch(event,payload=null){
    if(!ready||disposed||busy)return false;
    if(typeof event!=="string"||!/^[a-z][a-z0-9_-]{0,63}$/.test(event))throw new Error("Invalid event");
    return run(async()=>{
      const data=await transport.dispatch(version,event,payload);
      if(!apply(data))return false;
      return data.status==="ok";
    });
  }
  function click(e){
    const button=e.target instanceof Element&&e.target.closest("button[data-live-event]");
    if(!button||!root.contains(button))return;
    e.preventDefault();dispatch(button.dataset.liveEvent,button.dataset.livePayload??null).catch(onError);
  }
  function online(){if(!ready&&!disposed){attempts=0;if(timer!==null){clearTimeout(timer);timer=null;}schedule();}}
  root.addEventListener("click",click);
  if(autoRecover)globalThis.addEventListener("online",online);
  const connected=resync();
  return {connected,dispatch,resync,dispose(){
    disposed=true;ready=false;if(timer!==null)clearTimeout(timer);
    transport.dispose();root.removeEventListener("click",click);
    if(autoRecover)globalThis.removeEventListener("online",online);
    root.removeAttribute("aria-busy");
  }};
}
