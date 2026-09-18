"""Menu-only checks for saved preferences, revisit, export, deletion and storage errors."""
import sys,tempfile,threading,json
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
  page.goto(f'http://localhost:{http.server_port}',wait_until='networkidle')
  page.locator('.flight-options summary').click()
  page.select_option('#weather','haze');page.uncheck('#air-motion')
  page.evaluate('''async()=>{const {Journal}=await import('/src/journey.js?v=fleet7');const j=new Journal();j.save({kind:'flight',name:'Manhattan',world:'google',start:{name:'Manhattan',lat:40.758,lng:-73.9855},target:{name:'Local tour',lat:.025,lng:.012},timeSec:30,distanceKm:1,path:[[0,0,7,0],[0,.001,50,0]]});}''')
  page.reload(wait_until='networkidle')
  assert page.locator('#weather').input_value()=='haze'
  assert not page.locator('#air-motion').is_checked()
  page.click('#btn-journal');assert page.locator('.journal-card svg').count()==1
  with page.expect_download() as download:
   page.get_by_role('button',name='Export journey',exact=True).click()
  assert json.loads(Path(download.value.path()).read_text())['world']=='google'
  page.get_by_role('button',name='Plan this flight',exact=True).click()
  assert page.locator('#selected-route').inner_text()=='Manhattan'
  assert page.locator('#route-end').input_value()=='local'
  page.click('#btn-journal');page.get_by_role('button',name='Delete entry',exact=True).click()
  assert page.locator('.journal-card').count()==0
  result=page.evaluate('''async()=>{const {Journal}=await import('/src/journey.js?v=fleet7');const j=new Journal(),old=Storage.prototype.setItem;let rejected=false;Storage.prototype.setItem=()=>{throw new DOMException('Full','QuotaExceededError')};try{j.save({kind:'flight',name:'Must not save'})}catch{rejected=true}finally{Storage.prototype.setItem=old}return rejected&&j.entries.length===0&&new Journal().entries.length===0;}''')
  assert result
  assert page.evaluate('''async()=>{const {trackPoints}=await import('/src/journey.js?v=fleet7');const a=trackPoints([[179.9,0],[-179.9,.01]]).split(/[ ,]/).map(Number),b=trackPoints([[-.1,0],[.1,.01]]).split(/[ ,]/).map(Number);return a.every((x,i)=>Math.abs(x-b[i])<.00001);}''')
  assert not errors,errors
  print('Preferences, route revisit, JSON export, entry deletion and storage-failure handling passed.')
  browser.close()
 http.shutdown();http.server_close()
