"""Build original, material-batched glTF aircraft. Metres; builder +X nose/+Y up; exported glTF +Z forward/+Y up."""
import json,math,struct
from pathlib import Path
from collections import defaultdict
ROOT=Path(__file__).resolve().parents[1]
class Model:
 def __init__(self):self.parts=defaultdict(lambda:[[],[]]);self.materials=[]
 def mat(self,name,color,metal=0,rough=.4,emission=None):
  m={'name':name,'pbrMetallicRoughness':{'baseColorFactor':color+[1],'metallicFactor':metal,'roughnessFactor':rough},'doubleSided':True}
  if emission:m['emissiveFactor']=emission
  self.materials.append(m);return len(self.materials)-1
 def mesh(self,mat,verts,tris):
  v,t=self.parts[mat];offset=len(v);v.extend(verts);t.extend(tuple(i+offset for i in tri) for tri in tris)
 def rings(self,mat,rings,close=False):
  n=len(rings[0]);v=[p for ring in rings for p in ring];t=[]
  for j in range(len(rings)-1):
   for i in range(n):
    a=j*n+i;b=j*n+(i+1)%n;c=(j+1)*n+i;d=(j+1)*n+(i+1)%n;t.extend([(a,c,b),(b,c,d)])
  if close:
   for j,flip in [(0,False),(len(rings)-1,True)]:
    center=tuple(sum(p[k] for p in rings[j])/n for k in range(3));idx=len(v);v.append(center)
    for i in range(n):t.append((idx,j*n+(i+1)%n,j*n+i) if flip else (idx,j*n+i,j*n+(i+1)%n))
  self.mesh(mat,v,t)
 def body(self,mat,stations,cy=0,cz=0,n=40,close=True):
  self.rings(mat,[[(x,cy+y+ry*math.cos(i*2*math.pi/n),cz+rz*math.sin(i*2*math.pi/n)) for i in range(n)] for x,y,ry,rz in reversed(stations)],close)
 def ellipsoid(self,mat,center,size,n=20,m=10):
  rings=[]
  for j in range(m+1):
   a=math.pi*(.0001+(1-.0002)*j/m)
   rings.append([(center[0]+size[0]*math.cos(a),center[1]+size[1]*math.sin(a)*math.cos(i*2*math.pi/n),center[2]+size[2]*math.sin(a)*math.sin(i*2*math.pi/n)) for i in range(n)])
  self.rings(mat,rings,True)
 def foil(self,mat,sections,side=1,vertical=False):
  rings=[];n=36
  for lead,chord,span,height,thick in sections:
   ring=[]
   for i in range(n):
    a=2*math.pi*i/n;u=(1-math.cos(a))/2
    yt=5*thick*(.2969*math.sqrt(u)-.126*u-.3516*u*u+.2843*u**3-.1036*u**4)
    y=height+(1 if i<n/2 else -1)*yt*chord
    ring.append((lead-u*chord,span,y) if vertical else (lead-u*chord,y,side*span))
   rings.append(list(reversed(ring)) if side>0 and not vertical else ring)
  self.rings(mat,rings,True)
 def patch(self,mat,points):self.mesh(mat,points,[(0,i,i+1) for i in range(1,len(points)-1)])
 def save(self,path):
  data=bytearray();views=[];access=[];primitives=[]
  def acc(values,kind,fmt,ctype):
   while len(data)%4:data.append(0)
   flat=[x for v in values for x in v] if kind!='SCALAR' else values
   raw=struct.pack('<'+fmt*len(flat),*flat);view=len(views);views.append({'buffer':0,'byteOffset':len(data),'byteLength':len(raw)});data.extend(raw)
   d={'bufferView':view,'componentType':ctype,'count':len(values),'type':kind}
   if kind=='VEC3':d.update(min=[min(v[i] for v in values) for i in range(3)],max=[max(v[i] for v in values) for i in range(3)])
   access.append(d);return len(access)-1
  for mat,(verts,tris) in self.parts.items():
   # Cesium adapts glTF +Z forward to its local +X forward.
   verts=[(-z,y,x) for x,y,z in verts]
   normals=[[0,0,0] for _ in verts]
   for a,b,c in tris:
    u=[verts[b][i]-verts[a][i] for i in range(3)];v=[verts[c][i]-verts[a][i] for i in range(3)];n=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]]
    for idx in [a,b,c]:
     for k in range(3):normals[idx][k]+=n[k]
   normals=[[x/(math.sqrt(sum(y*y for y in n)) or 1) for x in n] for n in normals]
   primitives.append({'attributes':{'POSITION':acc(verts,'VEC3','f',5126),'NORMAL':acc(normals,'VEC3','f',5126)},'indices':acc([i for t in tris for i in t],'SCALAR','I',5125),'material':mat})
  gltf={'asset':{'version':'2.0','generator':'Open Skies original fleet builder'},'scene':0,'scenes':[{'nodes':[0]}],'nodes':[{'mesh':0,'name':path.stem,'extras':{'forwardAxis':'+Z','upAxis':'+Y'}}],'meshes':[{'primitives':primitives}],'materials':self.materials,'buffers':[{'byteLength':len(data)}],'bufferViews':views,'accessors':access}
  js=json.dumps(gltf,separators=(',',':')).encode();js+=b' '*((-len(js))%4);data+=b'\0'*((-len(data))%4)
  path.write_bytes(struct.pack('<III',0x46546c67,2,28+len(js)+len(data))+struct.pack('<II',len(js),0x4e4f534a)+js+struct.pack('<II',len(data),0x004e4942)+data)
  print(path.name,len(data),'bytes',sum(len(t) for v,t in self.parts.values()),'triangles',len(primitives),'draw batches')

