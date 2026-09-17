"""Journey persistence, route math, runway states, weather and minimal HUD."""
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
  page.goto(f'http://localhost:{http.server_port}',wait_until='networkidle')
  page.locator('.flight-options summary').click()
  page.select_option('#route-end','local')
  assert '10.0 km' in page.locator('#route-estimate').inner_text()
  checks=page.evaluate('''async()=>{const {routeInfo,Journal}=await import('/src/journey.js?v=journey5');const r=routeInfo({lat:0,lng:0},{lat:0,lng:1});const j=new Journal();j.save({kind:'flight',name:'Persistence check',distanceKm:1});const next=new Journal();return {distance:Math.abs(r.km-111.195)<.01,bearing:r.bearing===90,persist:next.entries[0].name==='Persistence check'};}''')
  assert all(checks.values()),checks
  page.click('[data-world=sandbox]')
  page.select_option('#time-of-day','sunset');page.select_option('#weather','rain')
  page.screenshot(path='/tmp/journey-home.png')
  page.evaluate('''async()=>{const {Flight}=await import('/src/flight.js?v=journey5');const start=Flight.prototype.start;Flight.prototype.start=function(){window.testFlight=this;return start.call(this)};}''')
  page.locator('.quality-btn').filter(has_text='Performance').click()
  page.click('#btn-sandbox');page.wait_for_function('window.testFlight?._running',timeout=60000)
  assert page.evaluate('testFlight.phase')=='parked'
  assert page.evaluate('testFlight.weather')=='rain'
  page.wait_for_timeout(1000)
  checks=page.evaluate('''()=>{const f=testFlight;f._running=false;const r={parked:f.speed===0};f.controls.throttle=1;for(let i=0;i<1200&&f.speed*3.6<110;i++)f._step(1/60);r.accelerates=f.speed*3.6>=105&&f.phase==='rolling';f.controls.pitch=1;f._step(1/60);r.takeoff=f.phase==='airborne'&&f.alt>7;
  f._setPositionLL(0,0,7.1);f.speed=30;f.heading=0;f.roll=0;f.pitch=-.03;f._vspeed=-1;f._altitude(.02);r.landing=f.phase==='landed';f.throttle=0;f.controls.throttle=0;f.controls.pitch=0;for(let i=0;i<700;i++)f._step(1/60);r.braking=f.speed===0;
  f.phase='airborne';f._setPositionLL(0,0,7);f.roll=.5;f.speed=70;const crashes=f.crashes;f._altitude(.02);r.hardLanding=f.crashes===crashes+1&&f.phase==='airborne';f._elapsed=120;f.distance=2;f._emitState();return r;}''')
  assert all(checks.values()),checks
  print('Route math, persistence, runway acceleration, rotation, landing, braking and hard-landing recovery passed.',flush=True)
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
