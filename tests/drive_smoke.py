"""Run with Python Playwright and Chromium installed. Uses temporary server data."""
import sys
import tempfile
import threading
from pathlib import Path
from playwright.sync_api import sync_playwright
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import server

with tempfile.TemporaryDirectory() as data:
    server.DATA = data
    server.SCORES = str(Path(data) / 'scores.json')
    http = server.ThreadingHTTPServer(('127.0.0.1', 0), server.Handler)
    threading.Thread(target=http.serve_forever, daemon=True).start()
    base = f'http://127.0.0.1:{http.server_port}'
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True, args=['--no-sandbox', '--enable-unsafe-swiftshader'])
        page = browser.new_page(viewport={'width': 1100, 'height': 760}, has_touch=True)
        errors, google = [], []
        page.on('pageerror', lambda error: errors.append(str(error)))
        page.route('**/*google*', lambda route: (google.append(route.request.url), route.abort()))
        page.goto(base + '/drive.html', wait_until='networkidle')
        page.wait_for_function("!document.getElementById('start').disabled")
        checks = page.evaluate('''async () => {
          const {DrivePhysics,collides,onRoad,ROUTE}=await import('/src/drive-physics.js');
          const result={};
          const p=new DrivePhysics();
          for(let i=0;i<120;i++)p.step(1/60,{forward:true});
          result.acceleration=p.speed>10 && p.y>-300;
          const forward=p.speed;
          for(let i=0;i<20;i++)p.step(1/60,{brake:true});
          result.braking=p.speed<forward;
          for(let i=0;i<240;i++)p.step(1/60,{reverse:true});
          result.reverse=p.speed<0;
          p.reset();p.speed=10;const before=p.heading;p.step(.05,{right:true});
          result.steering=p.heading>before;
          const obstacle={x:8,y:-306,w:8,d:2};
          const c=new DrivePhysics([obstacle]);
          for(let i=0;i<180;i++)c.step(1/60,{forward:true});
          result.collision=c.hits>0 && c.y<-308;
          result.boundary=collides(446,0,[]) && !collides(0,0,[]);
          result.roads=onRoad(8,90) && !onRoad(90,90);
          const r=new DrivePhysics();
          for(const point of ROUTE){[r.x,r.y]=point;r.step(.01,{});}
          result.lap=r.laps===1 && r.checkpoint===0 && r.bestLap>0;
          r.recover();result.recovery=!collides(r.x,r.y,[]);
          r.reset();result.restart=r.laps===0 && r.elapsed===0 && r.distance===0;
          return result;
        }''')
        print('Physics checks:', checks, flush=True)
        assert all(checks.values()), checks
        page.click('#start')
        page.wait_for_timeout(3000)
        page.keyboard.down('w')
        page.wait_for_function("Number(document.getElementById('speed').textContent)>0", timeout=30000)
        page.keyboard.up('w')
        page.screenshot(path='/tmp/street-run-desktop.png')
        page.keyboard.press('Escape')
        assert page.locator('#menu').is_visible()
        before = page.locator('#trip').inner_text()
        page.wait_for_timeout(250)
        assert page.locator('#trip').inner_text() == before
        page.click('#restart')
        assert page.locator('#speed').inner_text() == '0'
        page.keyboard.press('p')
        page.set_viewport_size({'width':390,'height':844})
        page.screenshot(path='/tmp/street-run-mobile.png')
        assert page.locator('#start').is_visible()
        page.click('#start')
        gas=page.locator('[data-control="forward"]').bounding_box()
        page.mouse.move(gas['x']+gas['width']/2,gas['y']+gas['height']/2)
        page.mouse.down()
        page.wait_for_function("Number(document.getElementById('speed').textContent)>0", timeout=30000)
        page.mouse.up()
        assert not page.locator('[data-control="forward"]').evaluate("e => e.classList.contains('held')")
        page.screenshot(path='/tmp/street-run-mobile-driving.png')
        assert not google, google
        assert not errors, errors
        page.goto(base, wait_until='networkidle')
        assert page.locator('[data-world="google"]').get_attribute('aria-pressed') == 'true'
        assert page.locator('.game-picker a[href="/drive.html"]').is_visible()
        print('Driving UI, pause/restart, mobile layout, no-Google driving, and flight selector passed.', flush=True)
        browser.close()
    http.shutdown()
    http.server_close()
