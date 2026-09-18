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
  assert page.locator('.aircraft-option').count()==3
  assert page.locator('[data-aircraft=plane]').get_attribute('aria-pressed')=='true'
  page.click('[data-aircraft=spaceship]')
  assert page.locator('[data-aircraft=spaceship]').get_attribute('aria-pressed')=='true'
  assert page.locator('[data-world], #sandbox-panel, #runway-start').count()==0
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
  assert page.locator('[data-aircraft=spaceship]').get_attribute('aria-pressed')=='true'
  assert page.locator('.aircraft-option img').evaluate_all('images=>images.every(i=>i.complete&&i.naturalWidth>300)')
  page.set_viewport_size({'width':390,'height':844})
  assert page.evaluate('document.querySelector("#screen-landing").scrollWidth<=innerWidth')
  page.screenshot(path='/tmp/navigation-mobile.png')
  print('Home works without the 3D engine; two aircraft and explicit destination selection passed.',flush=True)
  assert 'Sandbox' not in page.locator('body').inner_text()
  assert not errors,errors
  b.close()
 http.shutdown();http.server_close()
