"""End-to-end checks for real aircraft previews, selection, launch, and inspection."""
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
  assert page.locator('#plane-preview').evaluate('e=>e.complete && e.naturalWidth>400')
  page.locator('.vehicle-btn').filter(has_text='Swift').click()
  assert page.locator('#plane-name').inner_text()=='Swift'
  assert 'swift-preview' in page.locator('#plane-preview').get_attribute('src')
  page.locator('.preset-card').filter(has_text='Tokyo Bay').click()
  assert page.locator('#selected-route').inner_text()=='Tokyo Bay'
  assert not page.locator('#screen-ride').is_visible()
  page.locator('#place-input').fill('Glasgow')
  page.locator('#place-input').press('g')
  assert not page.locator('.tuner-panel.show').count()
  assert page.locator('#btn-takeoff').is_disabled()
  page.locator('.preset-card').filter(has_text='Tokyo Bay').click()
  assert page.locator('#btn-takeoff').is_enabled()
  page.screenshot(path='/tmp/hangar-desktop.png')
  page.reload(wait_until='networkidle')
  assert page.locator('#plane-name').inner_text()=='Swift'
  page.set_viewport_size({'width':390,'height':844})
  assert page.evaluate('document.querySelector("#screen-landing").scrollWidth<=innerWidth')
  page.screenshot(path='/tmp/hangar-mobile.png')
  print('Home works without the 3D engine; previews, persistent selection and explicit destination selection passed.',flush=True)
  page.unroute('**/Cesium.js')
  page.set_viewport_size({'width':1000,'height':760})
  page.click('#btn-inspect')
  page.wait_for_function("document.getElementById('inspect-status').textContent.startsWith('This is')",timeout=60000)
  page.click('#inspect-right')
  page.screenshot(path='/tmp/hangar-inspect.png')
  page.click('#inspect-close')
  page.wait_for_function("document.querySelectorAll('#inspect-stage canvas').length===0", timeout=5000)
  awaitable='''async () => {const {Flight}=await import('/src/flight.js');const start=Flight.prototype.start;Flight.prototype.start=function(){window.testFlight=this;return start.call(this)};}'''
  page.evaluate(awaitable)
  page.click('[data-world=sandbox]');page.click('#btn-sandbox')
  page.wait_for_function('window.testFlight?._running',timeout=60000)
  assert page.evaluate('testFlight.vehicleId')=='swift'
  assert page.evaluate("testFlight.viewer.dataSourceDisplay.getBoundingSphere(testFlight.plane,false,new Cesium.BoundingSphere())===Cesium.BoundingSphereState.DONE")
  page.keyboard.press('c')
  assert page.evaluate('testFlight.cameraView')=='profile'
  page.screenshot(path='/tmp/hangar-swift-flying.png')
  page.set_viewport_size({'width':390,'height':844})
  page.screenshot(path='/tmp/hangar-flight-mobile.png')
  for button in ['btn-camera','btn-dismount']:
    rect=page.locator('#'+button).bounding_box()
    assert rect['x']>=0 and rect['x']+rect['width']<=390
  page.keyboard.press('Escape')
  assert not errors,errors
  print('3D inspection, viewer cleanup, selected aircraft loaded before takeoff, and profile camera passed.',flush=True)
  b.close()
 http.shutdown();http.server_close()
