"""Render menu previews from the actual aircraft GLBs with the game's renderer.
Requires Python Playwright + Chromium. Output is a transparent PNG, not concept art.
"""
import sys,threading
from pathlib import Path
from playwright.sync_api import sync_playwright
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
import server
http=server.ThreadingHTTPServer(('127.0.0.1',0),server.Handler)
threading.Thread(target=http.serve_forever,daemon=True).start()
with sync_playwright() as p:
    browser=p.chromium.launch(headless=True,args=['--no-sandbox','--enable-unsafe-swiftshader'])
    page=browser.new_page(viewport={'width':1100,'height':700})
    page.route('**/*google*',lambda route:route.abort())
    page.goto(f'http://localhost:{http.server_port}',wait_until='networkidle')
    page.evaluate('''async () => {
      const {ensureEngine}=await import('/src/engine.js');await ensureEngine();
      document.body.innerHTML='<div id="render" style="position:fixed;inset:0"></div>';
      const {Hangar}=await import('/src/hangar.js'); window.hangar=new Hangar('render');hangar.viewer.resolutionScale=2;
    }''')
    for name in ['skylark','swift','plane']:
        png=page.evaluate('''async name => {
          const {VEHICLES}=await import('/src/vehicles.js');
          await hangar.show(VEHICLES.find(v=>v.id===name));
          hangar.viewer.render();
          const source=hangar.viewer.canvas;
          const snapshot=document.createElement('canvas');snapshot.width=source.width;snapshot.height=source.height;
          const context=snapshot.getContext('2d');context.drawImage(source,0,0);
          const pixels=context.getImageData(0,0,snapshot.width,snapshot.height).data;
          let x0=snapshot.width,y0=snapshot.height,x1=0,y1=0;
          for(let y=0;y<snapshot.height;y++)for(let x=0;x<snapshot.width;x++)if(pixels[(y*snapshot.width+x)*4+3]>20){x0=Math.min(x0,x);y0=Math.min(y0,y);x1=Math.max(x1,x);y1=Math.max(y1,y);}
          const output=document.createElement('canvas');output.width=x1-x0+80;output.height=y1-y0+80;
          output.getContext('2d').drawImage(snapshot,x0,y0,x1-x0+1,y1-y0+1,40,40,x1-x0+1,y1-y0+1);
          return output.toDataURL('image/png').split(',')[1];
        }''',name)
        import base64
        dest=ROOT/'assets'/f'{name}-preview.png'
        dest.write_bytes(base64.b64decode(png));print(dest.name,dest.stat().st_size,flush=True)
    browser.close()
http.shutdown()
