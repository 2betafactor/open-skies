"""Journey persistence, real-world launch contract, weather and minimal HUD."""
import sys, tempfile, threading
from pathlib import Path
from playwright.sync_api import sync_playwright
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import server
with tempfile.TemporaryDirectory() as data:
 server.DATA=data;server.SCORES=data+'/scores.json'
 http=server.ThreadingHTTPServer(('127.0.0.1',0),server.Handler)
 threading.Thread(target=http.serve_forever,daemon=True).start()
 with sync_playwright() as p:
  b=p.chromium.launch(headless=True,args=['--no-sandbox','--enable-unsafe-swiftshader'])
  page=b.new_page(viewport={'width':390,'height':844})
  errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
  page.route('**/*google*',lambda r:r.abort())
  page.route('https://tile.googleapis.com/**',lambda r:r.fulfill(json={'asset':{'version':'1.0'},'geometricError':0,'root':{'boundingVolume':{'sphere':[0,0,0,6378137]},'geometricError':0,'refine':'ADD','children':[]}}))
  page.goto(f'http://localhost:{http.server_port}',wait_until='networkidle')
  page.locator('.flight-options summary').click()
  page.select_option('#route-end','local')
  assert '10.0 km' in page.locator('#route-estimate').inner_text()
  checks=page.evaluate('''async()=>{const {routeInfo,Journal}=await import('/src/journey.js?v=fleet7');const r=routeInfo({lat:0,lng:0},{lat:0,lng:1});const j=new Journal();j.save({kind:'flight',name:'Persistence check',distanceKm:1});const next=new Journal();return {distance:Math.abs(r.km-111.195)<.01,bearing:r.bearing===90,persist:next.entries[0].name==='Persistence check'};}''')
  assert all(checks.values()),checks
  page.select_option('#time-of-day','sunset');page.select_option('#weather','rain')
  page.screenshot(path='/tmp/journey-home.png')
  page.evaluate('''async()=>{const {Flight}=await import('/src/flight.js?v=fleet7');const start=Flight.prototype.start;Flight.prototype.start=function(){window.testFlight=this;return start.call(this)};}''')
  page.locator('.quality-btn').filter(has_text='Performance').click()
  print('Loading 3D engine for real-world launch check',flush=True)
  page.evaluate('''async()=>{const {ensureEngine}=await import('/src/engine.js?v=fleet7');await ensureEngine();window.HORSEBACK_CONFIG={GOOGLE_MAPS_API_KEY:'test-only'};}''')
  print('Launching with external tiles stubbed',flush=True)
  page.click('#btn-takeoff');page.wait_for_function('window.testFlight?._running',timeout=60000)
  assert page.evaluate('testFlight.phase')=='airborne'
  assert page.evaluate('testFlight.weather')=='rain'
  page.wait_for_timeout(1000)
  assert page.evaluate("testFlight.world==='google' && testFlight.vehicleId==='plane'")
  assert page.evaluate("testFlight.viewer.dataSourceDisplay.getBoundingSphere(testFlight.plane,false,new Cesium.BoundingSphere())===Cesium.BoundingSphereState.DONE")
  page.evaluate('testFlight._elapsed=120;testFlight.distance=2')
  print('Real-world launch and upgraded airplane rendering passed with the external tiles provider stubbed.',flush=True)
  assert not page.evaluate('testFlight._warned'), 'Flight loop error'
  page.click('#btn-minimal');assert page.locator('body').evaluate("e=>e.classList.contains('minimal-flight')")
  assert page.locator('#journey-nav').is_visible()
  assert page.locator('#hud-warning').evaluate("e=>getComputedStyle(e).visibility")!='hidden'
  print('Testing photo capture',flush=True)
  page.click('#btn-photo');page.wait_for_function("JSON.parse(localStorage.getItem('open-skies.journal.v1')).some(e=>e.kind==='photo')",timeout=20000)
  page.screenshot(path='/tmp/journey-flight-mobile.png')
  assert page.locator('#btn-minimal').evaluate('e=>e.getBoundingClientRect().x>=0')
  print('Photo and mobile view passed',flush=True)
  page.click('#btn-minimal');page.click('#btn-dismount')
  page.click('#btn-result-again');page.click('#btn-journal')
  assert page.locator('.journal-card img').count()==1
  assert page.locator('.journal-card').count()==3
  page.locator('.journal-card button').filter(has_text='Favorite').first.click()
  page.screenshot(path='/tmp/journey-journal-mobile.png')
  page.reload(wait_until='networkidle');page.click('#btn-journal')
  assert page.locator('.journal-card').count()==3
  assert page.locator('.journal-card button[aria-pressed=true]').count()==1
  assert not errors,errors
  print('Weather rendering, minimal HUD, photo capture, flight log, favorite and reload persistence passed.',flush=True)
  b.close()
 http.shutdown();http.server_close()