def jet():
 m=Model();white=m.mat('Pearl fuselage',[.82,.86,.88],.25,.28);navy=m.mat('Midnight blue livery',[.025,.095,.14],.35,.3);glass=m.mat('Cockpit and cabin glass',[.025,.07,.10],.65,.13);metal=m.mat('Brushed titanium',[.42,.48,.5],.85,.27);dark=m.mat('Intake interiors',[.025,.028,.03],.25,.6);red=m.mat('Port navigation light',[.8,.025,.015],0,.3,[1,0,0]);green=m.mat('Starboard navigation light',[.02,.7,.2],0,.3,[0,1,.1])
 stations=[(-8,0,.035,.035),(-7.5,0,.20,.24),(-6.5,0,.38,.45),(-5.5,0,.60,.65),(-4.5,0,.79,.82),(-3,0,.87,.90),(0,0,.88,.91),(3,0,.87,.89),(4,0,.79,.83),(4.8,-.02,.68,.74),(5.5,-.09,.52,.59),(6.2,-.18,.34,.40),(6.7,-.23,.14,.18),(7,-.24,.015,.015)]
 m.body(white,stations)
 # Painted lower fuselage and long thin side cheatlines follow the same loft.
 for side in [-1,1]:
  rows=[]
  for x,y,ry,rz in stations[1:-1]:rows.append([(x,y+(ry+.008)*math.cos(a),(rz+.008)*math.sin(a)) for a in [side*(1.55+i*.13) for i in range(10)]])
  # Open ribbon, not closed rings, to avoid spanning the body.
  v=[p for r in rows for p in r];t=[]
  for j in range(len(rows)-1):
   for i in range(9):a=j*10+i;t.extend([(a,a+10,a+1),(a+1,a+10,a+11)])
  m.mesh(navy,v,t)
  m.foil(white,[(1.6,4.4,.75,-.35,.11),(.1,3.1,3,-.15,.10),(-2.1,1.9,6.5,.15,.09),(-3.5,1.05,8,.36,.08)],side)
  m.foil(navy,[(-3.5,1.05,8,.36,.08),(-3.8,.78,8.12,1.35,.08),(-4.05,.35,8.2,1.9,.08)],side)
  m.foil(white,[(-5.5,2.6,.3,1.15,.10),(-6.7,1.25,2.8,1.36,.09),(-7.2,.75,3.7,1.45,.08)],side)
  m.foil(metal,[(-2.1,1.5,1,.25,.12),(-3,1.2,1.6,.45,.12)],side)
  # Nacelle barrel, rolled intake lip, recessed face and visible fan blades.
  z=side*1.8
  m.body(white,[(-5.7,.38,.38,.38),(-5.1,.38,.59,.59),(-3.7,.38,.67,.67),(-2.8,.38,.64,.64)],cz=z,close=False)
  m.body(metal,[(-2.84,.38,.645,.645),(-2.73,.38,.62,.62),(-2.79,.38,.54,.54),(-3.03,.38,.53,.53)],cz=z,close=False)
  m.body(dark,[(-3.04,.38,.525,.525),(-3.1,.38,.52,.52)],cz=z)
  for i in range(20):
   a=i*math.pi/10;b=a+.16
   m.patch(metal,[(-3.025,.38+.13*math.cos(a),z+.13*math.sin(a)),(-3.04,.38+.49*math.cos(a+.24),z+.49*math.sin(a+.24)),(-3.04,.38+.49*math.cos(b+.24),z+.49*math.sin(b+.24)),(-3.025,.38+.13*math.cos(b),z+.13*math.sin(b))])
  m.ellipsoid(metal,(-2.99,.38,z),(.18,.13,.13))
  m.body(dark,[(-5.74,.38,.32,.32),(-5.85,.38,.27,.27)],cz=z)
  for x in [-3,-2.1,-1.2,-.3,.6,1.5,2.4,3.3]:
   m.ellipsoid(metal,(x,.29,side*.855),(.205,.26,.054),16,8);m.ellipsoid(glass,(x+.003,.29,side*.885),(.171,.224,.04),16,8)
  # Glazing follows the curved loft; flat quads intersect a round fuselage.
  for lo,hi in [(.22,.74),(.80,1.3)]:
   verts=[];tris=[];nx=10;na=8
   for j in range(nx):
    x=4.22+(5.72-4.22)*j/(nx-1)
    k=next(k for k in range(len(stations)-1) if stations[k][0]<=x<=stations[k+1][0])
    aa,bb=stations[k],stations[k+1];f=(x-aa[0])/(bb[0]-aa[0]);y,ry,rz=[aa[k]+(bb[k]-aa[k])*f for k in [1,2,3]]
    for i in range(na):
     angle=side*(lo+(hi-lo)*i/(na-1));verts.append((x,y+(ry+.018)*math.cos(angle),(rz+.018)*math.sin(angle)))
   for j in range(nx-1):
    for i in range(na-1):a=j*na+i;tris.extend([(a,a+1,a+na),(a+1,a+na+1,a+na)])
   m.mesh(glass,verts,tris)
  m.ellipsoid(red if side==-1 else green,(-3.5,.4,side*8.1),(.12,.08,.08),12,6)
 m.foil(navy,[(-5.1,2.8,.4,0,.11),(-6.6,1.55,3.5,0,.09),(-7.1,.9,4.1,0,.08)],vertical=True)
 # Fairing at the wing/body joint and dorsal antenna.
 m.ellipsoid(white,(-.8,-.55,0),(3.0,.38,1.13));m.foil(metal,[(1.2,.5,.8,0,.1),(1,.3,1.22,0,.1)],vertical=True)
 m.save(ROOT/'assets/aerion.glb')

