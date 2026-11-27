// One request in flight; never replay an uncertain mutation.
export function connectLiveSocket({endpoint,id,csrf,timeout=5000,onDisconnect=()=>{}}) {
  const url = new URL(endpoint,location.href);
  if (url.protocol==="http:") url.protocol="ws:";
  if (url.protocol==="https:") url.protocol="wss:";
  if (!["ws:","wss:"].includes(url.protocol) ||
      url.host !== location.host ||
      url.protocol !== (location.protocol==="https:"?"wss:":"ws:") ||
      url.username || url.password || url.hash)
    throw new TypeError("Expected same-origin WebSocket endpoint");
  if (typeof id!=="string" || typeof csrf!=="string" || !/^[0-9a-f]{64}$/.test(id) || !/^[0-9a-f]{64}$/.test(csrf) ||
      !Number.isInteger(timeout) || timeout<100 || timeout>60000)
    throw new TypeError("Invalid live socket configuration");
  let socket, pending, opening, disposed=false;
  function invalidate(ws,error,notify=true) {
    if (socket!==ws) return;
    socket=undefined;
    if (pending) {const p=pending;pending=undefined;clearTimeout(p.timer);p.reject(error);}
    if (opening) {const p=opening;opening=undefined;clearTimeout(p.timer);p.reject(error);}
    ws.close();
    if(notify&&!disposed) onDisconnect(error);
  }
  function request(message) {
    const ws=socket;
    if (disposed || !ws || ws.readyState!==WebSocket.OPEN || pending)
      return Promise.reject(new Error("Live socket unavailable or busy"));
    return new Promise((resolve,reject)=>{
      const timer=setTimeout(()=>invalidate(ws,new Error("Live response timeout")),timeout);
      pending={resolve,reject,timer};
      try {ws.send(JSON.stringify(message));}
      catch(error){invalidate(ws,error);}
    });
  }
  async function reconnect() {
    if (disposed || socket) throw new Error("Dispose or disconnect existing socket first");
    const ws=new WebSocket(url);
    socket=ws;
    ws.onclose=()=>invalidate(ws,new Error("Live socket closed"));
    ws.onerror=()=>invalidate(ws,new Error("Live socket failed"));
    ws.onmessage=e=>{
      if (socket!==ws) return;
      if (!pending) {invalidate(ws,new Error("Unexpected message"));return;}
      let result;
      try {
        result=JSON.parse(e.data);
        if (!result || !["ok","stale","unknown-event","error"].includes(result.status))
          throw new Error("Invalid live response");
      } catch(error){invalidate(ws,error);return;}
      const p=pending;pending=undefined;clearTimeout(p.timer);p.resolve(result);
    };
    await new Promise((resolve,reject)=>{
      opening={resolve,reject,timer:setTimeout(()=>invalidate(ws,new Error("Connect timeout")),timeout)};
      ws.onopen=()=>{if(socket!==ws || !opening)return;clearTimeout(opening.timer);opening=undefined;resolve();};
    });
    const result=await request({type:"bind",id,csrf});
    if(result.status!=="ok"){invalidate(ws,new Error("Bind rejected"));throw new Error("Bind rejected");}
    return result;
  }
  return {
    reconnect,
    snapshot:()=>request({type:"snapshot"}),
    dispatch:(version,event,payload=null)=>request({type:"event",version,event,payload}),
    disconnect:()=>{if(socket)invalidate(socket,new Error("Disconnected"),false);},
    dispose:()=>{disposed=true;if(socket)invalidate(socket,new Error("Disposed"),false);}
  };
}
