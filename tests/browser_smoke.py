import sys, threading, tempfile
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import server
test_data = tempfile.TemporaryDirectory()
server.DATA=test_data.name
server.SCORES=server.DATA+'/scores.json'
http=server.ThreadingHTTPServer(('127.0.0.1',0),server.Handler)
threading.Thread(target=http.serve_forever,daemon=True).start()
base = f'http://127.0.0.1:{http.server_port}'
from playwright.sync_api import sync_playwright
with sync_playwright() as p:
 b=p.chromium.launch(headless=True,args=['--no-sandbox','--enable-unsafe-swiftshader'])
 page=b.new_page(viewport={'width':960,'height':720})
 errors=[];google=[]
 page.on('pageerror',lambda e:errors.append(str(e)))
 page.route('**/*google*',lambda r:(google.append(r.request.url),r.abort()))
 # Request routing disables browser caching; retain the large engine across replay reload.
 engine_cache={}
 def engine_route(route):
  if 'body' not in engine_cache:
   response=route.fetch()
   engine_cache['body']=response.body()
  route.fulfill(status=200,content_type='application/javascript',body=engine_cache['body'])
 page.route('**/Cesium.js',engine_route)
 page.goto(base,wait_until='networkidle')
 assert page.locator('[data-world=google]').get_attribute('aria-pressed') == 'true'
 assert page.locator('#place-input').is_visible()
 assert page.locator('#presets .preset-card').count() == 8
 page.click('[data-world=sandbox]')
 result=page.evaluate('''async () => {
  const {ensureEngine}=await import('/src/engine.js');await ensureEngine();
  const {Sandbox}=await import('/src/sandbox.js');
  const entities=new Cesium.EntityCollection();
  const s=new Sandbox({entities});
  for(const g of s.gates) s.status(g.center);
  const complete=s.status(s.gates[7].center);
  s.reset(); const reset=s.next===0;
  s.destroy();return {complete,reset,clean:entities.values.length===0};
 }''')
 print('course',result,flush=True)
 assert result['reset'] and result['clean'] and 'complete' in result['complete']
 flight=page.request.post(base+'/api/scores',data={'world':'sandbox','vehicle':'swift','path':[[0,0,350,0],[0,.001,350,0],[0,.002,350,0]],'distanceKm':0.2}).json()
 page.goto(base+'/?flight='+flight['id'])
 page.wait_for_function("!document.querySelector('#screen-loading').classList.contains('active')")
 page.wait_for_function("document.querySelector('#screen-landing').classList.contains('active')",timeout=60000)
 print('sandbox shared replay finished',flush=True)
 page.set_viewport_size({'width':390,'height':844})
 page.screenshot(path='/tmp/game-mobile.png')
 page.click('[data-world="google"]')
 page.wait_for_timeout(500)
 page.click('[data-world="sandbox"]')
 assert page.locator('#btn-sandbox').is_visible()
 print('mobile and mode switch OK; errors',errors, 'Google requests (default Maps mode only)',len(google),flush=True)
 assert not errors
 b.close()

http.shutdown()
http.server_close()
test_data.cleanup()
