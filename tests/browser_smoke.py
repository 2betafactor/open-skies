"""Retired replay and archived journal handling, without loading scenery."""
import sys,threading,tempfile
from pathlib import Path
from playwright.sync_api import sync_playwright
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import server
with tempfile.TemporaryDirectory() as data:
 server.DATA=data;server.SCORES=data+'/scores.json'
 http=server.ThreadingHTTPServer(('127.0.0.1',0),server.Handler)
 threading.Thread(target=http.serve_forever,daemon=True).start()
 with sync_playwright() as p:
  browser=p.chromium.launch(headless=True,args=['--no-sandbox'])
  page=browser.new_page();errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
  page.route('**/*google*',lambda r:r.abort())
  page.route('**/api/flight?*',lambda r:r.fulfill(json={'world':'sandbox','path':[[0,0,350,0],[0,.001,350,0]]}))
  engine=[];page.route('**/Cesium.js',lambda r:(engine.append(r.request.url),r.abort()))
  page.goto(f'http://localhost:{http.server_port}/?flight=legacy',wait_until='networkidle')
  assert page.locator('#screen-landing').is_visible()
  assert 'retired environment' in page.locator('#landing-status').inner_text()
  assert not engine
  page.evaluate('''async()=>{const {Journal}=await import('/src/journey.js?v=fleet7');new Journal().save({kind:'flight',name:'Old practice flight',world:'sandbox',start:{lat:0,lng:0,name:'Old practice flight'},path:[[0,0,350,0],[0,.001,350,0]]});const {Flight}=await import('/src/flight.js?v=fleet7');let rejected=false;try{await new Flight('unused').init(null,'sandbox')}catch{rejected=true}if(!rejected)throw Error('Retired world accepted');}''')
  page.click('#btn-journal')
  assert 'Archived flight' in page.locator('#journal-entries').inner_text()
  assert page.get_by_role('button',name='Plan this flight',exact=True).count()==0
  assert page.get_by_role('button',name='Export journey',exact=True).count()==1
  assert not errors,errors
  print('Retired replay returns to menu before loading the engine; archived entries remain exportable without a launch action.')
  browser.close()
 http.shutdown();http.server_close()
