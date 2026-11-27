// Notifications are hints: refresh authoritative state even after a timeout.
export function subscribeLive({endpoint,id,csrf,refresh,onError=console.error}) {
  const url=new URL(endpoint,document.baseURI);
  if(url.origin!==location.origin || !["http:","https:"].includes(url.protocol)) throw new Error("invalid endpoint");
  if(!/^[0-9a-f]{64}$/.test(id)||!/^[0-9a-f]{64}$/.test(csrf)||typeof refresh!=="function") throw new Error("invalid subscription");
  const controller=new AbortController();
  let disposed=false, stopped=false, timer=null, failures=0;
  function schedule(ms) { if(!disposed&&!stopped) timer=setTimeout(poll,ms); }
  async function poll() {
    timer=null;
    if(disposed||stopped) return;
    try {
      const response=await fetch(url,{method:"POST",credentials:"same-origin",redirect:"error",cache:"no-store",
        headers:{"Content-Type":"application/json","X-Loom-CSRF":csrf},body:JSON.stringify({id}),signal:controller.signal});
      if(disposed) return;
      if([400,403,404,405].includes(response.status)) { stopped=true; throw new Error("subscription rejected"); }
      if(response.status!==200) throw new Error("notification HTTP "+response.status);
      const data=await response.json();
      if(!["changed","timeout"].includes(data.status)) throw new Error("invalid notification");
      if(disposed) return;
      if(!(await refresh())) throw new Error("snapshot not synchronized");
      failures=0;
      schedule(100);
    } catch(error) {
      if(disposed) return;
      failures=Math.min(failures+1,6);
      schedule(Math.min(1000*2**(failures-1),30000));
      onError(error);
    }
  }
  schedule(0);
  return {dispose(){disposed=true;clearTimeout(timer);controller.abort();}};
}
