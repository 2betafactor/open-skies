"""End-to-end checks for single-aircraft navigation and flight."""
import sys, tempfile, threading
from pathlib import Path
from playwright.sync_api import sync_playwright
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import server
with tempfile.TemporaryDirectory() as data:
 server.DATA=data;server.SCORES=data+'/scores.json'
 http=server.ThreadingHTTPServer(('127.0.0.1',0),server.Handler)
 threading.Thread(target=http.serve_forever,daemon=True).start()
 base=f'http://localhost:{http.server_port}'
 with sync_playwright() as p:
  b=p.chromium.launch(headless=True,args=['--no-sandbox','--enable-unsafe-swiftshader'])
  page=b.new_page(viewport={'width':1280,'height':900})
  errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
  page.route('**/*google*',lambda r:r.abort())
  page.route('**/Cesium.js',lambda r:r.abort())
  page.goto(base,wait_until='networkidle')
  assert page.evaluate('!window.Cesium')
  assert page.locator('.vehicle-btn, #vehicles, #inspect-dialog').count()==0
  assert page.locator('[data-world=google]').get_attribute('aria-pressed')=='true'
  page.evaluate("localStorage.setItem('open-skies.aircraft','swift')")
  page.locator('.preset-card').filter(has_text='Tokyo Bay').click()
  assert page.locator('#selected-route').inner_text()=='Tokyo Bay'
  assert not page.locator('#screen-ride').is_visible()
  page.locator('#place-input').fill('Glasgow')
  page.locator('#place-input').press('g')
  assert not page.locator('.tuner-panel.show').count()
  assert page.locator('#btn-takeoff').is_disabled()
  page.locator('.preset-card').filter(has_text='Tokyo Bay').click()
  assert page.locator('#btn-takeoff').is_enabled()
  page.screenshot(path='/tmp/navigation-desktop.png')
  page.reload(wait_until='networkidle')
  assert page.locator('.vehicle-btn').count()==0
  page.set_viewport_size({'width':390,'height':844})
  assert page.evaluate('document.querySelector("#screen-landing").scrollWidth<=innerWidth')
  page.screenshot(path='/tmp/navigation-mobile.png')
  print('Home works without the 3D engine; single aircraft and explicit destination selection passed.',flush=True)
  page.unroute('**/Cesium.js')
  page.set_viewport_size({'width':1000,'height':760})
  awaitable='''async () => {const {Flight}=await import('/src/flight.js?v=journey5');const start=Flight.prototype.start;Flight.prototype.start=function(){window.testFlight=this;return start.call(this)};}'''
  page.evaluate(awaitable)
  page.click('[data-world=sandbox]');page.click('#btn-sandbox')
  page.wait_for_function('window.testFlight?._running',timeout=60000)
  assert page.evaluate('testFlight.vehicleId')=='plane'
  assert page.evaluate("testFlight.viewer.dataSourceDisplay.getBoundingSphere(testFlight.plane,false,new Cesium.BoundingSphere())===Cesium.BoundingSphereState.DONE")
  page.keyboard.press('c')
  assert page.evaluate('testFlight.cameraView')=='profile'
  page.screenshot(path='/tmp/navigation-plane-flying.png')
  page.set_viewport_size({'width':390,'height':844})
  page.screenshot(path='/tmp/navigation-flight-mobile.png')
  for button in ['btn-camera','btn-dismount']:
    rect=page.locator('#'+button).bounding_box()
    assert rect['x']>=0 and rect['x']+rect['width']<=390
  page.keyboard.press('Escape')
  assert not errors,errors
  print('Original aircraft loaded before takeoff, and profile camera passed.',flush=True)
  b.close()
 http.shutdown();http.server_close()
