import sys,threading,tempfile
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import server
from playwright.sync_api import sync_playwright
with tempfile.TemporaryDirectory() as data:
 server.DATA=data;server.SCORES=data+'/scores.json'
 http=server.ThreadingHTTPServer(('127.0.0.1',0),server.Handler)
 threading.Thread(target=http.serve_forever,daemon=True).start()
 with sync_playwright() as p:
  b=p.chromium.launch(headless=True,args=['--no-sandbox','--enable-unsafe-swiftshader'])
  page=b.new_page(viewport={'width':1000,'height':720})
  errors=[]
  page.on('pageerror',lambda e:errors.append(str(e)))
  page.on('console',lambda m:errors.append(m.text) if m.type=='error' and 'Failed to load resource' not in m.text else None)
  page.route('**/*google*',lambda r:r.abort())
  page.goto(f'http://localhost:{http.server_port}',wait_until='networkidle')
  awaitable='''async () => {const {Flight}=await import('/src/flight.js?v=hangar3'); const start=Flight.prototype.start; Flight.prototype.start=function(){window.testFlight=this;return start.call(this)};}'''
  page.evaluate(awaitable)
  page.click('[data-world="sandbox"]')
  page.click('#btn-sandbox')
  page.wait_for_function('window.testFlight?._running',timeout=60000)
  page.wait_for_timeout(8000)
  page.evaluate('''() => { const f=window.testFlight; f._running=false; f.P.camBack=20; f.P.camUp=7; }''')
  page.screenshot(path='/tmp/skylark-flight.png')
  print('first aircraft',page.evaluate('({id:testFlight.vehicleId, elapsed:testFlight.getStats().timeSec, path:testFlight.path.length})'),flush=True)
  # Inspect timing, crash recovery, model switching and replay metadata directly.
  checks=page.evaluate('''async () => {
    const f=testFlight, {VEHICLES}=await import('/src/vehicles.js');
    const result={};
    f._elapsed=12.5; result.time=f.getStats().timeSec===12.5;
    f.alt=0;f.position=Cesium.Cartesian3.fromDegrees(0,0,0);f._altitude(.02);
    result.respawn=Cesium.Cartographic.fromCartesian(f.position).height>300;
    f.dispose(); result.idle=!f.viewer.useDefaultRenderLoop;
    await f.init(null,'sandbox'); f.setVehicle(VEHICLES.find(v=>v.id==='swift'));
    await f.spawn(0,0);f.start();f._running=false;f.P.camBack=20;f.P.camUp=7;
    result.aircraft=f.getFlight().vehicle==='swift';
    return result;
  }''')
  print(checks,flush=True)
  assert all(checks.values())
  page.wait_for_timeout(4000)
  page.screenshot(path='/tmp/swift-flight.png')
  print('errors',errors,flush=True)
  assert not errors
  b.close()
 http.shutdown()