def ship():
 m=Model();hull=m.mat('Ceramic silver',[.48,.56,.65],.7,.3);edge=m.mat('Graphite armor',[.045,.07,.11],.65,.32);glass=m.mat('Smoked canopy',[.018,.065,.095],.8,.11);metal=m.mat('Engine alloy',[.26,.29,.35],.85,.32);glow=m.mat('Ion emitters',[.02,.55,.85],.1,.3,[.05,.8,1]);amber=m.mat('Warning markings',[.95,.36,.045],.3,.4)
 m.body(hull,[(-6.5,0,.35,.9),(-5,0,.65,1.3),(-2,0,.8,1.5),(1,0,.65,1.25),(4,-.1,.35,.65),(6,-.22,.025,.025)],n=32)
 m.ellipsoid(edge,(.7,.51,0),(2.7,.65,.85));m.ellipsoid(glass,(.85,.67,0),(2.35,.55,.7))
 for side in [-1,1]:
  m.foil(edge,[(1,4.8,1,0,.13),(-3.8,2.4,5.5,-.25,.11),(-5.8,1,6.8,-.3,.1)],side)
  m.foil(hull,[(.4,3.3,1.3,.08,.12),(-3.5,1.6,4.8,-.10,.1),(-5.4,.65,6.1,-.2,.09)],side)
  m.foil(edge,[(-3.8,2.4,1.7,.4,.10),(-5.4,1.4,2.2,2.2,.09)],side)
  z=side*2.0
  m.body(edge,[(-6.8,-.12,.62,.62),(-5.7,-.12,.7,.7),(-3.1,-.12,.55,.55),(-1.6,-.12,.16,.16)],cz=z,n=32)
  m.body(metal,[(-6.85,-.12,.61,.61),(-7,-.12,.55,.55),(-7.02,-.12,.43,.43)],cz=z,n=32)
  m.body(glow,[(-7.04,-.12,.42,.42),(-7.1,-.12,.34,.34)],cz=z,n=32)
  m.ellipsoid(glow,(-7.25,-.12,z),(.3,.28,.28),20,8)
  m.patch(amber,[(-2.7,.12,side*3),(-3.15,.12,side*3.6),(-3.5,.12,side*3.6),(-3.05,.12,side*3)])
  m.ellipsoid(glow,(-5.35,-.1,side*6.1),(.22,.07,.07),12,6)
 m.save(ROOT/'assets/wayfarer.glb')

