// Menus remain usable even if the 3D CDN is unavailable.
let pending;
export function ensureEngine() {
  if(window.Cesium)return Promise.resolve(window.Cesium);
  if(pending)return pending;
  pending=new Promise((resolve,reject)=> {
    const script=document.createElement('script');
    script.src=window.CESIUM_BASE_URL+'Cesium.js';script.async=true;
    const timer=setTimeout(()=>{script.remove();reject(new Error('The 3D engine timed out. Please retry.'));},30000);
    script.onload=()=>{clearTimeout(timer);resolve(window.Cesium);};
    script.onerror=()=>{clearTimeout(timer);script.remove();reject(new Error('The 3D engine could not load. Check your connection and retry.'));};
    document.head.appendChild(script);
  }).catch(error=>{pending=null;throw error;});
  return pending;
}
