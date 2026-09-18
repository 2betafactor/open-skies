const API='https://de1.api.radio-browser.info/json/stations/search';
const NIGHTRIDE={name:'Nightride FM · EQ',country:'Online',codec:'MP3',url:'https://stream.nightride.fm/nightride.mp3'};
const FALLBACK=[
  {name:'BBC World Service',country:'United Kingdom',codec:'MP3',url:'https://stream.live.vc.bbcmedia.co.uk/bbc_world_service',geo_lat:51.5,geo_long:-.12},
  {name:'Radio Paradise',country:'United States',codec:'MP3',url:'https://stream.radioparadise.com/aac-320',geo_lat:38.9,geo_long:-122.7},
  {name:'FIP',country:'France',codec:'MP3',url:'https://icecast.radiofrance.fr/fip-hifi.aac',geo_lat:48.86,geo_long:2.35}
];
const $=id=>document.getElementById(id);
function distance(a,b){const r=Math.PI/180,p=a.lat*r,q=b.lat*r,dl=(b.lng-a.lng)*r;const h=Math.sin((q-p)/2)**2+Math.cos(p)*Math.cos(q)*Math.sin(dl/2)**2;return 6371*2*Math.atan2(Math.sqrt(h),Math.sqrt(Math.max(0,1-h)));}
export class Radio {
  constructor(notify){this.notify=notify;this.audio=new Audio();this.audio.preload='none';this.station=null;this.stations=[];this.bind();}
  bind(){const stop=$('radio-stop');if(!stop)return;stop.onclick=()=>this.stop();this.audio.addEventListener('error',()=>{this.status('Nightride FM could not be reached.');stop.disabled=true;});}
  status(text){const el=$('radio-status');if(el)el.textContent=text;}
  start(){this.load([NIGHTRIDE,...FALLBACK],'Nightride FM');this.play(NIGHTRIDE);}
  async find(){const button=$('radio-locate');button.disabled=true;this.status('Requesting your location…');let pos;try{pos=await new Promise((resolve,reject)=>navigator.geolocation.getCurrentPosition(resolve,reject,{enableHighAccuracy:false,timeout:9000,maximumAge:300000}));}catch{this.load(FALLBACK,'Worldwide picks');button.disabled=false;this.status('Location was unavailable, so here are reliable digital stations.');if(this.auto){this.auto=false;this.play(FALLBACK[0]);}return;}
    const here={lat:pos.coords.latitude,lng:pos.coords.longitude};let stations=[];try{const u=new URL(API);u.searchParams.set('has_geo_info','true');u.searchParams.set('is_https','true');u.searchParams.set('hidebroken','true');u.searchParams.set('order','clickcount');u.searchParams.set('reverse','true');u.searchParams.set('limit','200');const res=await fetch(u);if(!res.ok)throw Error('directory');const data=await res.json();stations=data.filter(s=>Number.isFinite(Number(s.geo_lat))&&Number.isFinite(Number(s.geo_long))&&(s.url_resolved||s.url)).map(s=>({...s,url:s.url_resolved||s.url,_distance:distance(here,{lat:Number(s.geo_lat),lng:Number(s.geo_long)})})).sort((a,b)=>a._distance-b._distance).slice(0,18);}catch{}
    const list=stations.length?stations:FALLBACK;this.load(list,stations.length?'Nearby stations':'Worldwide picks');button.disabled=false;this.status(stations.length?'Choose a nearby station to start playback.':'The directory is unavailable, so here are reliable digital stations.');if(this.auto){this.auto=false;this.play(list[0]);}
  }
  load(stations,label){this.stations=stations;$('radio-stop').disabled=true;$('radio-location').textContent=label;}
  play(station){this.station=station;this.audio.src=station.url;this.audio.play().then(()=>{$('radio-stop').disabled=false;this.status(`Playing ${station.name}.`);if(station.stationuuid)fetch(`https://de1.api.radio-browser.info/json/url/${encodeURIComponent(station.stationuuid)}`,{mode:'no-cors'}).catch(()=>{});}).catch(()=>this.status('Playback was blocked. Tap the station again to start it.'));}
  stop(){this.audio.pause();this.audio.removeAttribute('src');this.audio.load();$('radio-stop').disabled=true;this.status('Radio stopped.');}
}
