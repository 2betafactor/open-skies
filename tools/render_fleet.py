"""Render previews from the shipped GLBs through the game's Cesium renderer."""
import base64,sys,threading
from pathlib import Path
from playwright.sync_api import sync_playwright
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import server
http=server.ThreadingHTTPServer(('127.0.0.1',0),server.Handler)
threading.Thread(target=http.serve_forever,daemon=True).start()
html='''<!doctype html><html><head><link rel="stylesheet" href="https://unpkg.com/cesium@1.122/Build/Cesium/Widgets/widgets.css"><script>window.CESIUM_BASE_URL='https://unpkg.com/cesium@1.122/Build/Cesium/';</script><script src="https://unpkg.com/cesium@1.122/Build/Cesium/Cesium.js"></script><style>html,body,#scene{margin:0;width:100%;height:100%;overflow:hidden;background:transparent}</style></head><body><div id="scene"></div></body></html>'''
with sync_playwright() as p:
 browser=p.chromium.launch(headless=True,args=['--no-sandbox','--enable-unsafe-swiftshader'])
 page=browser.new_page(viewport={'width':640,'height':420},device_scale_factor=1)
 page.route('**/preview',lambda r:r.fulfill(content_type='text/html',body=html))
 page.goto(f'http://localhost:{http.server_port}/preview',wait_until='networkidle')
 page.evaluate('''()=>{const C=Cesium;C.Ion.defaultAccessToken=undefined;window.viewer=new C.Viewer('scene',{baseLayer:false,baseLayerPicker:false,geocoder:false,homeButton:false,sceneModePicker:false,navigationHelpButton:false,fullscreenButton:false,timeline:false,animation:false,infoBox:false,selectionIndicator:false,contextOptions:{webgl:{alpha:true,preserveDrawingBuffer:true}}});const s=viewer.scene;s.globe.show=false;s.skyBox.show=false;s.skyAtmosphere.show=false;s.sun.show=false;s.moon.show=false;s.backgroundColor=C.Color.TRANSPARENT;s.light=new C.DirectionalLight({direction:new C.Cartesian3(-.8,-.3,-.6),intensity:2.3});window.origin=C.Cartesian3.fromDegrees(0,0,1000);}''')
 for name in ['aerion','wayfarer']:
  page.evaluate('''name=>{viewer.entities.removeAll();window.model=viewer.entities.add({position:origin,orientation:Cesium.Transforms.headingPitchRollQuaternion(origin,new Cesium.HeadingPitchRoll(-Math.PI/2,0,0)),model:{uri:'/assets/'+name+'.glb',scale:1}});viewer.camera.lookAt(origin,new Cesium.HeadingPitchRange(name==='wayfarer'?.85:3.9,-.42,24));}''',name)
  page.wait_for_function('viewer.dataSourceDisplay.getBoundingSphere(model,false,new Cesium.BoundingSphere())===Cesium.BoundingSphereState.DONE',timeout=60000)
  page.wait_for_timeout(1500)
  result=page.evaluate("()=>{viewer.render();return viewer.scene.canvas.toDataURL('image/png').split(',')[1]}")
  (Path(server.BASE)/'assets'/f'{name}-preview.png').write_bytes(base64.b64decode(result))
  print('Rendered',name,flush=True)
 browser.close()
http.shutdown();http.server_close()
