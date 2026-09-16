import { DrivePhysics, ROUTE, ROAD_CENTERS } from './drive-physics.js';
import { DriveCity } from './drive-city.js';
import { EngineAudio } from './audio.js';

const $=id=>document.getElementById(id);
const keys=new Set(), pointers=new Map();
const audio=new EngineAudio();
audio.muted=true;
let viewer, city, physics, car, position, orientation;
let running=false, started=false, lastTime=0, camHeading=0, best=null, noticeUntil=0;
const formatTime=s=>`${Math.floor(s/60)}:${String(Math.floor(s%60)).padStart(2,'0')}`;
try { const saved=Number(localStorage.getItem('open-skies.drive.best.v1')); if(saved>0 && Number.isFinite(saved))best=saved; } catch {}
const binding={KeyW:'forward',ArrowUp:'forward',KeyS:'reverse',ArrowDown:'reverse',KeyA:'left',ArrowLeft:'left',KeyD:'right',ArrowRight:'right',Space:'brake'};
function inputState() {
  const input={};
  keys.forEach(code=> {if(binding[code])input[binding[code]]=true;});
  pointers.forEach(control=>input[control]=true);
  return input;
}
function clearInput() {keys.clear();pointers.clear();document.querySelectorAll('.held').forEach(b=>b.classList.remove('held'));}
function notice(message) {$('drive-notice').textContent=message;noticeUntil=performance.now()+2600;}
function pose() {
  const C=window.Cesium;
  position=city.point(physics.x,physics.y,.24);
  orientation=C.Transforms.headingPitchRollQuaternion(position,new C.HeadingPitchRoll(physics.heading,0,0));
}
function camera(dt) {
  const C=window.Cesium;
  const difference=Math.atan2(Math.sin(physics.heading-camHeading),Math.cos(physics.heading-camHeading));
  camHeading+=difference*(1-Math.exp(-dt*7));
  const target=city.point(physics.x+Math.sin(camHeading)*9,physics.y+Math.cos(camHeading)*9,1.0);
  viewer.camera.lookAt(target,new C.HeadingPitchRange(camHeading,-.2,23));
}
function setPaused(paused) {
  if(!viewer || !started)return;
  running=!paused;clearInput();lastTime=0;
  $('menu').hidden=!paused;
  $('pause').textContent=paused?'Resume':'Pause';
  $('menu-title').textContent='Pit stop';
  $('menu-description').textContent=`${(physics.distance/1000).toFixed(2)} km driven · ${physics.laps} laps · ${physics.hits} bumps. Your car is waiting where you left it.`;
  $('start').textContent='Resume driving →';
  $('restart').hidden=false;
  if(paused)audio.suspend();else if(!audio.muted)audio.start();
}
function start(fresh=false) {
  if(!physics)return;
  if(fresh || !started) {physics.reset();camHeading=0;city.setTarget(0);pose();notice('Follow the gold checkpoints. Enjoy the drive.');}
  started=true;setPaused(false);camera(1);updateHUD();
}
function recover() {
  if(!running)return;
  physics.recover();camHeading=physics.heading;pose();camera(1);clearInput();notice('Back on the route');
}
function updateHUD() {
  $('speed').textContent=Math.round(Math.abs(physics.speed)*3.6);
  $('gear').textContent=physics.speed<-.2?'R':physics.speed>.2?'D':'N';
  $('lap').textContent=physics.laps+1;
  $('target').textContent=`Checkpoint ${physics.checkpoint+1} / ${ROUTE.length}`;
  const target=ROUTE[physics.checkpoint], dx=target[0]-physics.x, dy=target[1]-physics.y;
  const angle=Math.atan2(Math.sin(Math.atan2(dx,dy)-physics.heading),Math.cos(Math.atan2(dx,dy)-physics.heading));
  const turn=Math.abs(angle)<.4?'Ahead':Math.abs(angle)>2.5?'Turn around':angle>0?'Turn right':'Turn left';
  $('direction').textContent=`${turn} · ${Math.round(Math.hypot(dx,dy))} m`;
  $('route-fill').style.width=`${physics.checkpoint/ROUTE.length*100}%`;
  $('trip').textContent=`${(physics.distance/1000).toFixed(2)} km`;
  $('timer').textContent=formatTime(physics.lapTime);
  $('best').textContent=best?`Best ${formatTime(best)}`:'Best lap —';
  drawMap();
}
function drawMap() {
  const ctx=$('minimap').getContext('2d'), size=240, scale=size/960;
  ctx.clearRect(0,0,size,size);ctx.fillStyle='#254c42';ctx.fillRect(0,0,size,size);
  const at=(x,y)=>[size/2+x*scale,size/2-y*scale];
  ctx.strokeStyle='#98aaa2';ctx.lineWidth=6;
  for(const c of ROAD_CENTERS) {
    ctx.beginPath();ctx.moveTo(...at(c,-450));ctx.lineTo(...at(c,450));ctx.stroke();
    ctx.beginPath();ctx.moveTo(...at(-450,c));ctx.lineTo(...at(450,c));ctx.stroke();
  }
  const goal=at(...ROUTE[physics.checkpoint]);ctx.fillStyle='#ffd37a';ctx.beginPath();ctx.arc(...goal,7,0,Math.PI*2);ctx.fill();
  ctx.save();ctx.translate(...at(physics.x,physics.y));ctx.rotate(physics.heading);
  ctx.fillStyle='#ffffff';ctx.strokeStyle='#122';ctx.lineWidth=2;ctx.beginPath();ctx.moveTo(0,-8);ctx.lineTo(6,6);ctx.lineTo(0,3);ctx.lineTo(-6,6);ctx.closePath();ctx.fill();ctx.stroke();ctx.restore();
}
function tick() {
  const now=performance.now();
  if(!lastTime)lastTime=now;
  const dt=Math.min(.1,(now-lastTime)/1000);lastTime=now;
  if(!running || document.hidden)return;
  const previous=physics.checkpoint, laps=physics.laps, hits=physics.hits;
  const input=inputState(), steps=Math.max(1,Math.ceil(dt/(1/60)));
  for(let i=0;i<steps;i++)physics.step(dt/steps,input);
  if(physics.checkpoint!==previous || physics.laps!==laps) {
    city.setTarget(physics.checkpoint);
    if(physics.laps!==laps) {
      const record=!best || physics.lastLap<best;
      if(record) {best=physics.lastLap;try {localStorage.setItem('open-skies.drive.best.v1',String(best));}catch {}}
      notice(`${record?'New best!':'Lap complete!'} ${formatTime(physics.lastLap)}`);
    } else notice(`Checkpoint ${previous+1} cleared`);
  }
  if(physics.hits!==hits)notice('Bump! Reverse or press R to reset.');
  if(now>noticeUntil)$('drive-notice').textContent='';
  pose();camera(dt);updateHUD();audio.setSpeed(Math.min(1,Math.abs(physics.speed)/36));
}
function fail(error) {
  running=false;clearInput();audio.suspend();
  $('menu').hidden=false;
  $('loading-status').textContent='The 3D scene could not load. Check your connection and reload, or return to flying.';
  $('start').disabled=true;
  console.error(error);
}
async function init() {
  const C=window.Cesium;
  if(!C)throw new Error('Cesium is unavailable');
  C.Ion.defaultAccessToken=undefined;
  viewer=new C.Viewer('drive-scene',{baseLayer:false,baseLayerPicker:false,geocoder:false,homeButton:false,sceneModePicker:false,navigationHelpButton:false,fullscreenButton:false,timeline:false,animation:false,infoBox:false,selectionIndicator:false});
  viewer.resolutionScale=.85;viewer.useBrowserRecommendedResolution=true;
  const scene=viewer.scene;
  scene.globe.baseColor=C.Color.fromCssColorString('#66806b');scene.skyBox.show=false;
  scene.skyAtmosphere.show=true;scene.backgroundColor=C.Color.fromCssColorString('#9dc6d4');
  scene.screenSpaceCameraController.enableInputs=false;
  scene.light=new C.DirectionalLight({direction:C.Cartesian3.normalize(new C.Cartesian3(-.6,-.2,-.8),new C.Cartesian3()),intensity:2});
  scene.renderError.addEventListener((_,e)=>fail(e));
  city=new DriveCity(viewer);physics=new DrivePhysics(city.obstacles);pose();
  car=viewer.entities.add({position:new C.CallbackProperty(()=>position,false),orientation:new C.CallbackProperty(()=>orientation,false),model:{uri:'assets/street-gt.glb',scale:1,minimumPixelSize:48}});
  viewer.camera.lookAtTransform(city.frame,new C.Cartesian3(550,-700,650));
  scene.preUpdate.addEventListener(tick);
  updateHUD();
  $('loading-status').textContent='Ready to drive. No Google Maps connection required.';
  $('start').disabled=false;
}
$('start').disabled=true;
$('start').addEventListener('click',()=>start());
$('restart').addEventListener('click',()=>start(true));
$('pause').addEventListener('click',()=>setPaused(running));
$('recover').addEventListener('click',recover);
$('sound').addEventListener('click',()=> {
  audio.toggleMute();$('sound').textContent=audio.muted?'Sound off':'Sound on';
  if(!audio.muted && running)audio.start();
});
window.addEventListener('keydown',event=> {
  if(event.target.matches('input,textarea,select,[contenteditable=true]'))return;
  if(binding[event.code])event.preventDefault();
  if(!event.repeat && (event.code==='Escape'||event.code==='KeyP')) {setPaused(running);return;}
  if(!running)return;
  if(event.code==='KeyR' && !event.repeat)recover();
  keys.add(event.code);
});
window.addEventListener('keyup',event=>keys.delete(event.code));
window.addEventListener('blur',()=>setPaused(true));
document.addEventListener('visibilitychange',()=> {if(document.hidden)setPaused(true);});
for(const button of document.querySelectorAll('[data-control]')) {
  button.addEventListener('pointerdown',event=> {
    if(!running)return;
    event.preventDefault();button.setPointerCapture(event.pointerId);
    pointers.set(event.pointerId,button.dataset.control);button.classList.add('held');
  });
  const release=event=> {pointers.delete(event.pointerId);if(![...pointers.values()].includes(button.dataset.control))button.classList.remove('held');};
  button.addEventListener('pointerup',release);button.addEventListener('pointercancel',release);button.addEventListener('lostpointercapture',release);
}
window.addEventListener('pagehide',()=> {audio.suspend();if(viewer && !viewer.isDestroyed())viewer.destroy();});
init().catch(fail);
