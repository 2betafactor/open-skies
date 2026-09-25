// Personal journeys stay in this browser; no account or upload required.
export function routeInfo(a, b, cruiseKmh = 180) {
  const rad=Math.PI/180, p=a.lat*rad, q=b.lat*rad, dl=(b.lng-a.lng)*rad;
  const h=Math.sin((q-p)/2)**2+Math.cos(p)*Math.cos(q)*Math.sin(dl/2)**2;
  const km=6371*2*Math.atan2(Math.sqrt(Math.min(1,h)),Math.sqrt(Math.max(0,1-h)));
  const bearing=(Math.atan2(Math.sin(dl)*Math.cos(q),Math.cos(p)*Math.sin(q)-Math.sin(p)*Math.cos(q)*Math.cos(dl))/rad+360)%360;
  return {km,bearing,minutes:km/Math.max(1, cruiseKmh)*60};
}
// Unwrap date-line crossings and fit the recorded track without stretching it.
export function trackPoints(path) {
  const coords=[];
  for(const p of path) {
    const previous=coords.at(-1);
    const x=previous ? previous[0]+((p[0]-previous[0]+540)%360)-180 : p[0];
    coords.push([x,p[1]]);
  }
  const latitude=coords.reduce((sum,p)=>sum+p[1],0)/coords.length;
  const horizontal=Math.max(.01,Math.cos(latitude*Math.PI/180));
  const xs=coords.map(p=>p[0]*horizontal),ys=coords.map(p=>p[1]);
  const minX=Math.min(...xs),minY=Math.min(...ys),dx=Math.max(...xs)-minX,dy=Math.max(...ys)-minY;
  const scale=Math.min(280/Math.max(dx,.000001),80/Math.max(dy,.000001));
  return coords.map((p,i)=>`${150+(xs[i]-minX-dx/2)*scale},${50-(ys[i]-minY-dy/2)*scale}`).join(' ');
}
export class Journal {
  constructor() { this.key='open-skies.journal.v1';this.entries=[];try{this.refresh();}catch{} }
  refresh() { const saved=JSON.parse(localStorage.getItem(this.key)||'[]');this.entries=Array.isArray(saved)?saved.filter(e=>e&&typeof e==='object'):[]; }
  save(entry) {
    this.refresh();
    const next=[{id:crypto.randomUUID(),date:new Date().toISOString(),...entry},...this.entries].slice(0,60);
    // Never claim success when storage is full or disabled.
    localStorage.setItem(this.key,JSON.stringify(next)); this.entries=next; return next[0];
  }
  favorite(id) { this.refresh();const next=this.entries.map(e=>e.id===id?{...e,favorite:!e.favorite}:e);localStorage.setItem(this.key,JSON.stringify(next));this.entries=next; }
}
const $=id=>document.getElementById(id);
export class Journey {
  constructor(app, presets, notify, revisit) {
    this.app=app;this.presets=presets;this.notify=notify;this.revisit=revisit;this.journal=new Journal();
    if($('btn-journal'))$('btn-journal').onclick=()=>{this.render();$('journal-dialog').showModal();};
    $('journal-close').onclick=()=>$('journal-dialog').close();
    $('btn-photo').onclick=()=>this.photo();
    $('btn-minimal').onclick=()=>this.toggleMinimal();
    window.addEventListener('keydown',e=>{if(!app.flying||e.repeat||e.target?.matches('input,textarea,select,[contenteditable=true]'))return;if(e.code==='KeyH')this.toggleMinimal();if(e.code==='KeyP')this.photo();});
    $('btn-return').onclick=()=>{this.target={...this.departure};this.arrived=false;this.notify('Guidance set to your departure point.');};
    this.plan();
  }
  plan() {
    const start=this.app.destination;
    this.destination=null;
    this.start=start;
  }
  begin() {
    this.plan();this.discovered=new Set();this.arrived=false;
    this.departure={...this.start};this.target=this.destination?{...this.destination}:null;
    $('journey-nav').hidden=true;
    document.querySelector('.journey-actions').hidden=false;
  }
  update(s) {
    const f=this.app.flight,C=window.Cesium,c=C.Cartographic.fromCartesian(f.position),here={lat:C.Math.toDegrees(c.latitude),lng:C.Math.toDegrees(c.longitude)};
    this.here=here;
    const phase=f.phase;
    let line='';
    if(this.target){const r=routeInfo(here,this.target);line=`${this.target.name} · ${r.km.toFixed(1)} km · steer ${Math.round(r.bearing).toString().padStart(3,'0')}°`;if(r.km<.5&&!this.arrived&&phase==='airborne'){this.arrived=true;this.notify('Destination reached — enjoy the view.');if($('radio').checked)this.app.audio.say('Destination reached.');}}
    $('journey-nav').textContent=line;
  }
  finish(flight) {
    document.body.classList.remove('minimal-flight');$('btn-minimal').textContent='Hide HUD';$('btn-minimal').setAttribute('aria-pressed','false');$('journey-nav').hidden=true;
    if(!flight||flight.timeSec<1)return;
    try {this.journal.save({kind:'flight',name:this.departure?.name||'Flight',start:this.departure,target:this.target,world:flight.world,vehicle:flight.vehicle,timeSec:flight.timeSec,distanceKm:flight.distanceKm,topSpeedKmh:flight.topSpeedKmh,path:flight.path});}catch{this.notify('Logbook could not save. Browser storage may be full or unavailable.');}
  }
  toggleMinimal(){const on=document.body.classList.toggle('minimal-flight');$('btn-minimal').textContent=on?'Show HUD':'Hide HUD';$('btn-minimal').setAttribute('aria-pressed',String(on));}
  async photo(){
    if(!this.app.flying||this.capturing)return;this.capturing=true;$('btn-photo').disabled=true;
    const context={name:this.departure?.name||'Flight',start:{...this.departure},target:this.target?{...this.target}:null,world:this.app.world,vehicle:this.app.vehicle.id,position:this.here?{...this.here}:null,path:this.app.flight.path.map(p=>p.slice())};
    try {
      const blob=await this.app.flight.capture();if(!blob)throw Error('No image');
      const bitmap=await createImageBitmap(blob),canvas=document.createElement('canvas');canvas.width=Math.min(960,bitmap.width);canvas.height=Math.round(bitmap.height*canvas.width/bitmap.width);canvas.getContext('2d').drawImage(bitmap,0,0,canvas.width,canvas.height);bitmap.close();
      const image=canvas.toDataURL('image/jpeg',.72);
      this.journal.save({kind:'photo',image,...context});this.notify('Photo saved to your travel journal.');
    }catch{this.notify('Photo could not be saved. Browser storage may be full or capture unavailable.');}finally{this.capturing=false;$('btn-photo').disabled=false;}
  }
  render(){
    try{this.journal.refresh();}catch{}
    const wrap=$('journal-entries');wrap.replaceChildren();const entries=this.journal.entries;
    const flights=entries.filter(e=>e.kind==='flight');$('journal-summary').textContent=`${flights.length} flights · ${flights.reduce((n,e)=>n+(e.distanceKm||0),0).toFixed(1)} km · ${Math.round(flights.reduce((n,e)=>n+(e.timeSec||0),0)/60)} minutes. Saved on this device (latest 60 entries).`;
    if(!entries.length)wrap.textContent='Your journeys start here. Finish a flight or take a photo to add an entry.';
    for(const e of entries){
      const card=document.createElement('article');card.className='journal-card';
      const title=document.createElement('h3');title.textContent=e.name||'Flight';card.append(title);
      const meta=document.createElement('p');meta.textContent=`${new Date(e.date).toLocaleString()} · ${e.world && e.world!=='google'?'Archived flight':'Real world'}${e.kind==='flight'?` · ${(e.distanceKm||0).toFixed(1)} km · ${Math.round((e.timeSec||0)/60)} min${e.landed?' · Landed':''}`:''}`;card.append(meta);
      if(e.vehicle){const p=document.createElement("p");p.textContent=e.vehicle==="spaceship"?"Wayfarer · Spaceship":"Aerion · Airplane";card.append(p);}
      if(e.target){const p=document.createElement('p');p.textContent=`Route to ${e.target.name}`;card.append(p);}
      if(e.image){const img=document.createElement('img');img.src=e.image;img.alt=`Flight over ${e.name}`;img.loading='lazy';card.append(img);const a=document.createElement('a');a.href=e.image;a.download='open-skies-journey.jpg';a.textContent='Download photo';card.append(a);}
      if(e.path?.length>1){const map=document.createElementNS('http://www.w3.org/2000/svg','svg');map.setAttribute('viewBox','0 0 300 100');map.setAttribute('role','img');map.setAttribute('aria-label','Recorded flight track, schematic');const line=document.createElementNS(map.namespaceURI,'polyline');line.setAttribute('points',trackPoints(e.path));line.setAttribute('fill','none');line.setAttribute('stroke','#c85d39');line.setAttribute('stroke-width','2');map.append(line);card.append(map);}
      const favorite=document.createElement('button');favorite.textContent=e.favorite?'★ Favorite':'☆ Favorite';favorite.setAttribute('aria-pressed',String(!!e.favorite));favorite.onclick=()=>{try{this.journal.favorite(e.id);this.render();}catch{this.notify('Could not save your favorite.');}};card.append(favorite);
      const exportButton=document.createElement('button');exportButton.textContent='Export journey';exportButton.onclick=()=>{const {image,...record}=e;const blob=new Blob([JSON.stringify(record,null,2)],{type:'application/json'});const a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download='open-skies-journey.json';a.click();setTimeout(()=>URL.revokeObjectURL(a.href),1000);};card.append(exportButton);
      if(e.start && (!e.world || e.world==='google')){const revisit=document.createElement('button');revisit.textContent='Plan this flight';revisit.onclick=()=>{$('journal-dialog').close();this.revisit(e);};card.append(revisit);}
      const remove=document.createElement('button');remove.textContent='Delete entry';remove.onclick=()=>{try{const next=this.journal.entries.filter(item=>item.id!==e.id);localStorage.setItem(this.journal.key,JSON.stringify(next));this.journal.entries=next;this.render();}catch{this.notify('Could not delete the entry.');}};card.append(remove);
      wrap.append(card);
    }
  }
}
