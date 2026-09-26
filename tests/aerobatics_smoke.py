"""Aerobatic flight physics: real loops and rolls, inverted flight with no
forced auto-level, recovery, beginner stabilisation and stunt completion.
Runs the actual flight engine (real Cesium math) headlessly at a fixed step."""
import sys,tempfile,threading
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
  page=b.new_page();errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
  page.route('**/*google*',lambda r:r.abort())
  page.goto(f'http://localhost:{http.server_port}',wait_until='networkidle')
  result=page.evaluate('''async()=>{
   const {ensureEngine}=await import('/src/engine.js?v=fleet7');await ensureEngine();
   const {Flight}=await import('/src/flight.js?v=fleet7');
   const C=Cesium,D=Math.PI/180;
   const mk=()=>{const f=new Flight('none');
     f.viewer={scene:{sampleHeightSupported:false}};
     f.position=C.Cartesian3.fromDegrees(2,45,1500);
     f._graceUntil=performance.now()+1e9;
     f.alt=1500;f.heading=0;f.pitch=0;f.roll=0;f.speed=25;f.throttle=.6;
     return f;};
   const run=(f,secs)=>{for(let i=0;i<secs*120;i++)f._step(1/120);};
   const out={};

   // 1) Loop: hold full pitch-up in aerobatic — the plane must climb, pass
   // through inverted, dive down the back side, and keep looping (repeatedly).
   {const f=mk();f.setAssist('aerobatic');f.controls.pitch=1;
    let sawClimb=false,sawInverted=false,dives=0,inDive=false,maxAlt=0,finite=true;
    for(let i=0;i<20*120;i++){f._step(1/120);
      if(f.pitch>75*D)sawClimb=true;
      if(Math.abs(Math.abs(f.roll)-Math.PI)<.4)sawInverted=true;
      const dive=f.pitch<-75*D;
      if(dive&&!inDive)dives++;
      inDive=dive;
      maxAlt=Math.max(maxAlt,f.alt);
      finite=finite&&Number.isFinite(f.speed)&&Number.isFinite(f.alt)&&Number.isFinite(f.heading);}
    out.loop={sawClimb,sawInverted,repeated:dives>=2,climbed:maxAlt>1560,finite};}

   // 2) Inverted flight holds (no auto-level), then LEVEL recovers.
   {const f=mk();f.setAssist('aerobatic');f.controls.roll=1;
    let t=0;while(Math.abs(f.roll)<2.5&&t<6*120){f._step(1/120);t++;}
    f.controls.roll=0;run(f,1.5); // let rotational inertia decay
    const roll0=f.roll;run(f,3);
    let drift=f.roll-roll0;while(drift>Math.PI)drift-=2*Math.PI;while(drift<-Math.PI)drift+=2*Math.PI;
    const held=Math.abs(roll0)>1.9&&Math.abs(drift)<.25; // stays inverted, wherever it stopped
    f.recover();run(f,3);
    out.inverted={reached:t<6*120,held,recovered:Math.abs(f.roll)<.3&&Math.abs(f.pitch)<.3};}

   // 3) Beginner: hands-off auto-level, and full stick never goes inverted.
   {const f=mk();f.roll=.6;f.pitch=.4;run(f,3);
    const leveled=Math.abs(f.roll)<.05&&Math.abs(f.pitch)<.05;
    f.controls.pitch=1;let maxP=0,maxR=0;
    for(let i=0;i<10*120;i++){f._step(1/120);maxP=Math.max(maxP,f.pitch);maxR=Math.max(maxR,Math.abs(f.roll));}
    out.beginner={leveled,clamped:maxP<71*D,upright:maxR<.3};}

   // 4) R-key loop stunt completes as a REAL rotation even in beginner mode,
   // then the springs bring the plane back to level.
   {const f=mk();f.startFlip('backflip');
    let sawInverted=false;
    for(let i=0;i<6*120;i++){f._step(1/120);
      if(Math.abs(Math.abs(f.roll)-Math.PI)<.4)sawInverted=true;}
    out.stuntLoop={sawInverted,done:f._stuntRemaining===0,leveled:Math.abs(f.roll)<.2&&Math.abs(f.pitch)<.2};}

   // 5) T-key barrel roll passes through inverted bank and completes.
   {const f=mk();f.setAssist('aerobatic');f.startFlip('barrel');
    let sawInvertedBank=false;
    for(let i=0;i<5*120;i++){f._step(1/120);
      if(Math.abs(Math.abs(f.roll)-Math.PI)<.5)sawInvertedBank=true;}
    out.barrel={sawInvertedBank,done:f._stuntRemaining===0};}

   // 6) Aerobatic straight flight holds its heading and attitude hands-off;
   // a held bank keeps turning (coordinated coupling) without self-righting.
   {const f=mk();f.setAssist('aerobatic');run(f,5);
    const straight=Math.abs(f.heading)<.05&&Math.abs(f.pitch)<.06&&Math.abs(f.roll)<.05;
    f.controls.roll=1;let t=0;while(f.roll<40*D&&t<4*120){f._step(1/120);t++;}
    f.controls.roll=0;const h0=f.heading;run(f,5);
    const bankHolds=f.roll>25*D;
    let dh=f.heading-h0;while(dh<-Math.PI)dh+=2*Math.PI;while(dh>Math.PI)dh-=2*Math.PI;
    out.turn={straight,bankHolds,turns:dh>.25};}
   return out;}''')
  print(result)
  flat=[];[flat.extend([f'{g}.{k}={v}' for k,v in checks.items() if v is not True]) for g,checks in result.items()]
  assert not flat,flat
  assert not errors,errors
  print('Aerobatics: loops fly through inverted and repeat; inverted flight holds; recovery, beginner assists and stunts all behave.')
  b.close()
 http.shutdown();http.server_close()