def cyber():
 # A compact cyberpunk interceptor: faceted black body, swept delta wings,
 # smoked canopy and emissive cyan/magenta edge lighting.
 m=Model();body=m.mat('Obsidian composite',[.018,.025,.045],.72,.24);panel=m.mat('Violet armor',[.12,.035,.22],.72,.28);glass=m.mat('Smoked canopy',[.015,.035,.08],.9,.08);metal=m.mat('Gunmetal',[.18,.2,.27],.9,.22);cyan=m.mat('Cyan neon',[.01,.45,.8],.15,.2,[.01,.8,1]);pink=m.mat('Magenta neon',[.7,.015,.35],.15,.2,[1,.02,.38]);amber=m.mat('Amber marker',[.95,.28,.03],.2,.3,[1,.1,.01])
 stations=[(-6.8,0,.04,.05),(-6.2,0,.25,.28),(-4.7,0,.48,.5),(-2.2,0,.63,.62),(1.2,0,.58,.56),(3.6,-.08,.4,.4),(5.7,-.2,.08,.1),(6.2,-.23,.02,.02)]
 m.body(body,stations,n=8)
 m.ellipsoid(panel,(-.2,.22,0),(2.8,.48,.54),16,8)
 m.ellipsoid(glass,(1.25,.48,0),(1.85,.38,.42),16,8)
 for side in [-1,1]:
  # Broad swept delta wing and a thin neon leading edge.
  m.foil(panel,[(2.4,3.8,1.0,.08,.1),(-1.6,2.2,5.8,.0,.08),(-4.7,.75,7.5,-.18,.06)],side)
  m.foil(cyan,[(2.35,.32,1.0,.1,.035),(-1.55,.18,5.7,.02,.03),(-4.65,.08,7.35,-.16,.025)],side)
  # Twin rear nacelles with glowing exhaust rings.
  z=side*1.45
  m.body(metal,[(-5.4,-.05,.3,.3),(-4.3,-.05,.42,.42),(-2.4,-.05,.38,.38),(-1.7,-.05,.18,.18)],cz=z,n=16)
  m.body(body,[(-5.48,-.05,.29,.29),(-5.62,-.05,.22,.22)],cz=z,n=16)
  m.body(pink,[(-5.65,-.05,.21,.21),(-5.74,-.05,.13,.13)],cz=z,n=16)
  m.ellipsoid(cyan,(-5.9,-.05,z),(.25,.16,.16),12,6)
  m.ellipsoid(amber,(3.9,.08,side*2.7),(.11,.06,.06),10,5)
 # Dorsal fin and tail light.
 m.foil(panel,[(-2.1,.9,.35,0,.07),(-3.8,.3,1.25,0,.05),(-4.6,.12,1.45,0,.04)],vertical=True)
 m.ellipsoid(pink,(-4.85,.06,0),(.12,.07,.07),10,5)
 m.save(ROOT/'assets/cyberwing.glb')
if __name__=='__main__':jet();ship();cyber()
