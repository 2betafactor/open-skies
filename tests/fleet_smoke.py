"""Both shipped models, selection, handling reset, recording and replay geometry.
External tile responses are fixtures; the renderer, GLBs and flight code are real.
"""
import sys,tempfile,threading
from pathlib import Path
from playwright.sync_api import sync_playwright
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import server
with tempfile.TemporaryDirectory() as data:
 server.DATA=data;server.SCORES=data+'/scores.json'
 http=server.ThreadingHTTPServer(('127.0.0.1',0),server.Handler)
 threading.Thread(target=http.serve_forever,daemon=True).start()
 with sync_playwright() as p:
  browser=p.chromium.launch(headless=True,args=['--no-sandbox','--enable-unsafe-swiftshader'])
  page=browser.new_page(viewport={'width':1000,'height':760})
  errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
  page.route('**/*google*',lambda r:r.abort())
  page.route('https://tile.googleapis.com/**',lambda r:r.fulfill(json={'asset':{'version':'1.0'},'geometricError':0,'root':{'boundingVolume':{'sphere':[0,0,0,6378137]},'geometricError':0,'refine':'ADD','children':[]}}))
  page.goto(f'http://localhost:{http.server_port}',wait_until='networkidle')
  page.locator('.quality-btn').filter(has_text='Performance').click()
  page.screenshot(path='/tmp/fleet-home.png')
  page.evaluate('''async()=>{const {ensureEngine}=await import('/src/engine.js?v=fleet7');await ensureEngine();window.HORSEBACK_CONFIG={GOOGLE_MAPS_API_KEY:'test-only'};const {Flight}=await import('/src/flight.js?v=fleet7');const start=Flight.prototype.start;Flight.prototype.start=function(){window.testFlight=this;return start.call(this)};}''')
  for aircraft in ['plane','spaceship']:
   page.click(f'[data-aircraft={aircraft}]');page.click('#btn-takeoff')
   page.wait_for_function('window.testFlight?._running',timeout=60000)
   assert page.evaluate('testFlight.vehicleId')==aircraft
   checks=page.evaluate('''()=>{const f=testFlight,C=Cesium;f._running=false;f.heading=0;f.pitch=0;f.roll=0;f._recomputeOrientation();const nose=C.Matrix3.multiplyByVector(C.Matrix3.fromQuaternion(f.orientation),C.Cartesian3.UNIT_X,new C.Cartesian3());const bounds=new C.BoundingSphere();const ready=f.viewer.dataSourceDisplay.getBoundingSphere(f.plane,false,bounds)===C.BoundingSphereState.DONE;const dot=C.Cartesian3.dot(nose,f._basisFor(0,0,0).F);return {ready,mount:dot>.999,bounds:bounds.radius<20,physics:Number.isFinite(f.speed)&&f.speed>0};}''')
   assert all(checks.values()),checks
   if aircraft=='plane':
    assert page.evaluate('''()=>{const f=testFlight;f.roll=.5;f.controls.roll=1;f.controls.level=true;for(let i=0;i<120;i++)f._step(1/60);const leveled=Math.abs(f.roll)<.05;f.controls.roll=0;f.controls.level=false;f.roll=0;f.speed=70;f.throttle=.5;f.flaps=0;f._step(.02);const clean=f.speed;f.speed=70;f.flaps=40;f._step(.02);const drag=f.speed<clean;f.flaps=0;return leveled&&drag;}''')
   if aircraft=='spaceship':
    page.keyboard.press('v');page.keyboard.press('f')
    assert page.evaluate("testFlight.mode==='arcade'&&testFlight.flaps===0")
   page.keyboard.press('c');page.wait_for_timeout(200)
   page.screenshot(path=f'/tmp/fleet-{aircraft}.png')
   page.evaluate('testFlight.distance=1;testFlight._elapsed=30')
   page.click('#btn-dismount');page.click('#btn-result-again')
   print(aircraft,'loaded, points forward, correct handling and saved to logbook',flush=True)
  entries=page.evaluate("JSON.parse(localStorage.getItem('open-skies.journal.v1'))")
  assert [e['vehicle'] for e in entries[:2]]==['spaceship','plane']
  page.click('#btn-journal');page.get_by_role('button',name='Plan this flight',exact=True).nth(1).click()
  assert page.locator('[data-aircraft=plane]').get_attribute('aria-pressed')=='true'
  checks=page.evaluate('''async()=>{const f=testFlight,{VEHICLES}=await import('/src/vehicles.js?v=fleet7');f.setVehicle(VEHICLES[0]);const reset=f.P.maxSpeedKmh===460&&f.vehicleType==='plane';document.querySelectorAll('.screen').forEach(e=>e.classList.toggle('active',e.id==='screen-ride'));f.viewer.resize();f.viewer.useDefaultRenderLoop=true;f.onReplayEnd=()=>{};await f.startReplay([[179.9,0,400,0],[-179.9,0,400,0]],()=>{},'spaceship');f._recElapsed=0;f._stepReplay(.25);f._replayReady=false;const lon=Cesium.Math.toDegrees(Cesium.Cartographic.fromCartesian(f.position).longitude);const result={reset,replay:f.vehicleId==='spaceship',dateLine:Math.abs(lon)>179.8};f.dispose();return result;}''')
  assert all(checks.values()),checks
  assert not errors,errors
  print('Aircraft revisit, parameter reset, spaceship replay and date-line interpolation passed.',flush=True)
  browser.close()
 http.shutdown();http.server_close()
