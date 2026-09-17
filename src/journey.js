// Personal journeys stay in this browser; no account or upload required.
export function routeInfo(a, b) {
  const rad=Math.PI/180, p=a.lat*rad, q=b.lat*rad, dl=(b.lng-a.lng)*rad;
  const h=Math.sin((q-p)/2)**2+Math.cos(p)*Math.cos(q)*Math.sin(dl/2)**2;
  const km=6371*2*Math.atan2(Math.sqrt(Math.min(1,h)),Math.sqrt(Math.max(0,1-h)));
  const bearing=(Math.atan2(Math.sin(dl)*Math.cos(q),Math.cos(p)*Math.sin(q)-Math.sin(p)*Math.cos(q)*Math.cos(dl))/rad+360)%360;
  return {km,bearing,minutes:km/3};
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
const PLACE_NOTES = {
  'Manhattan': 'Follow the river edges for an open view of the skyline. A gentle circuit makes the city easier to take in.',
  'Tokyo Bay': 'Follow the waterfront, then turn back toward the city. Use the shoreline as a visual guide.',
  'Swiss Alps': 'Follow the valleys and leave room to climb before approaching higher ground.',
  'Grand Canyon': 'Explore along the rim first. Watch your altitude as the terrain rises ahead of you.',
  'Ithaka': 'Trace the island shoreline at a relaxed pace, then turn inland for a different perspective.',
  'Alyzia': 'Try a coastal circuit, using the contrast between land and sea to keep your bearings.',
  'Cape Town': 'Circle the harbour before heading toward the hills. Leave plenty of room above rising terrain.',
  'Key West': 'Explore the edges of the island and follow the coastline back to your departure point.'
};
const $=id=>document.getElementById(id);
export class Journey {
  constructor(app, presets, notify, revisit) {
    this.app=app;this.presets=presets;this.notify=notify;this.revisit=revisit;this.journal=new Journal();
    const dest=$('route-end');
    for(const p of presets) {const o=document.createElement('option');o.value=p.name;o.textContent=p.name;dest.append(o);}
    // Nearby touring routes make the planner useful without hours of travel.
    dest.add(new Option('Local tour · 10 km north','local'));
    dest.addEventListener('change',()=>this.plan());
    $('btn-journal').onclick=()=>{this.render();$('journal-dialog').showModal();};
    $('journal-close').onclick=()=>$('journal-dialog').close();
    $('btn-photo').onclick=()=>this.photo();
    $('btn-minimal').onclick=()=>this.toggleMinimal();
    const settingIds=['time-of-day','weather','air-motion','radio','discoveries','runway-start'];
    try{const saved=JSON.parse(localStorage.getItem('open-skies.preferences')||'{}');for(const id of settingIds){const el=$(id);if(el.type==='checkbox'&&typeof saved[id]==='boolean')el.checked=saved[id];else if([...el.options||[]].some(o=>o.value===saved[id]))el.value=saved[id];}}catch{}
    for(const id of settingIds)$(id).addEventListener('change',()=>{this.apply();try{localStorage.setItem('open-skies.preferences',JSON.stringify(Object.fromEntries(settingIds.map(key=>[key,$(key).type==='checkbox'?$(key).checked:$(key).value]))));}catch{}});
    window.addEventListener('keydown',e=>{if(!app.flying||e.repeat||e.target?.matches('input,textarea,select,[contenteditable=true]'))return;if(e.code==='KeyH')this.toggleMinimal();if(e.code==='KeyP')this.photo();});
    $('btn-return').onclick=()=>{this.target={...this.departure};this.arrived=false;this.notify('Guidance set to your departure point.');};
    this.plan();
  }
  plan() {
    const start=this.app.world==='sandbox'?{name:'Meadow Airfield',lat:0,lng:0}:this.app.destination;
    const select=$('route-end');
    for(const o of select.options) {
      o.disabled=!!o.value && (this.app.world==='sandbox' ? o.value!=='local' : o.value===start.name);
      if(o.value==='local')o.textContent=this.app.world==='sandbox'?'Northern fields · practice tour':'Local tour · 10 km north';
    }
    if(select.selectedOptions[0]?.disabled)select.value='';
    const choice=select.value;
    this.destination=choice==='local'?{name:this.app.world==='sandbox'?'Northern fields':'Local tour',lat:this.app.world==='sandbox'?.025:Math.min(89.9,start.lat+.09),lng:this.app.world==='sandbox'?.012:start.lng}:this.presets.find(p=>p.name===choice);
    this.start=start;
    const r=this.destination?routeInfo(start,this.destination):null;
    $('route-estimate').textContent=r?`${start.name} → ${this.destination.name} · ${r.km.toFixed(1)} km · about ${Math.max(1,Math.round(r.minutes))} min at cruise`:'Explore freely, or choose an optional destination.';
  }
  apply() {
    const f=this.app.flight;if(!f?.viewer)return;
    f.airMotion=$('air-motion').checked;
    f.setAtmosphere($('time-of-day').value,$('weather').value);
  }
  begin() {
    this.plan();this.discovered=new Set();this.arrived=false;this.lastPhase=null;this.apply();
    this.departure={...this.start};this.target=this.destination?{...this.destination}:null;
    $('journey-nav').hidden=false;
    document.querySelector('.journey-actions').hidden=false;
    if($('radio').checked)this.app.audio.say('Open Skies. Enjoy your flight.');
  }
  update(s) {
    const f=this.app.flight,C=window.Cesium,c=C.Cartographic.fromCartesian(f.position),here={lat:C.Math.toDegrees(c.latitude),lng:C.Math.toDegrees(c.longitude)};
    this.here=here;
    const phase=f.phase;
    let line='';
    if(phase==='parked'||phase==='rolling')line='Runway 36 · Increase throttle · At 105 km/h, pitch up (W / ↑ or STEER up)';
    else if(phase==='landed')line='Touchdown · Reduce throttle to brake · Finish when stopped';
    else if(this.target){const r=routeInfo(here,this.target);line=`${this.target.name} · ${r.km.toFixed(1)} km · steer ${Math.round(r.bearing).toString().padStart(3,'0')}°`;if(r.km<.5&&!this.arrived&&phase==='airborne'){this.arrived=true;this.notify('Destination reached — enjoy the view.');if($('radio').checked)this.app.audio.say('Destination reached.');}}
    else line='Free exploration';
    $('journey-nav').textContent=line;
    if(phase!==this.lastPhase&&phase==='landed'&&$('radio').checked)this.app.audio.say('Welcome back to Meadow Airfield.');
    this.lastPhase=phase;
    this.app.audio.setGround(phase==='rolling'||phase==='landed',s.speedKmh);
    if(!$('discoveries').checked)return;
    const places=this.app.world==='sandbox'?[{name:'Meadow Airfield',lat:0,lng:0,desc:'Line up north or south with the paved strip. Slow down and keep the wings level for landing.'},{name:'Northern fields',lat:.025,lng:.012,desc:'The winding golden gates lead across the fields. Bank gently to follow the course.'}]:this.presets;
    for(const p of places)if(!this.discovered.has(p.name)&&routeInfo(here,p).km<2){this.discovered.add(p.name);$('discovery-note').textContent=`${p.name} · ${PLACE_NOTES[p.name] || p.desc}`;clearTimeout(this.noteTimer);this.noteTimer=setTimeout(()=>$('discovery-note').textContent='',12000);break;}
  }
  finish(flight) {
    document.body.classList.remove('minimal-flight');$('btn-minimal').textContent='Hide HUD';$('btn-minimal').setAttribute('aria-pressed','false');$('journey-nav').hidden=true;$('discovery-note').textContent='';clearTimeout(this.noteTimer);
    if(!flight||flight.timeSec<1)return;
    try {this.journal.save({kind:'flight',name:this.departure?.name||'Flight',start:this.departure,target:this.target,world:flight.world,timeSec:flight.timeSec,distanceKm:flight.distanceKm,topSpeedKmh:flight.topSpeedKmh,path:flight.path,landed:this.app.flight.phase==='landed',discoveries:[...(this.discovered||[])]});}catch{this.notify('Logbook could not save. Browser storage may be full or unavailable.');}
  }
  toggleMinimal(){const on=document.body.classList.toggle('minimal-flight');$('btn-minimal').textContent=on?'Show HUD':'Hide HUD';$('btn-minimal').setAttribute('aria-pressed',String(on));}
  async photo(){
    if(!this.app.flying||this.capturing)return;this.capturing=true;$('btn-photo').disabled=true;
    const context={name:this.departure?.name||'Flight',start:{...this.departure},target:this.target?{...this.target}:null,world:this.app.world,position:this.here?{...this.here}:null,path:this.app.flight.path.map(p=>p.slice())};
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
      const meta=document.createElement('p');meta.textContent=`${new Date(e.date).toLocaleString()} · ${e.world==='sandbox'?'Sandbox':'Real world'}${e.kind==='flight'?` · ${(e.distanceKm||0).toFixed(1)} km · ${Math.round((e.timeSec||0)/60)} min${e.landed?' · Landed':''}`:''}`;card.append(meta);
      if(e.target){const p=document.createElement('p');p.textContent=`Route to ${e.target.name}`;card.append(p);}
      if(e.discoveries?.length){const p=document.createElement('p');p.textContent='Discovered: '+e.discoveries.join(', ');card.append(p);}
      if(e.image){const img=document.createElement('img');img.src=e.image;img.alt=`Flight over ${e.name}`;img.loading='lazy';card.append(img);const a=document.createElement('a');a.href=e.image;a.download='open-skies-journey.jpg';a.textContent='Download photo';card.append(a);}
      if(e.path?.length>1){const map=document.createElementNS('http://www.w3.org/2000/svg','svg');map.setAttribute('viewBox','0 0 300 100');map.setAttribute('role','img');map.setAttribute('aria-label','Recorded flight track, schematic');const xs=e.path.map(p=>p[0]),ys=e.path.map(p=>p[1]),minX=Math.min(...xs),minY=Math.min(...ys),span=Math.max(Math.max(...xs)-minX,Math.max(...ys)-minY,.001);const line=document.createElementNS(map.namespaceURI,'polyline');line.setAttribute('points',e.path.map(p=>`${10+(p[0]-minX)/span*80},${90-(p[1]-minY)/span*80}`).join(' '));line.setAttribute('fill','none');line.setAttribute('stroke','#c85d39');line.setAttribute('stroke-width','2');map.append(line);card.append(map);}
      const favorite=document.createElement('button');favorite.textContent=e.favorite?'★ Favorite':'☆ Favorite';favorite.setAttribute('aria-pressed',String(!!e.favorite));favorite.onclick=()=>{try{this.journal.favorite(e.id);this.render();}catch{this.notify('Could not save your favorite.');}};card.append(favorite);
      const exportButton=document.createElement('button');exportButton.textContent='Export journey';exportButton.onclick=()=>{const {image,...record}=e;const blob=new Blob([JSON.stringify(record,null,2)],{type:'application/json'});const a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download='open-skies-journey.json';a.click();setTimeout(()=>URL.revokeObjectURL(a.href),1000);};card.append(exportButton);
      if(e.start){const revisit=document.createElement('button');revisit.textContent='Plan this flight';revisit.onclick=()=>{$('journal-dialog').close();this.revisit(e);};card.append(revisit);}
      const remove=document.createElement('button');remove.textContent='Delete entry';remove.onclick=()=>{try{const next=this.journal.entries.filter(item=>item.id!==e.id);localStorage.setItem(this.journal.key,JSON.stringify(next));this.journal.entries=next;this.render();}catch{this.notify('Could not delete the entry.');}};card.append(remove);
      wrap.append(card);
    }
  }
}
