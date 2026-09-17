"""Build original, self-contained glTF aircraft. Python standard library only.
Coordinate convention: +X nose, +Y up, +Z right. Dimensions are metres.
Run from any directory; outputs are deterministic and contain no external textures.
"""
import json
import math
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class Aircraft:
    def __init__(self, name, color):
        self.binary = bytearray()
        self.parts = []
        self.doc = dict(asset={'version': '2.0', 'generator': 'Open Skies aircraft workshop'},
                        scene=0, scenes=[{'nodes': []}], nodes=[], meshes=[], accessors=[], bufferViews=[],
                        materials=[], buffers=[])
        for label, rgba, metal, rough in [
            ('Ivory enamel', [.93, .945, .94, 1], .05, .28),
            ('Livery', color, .25, .3),
            ('Smoked blue glazing', [.035, .105, .16, 1], .3, .12),
            ('Graphite rubber', [.035, .045, .05, 1], .0, .9),
            ('Brushed metal', [.55, .61, .64, 1], .8, .3),
            ('Amber tips', [1, .61, .12, 1], .1, .35),
        ]:
            self.doc['materials'].append({'name': label, 'doubleSided': False, 'pbrMetallicRoughness': {
                'baseColorFactor': rgba, 'metallicFactor': metal, 'roughnessFactor': rough}})
        self.name = name

    def accessor(self, rows, kind, bounds=False):
        while len(self.binary) % 4:
            self.binary.append(0)
        flat = [v for row in rows for v in row]
        data = struct.pack('<' + 'f' * len(flat), *flat)
        view = len(self.doc['bufferViews'])
        self.doc['bufferViews'].append({'buffer': 0, 'byteOffset': len(self.binary), 'byteLength': len(data)})
        self.binary.extend(data)
        value = {'bufferView': view, 'componentType': 5126, 'count': len(rows), 'type': kind}
        if bounds:
            value['min'] = [min(r[i] for r in rows) for i in range(len(rows[0]))]
            value['max'] = [max(r[i] for r in rows) for i in range(len(rows[0]))]
        self.doc['accessors'].append(value)
        return len(self.doc['accessors']) - 1

    def mesh(self, name, vertices, faces, material, translation=None, smooth=False):
        triangles=[]
        for face in faces:
            triangles.extend((face[0],face[i],face[i+1]) for i in range(1,len(face)-1))
        normals=[[0.,0.,0.] for _ in vertices]
        face_normals=[]
        for tri in triangles:
            a,b,c=[vertices[j] for j in tri]
            u=[b[j]-a[j] for j in range(3)];v=[c[j]-a[j] for j in range(3)]
            n=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]]
            face_normals.append(n)
            for i in tri:
                for j in range(3):normals[i][j]+=n[j]
        unit=lambda n: [v/(math.sqrt(sum(x*x for x in n)) or 1) for v in n]
        positions=[];out_normals=[];indices=[];lookup={}
        for tri,normal in zip(triangles,face_normals):
            for index in tri:
                position=vertices[index];n=unit(normals[index] if smooth else normal)
                key=tuple(position)+tuple(round(x,6) for x in n)
                if key not in lookup:
                    lookup[key]=len(positions);positions.append(position);out_normals.append(n)
                indices.append(lookup[key])
        self.parts.append((name,positions,out_normals,indices,material,translation))
        return len(self.parts)-1

    def box(self, name, center, size, mat):
        vertices = [[center[i]+size[i]*sign[i]/2 for i in range(3)] for sign in
                    [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]]
        return self.mesh(name, vertices, [(0,3,2,1),(4,5,6,7),(0,1,5,4),(3,7,6,2),(0,4,7,3),(1,2,6,5)],mat)

    def hull(self, name, rings, mat, segments=32):
        vertices = []
        for x, y, ry, rz in rings:
            vertices.extend((x, y+ry*math.cos(i*math.tau/segments), rz*math.sin(i*math.tau/segments)) for i in range(segments))
        faces=[]
        for j in range(len(rings)-1):
            for i in range(segments):
                a=j*segments+i; b=j*segments+(i+1)%segments
                faces.append((a,b,b+segments,a+segments))
        faces += [tuple(reversed(range(segments))), tuple(range((len(rings)-1)*segments,len(rings)*segments))]
        return self.mesh(name,vertices,faces,mat,smooth=True)

    def wing(self, name, span, root_x, tip_x, root_chord, tip_chord, height, mat):
        # Symmetric 12% airfoil, sampled more densely around the leading edge.
        samples=[(1-math.cos(i*math.pi/16))/2 for i in range(17)]
        thickness=lambda x: .6*(.2969*math.sqrt(x)-.126*x-.3516*x*x+.2843*x**3-.1036*x**4)
        section=[(x,thickness(x)) for x in samples]+[(x,-thickness(x)) for x in reversed(samples[1:-1])]
        vertices=[];count=len(section)
        for f in [-1,-.92,-.55,0,.55,.92,1]:
            t=abs(f);chord=root_chord+(tip_chord-root_chord)*t
            if t==1:chord*=.85
            x=root_x+(tip_x-root_x)*t
            vertices.extend((x-u*chord,height+t*.18+h*chord,f*span/2) for u,h in section)
        faces=[tuple(reversed(range(count))),tuple(range(6*count,7*count))]
        for j in range(6):
            for i in range(count):faces.append((j*count+i,j*count+(i+1)%count,(j+1)*count+(i+1)%count,(j+1)*count+i))
        self.mesh(name,vertices,faces,mat,smooth=True)

    def rod(self,name,a,b,radius,mat,segments=12):
        unit=lambda n:[v/(math.sqrt(sum(x*x for x in n)) or 1) for v in n]
        cross=lambda a,b:[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]
        axis=unit([b[i]-a[i] for i in range(3)])
        u=unit(cross(axis,[1,0,0] if abs(axis[0])<.8 else [0,1,0]));v=cross(axis,u)
        vertices=[]
        for point in [a,b]:
            vertices.extend(tuple(point[j]+radius*(math.cos(i*math.tau/segments)*u[j]+math.sin(i*math.tau/segments)*v[j]) for j in range(3)) for i in range(segments))
        faces=[tuple(reversed(range(segments))),tuple(range(segments,2*segments))]
        faces += [(i,(i+1)%segments,(i+1)%segments+segments,i+segments) for i in range(segments)]
        self.mesh(name,vertices,faces,mat,smooth=True)

    def finish(self, file):
        animated={c['target']['node'] for anim in self.doc.get('animations',[]) for c in anim['channels']}
        groups={};dynamic=[]
        for i,part in enumerate(self.parts):
            if i in animated:dynamic.append((i,part));continue
            name,positions,normals,indices,mat,translation=part
            group=groups.setdefault(mat,[[],[],[]]);offset=len(group[0])
            group[0].extend(positions);group[1].extend(normals);group[2].extend(v+offset for v in indices)
        def primitive(positions,normals,indices,mat):
            pos=self.accessor(positions,'VEC3',True);norm=self.accessor(normals,'VEC3')
            while len(self.binary)%4:self.binary.append(0)
            view=len(self.doc['bufferViews']);data=struct.pack('<'+'H'*len(indices),*indices)
            self.doc['bufferViews'].append({'buffer':0,'byteOffset':len(self.binary),'byteLength':len(data)})
            self.binary.extend(data);access=len(self.doc['accessors'])
            self.doc['accessors'].append({'bufferView':view,'componentType':5123,'count':len(indices),'type':'SCALAR'})
            return {'attributes':{'POSITION':pos,'NORMAL':norm},'indices':access,'material':mat}
        self.doc['meshes']=[{'name':'Airframe','primitives':[primitive(*group,mat) for mat,group in groups.items()]}]
        self.doc['nodes']=[{'name':self.name,'mesh':0}];mapping={}
        for old,(name,positions,normals,indices,mat,translation) in dynamic:
            mesh=len(self.doc['meshes']);self.doc['meshes'].append({'name':name,'primitives':[primitive(positions,normals,indices,mat)]})
            mapping[old]=len(self.doc['nodes']);node={'name':name,'mesh':mesh}
            if translation:node['translation']=translation
            self.doc['nodes'].append(node)
        for anim in self.doc.get('animations',[]):
            for channel in anim['channels']:channel['target']['node']=mapping[channel['target']['node']]
        self.doc['scenes'][0]['nodes']=list(range(len(self.doc['nodes'])))
        self.doc['buffers']=[{'byteLength':len(self.binary)}]
        meta=json.dumps(self.doc,separators=(',',':')).encode();meta+=b' '*(-len(meta)%4)
        self.binary+=b'\0'*(-len(self.binary)%4)
        body=struct.pack('<I4s',len(meta),b'JSON')+meta+struct.pack('<I4s',len(self.binary),b'BIN\0')+self.binary
        file.write_bytes(struct.pack('<4sII',b'glTF',2,12+len(body))+body)
        print(file.name,file.stat().st_size,'bytes;',len(self.doc['nodes']),'nodes;',sum(len(m['primitives']) for m in self.doc['meshes']),'draw primitives')


def build(name, color, sport=False):
    a=Aircraft(name,color)
    # Fine longitudinal stations avoid the old faceted, cigar-shaped silhouette.
    a.hull('Fuselage',[(-4.25,.05,.035,.045),(-3.9,.03,.14,.16),(-3.35,0,.23,.24),(-2.6,0,.32,.33),(-1.7,0,.43,.44),(-.9,0,.53,.52),(0,0,.57,.56),(.75,0,.54,.53),(1.4,-.03,.45,.45),(2,-.04,.39,.4),(2.65,-.04,.33,.35),(2.95,-.04,.26,.29)],0,40)
    a.hull('Cowling',[(1.8,-.04,.411,.415),(2.1,-.04,.39,.397),(2.6,-.04,.34,.358),(2.96,-.04,.267,.299)],0,32)
    # Glazing with a painted spine; high-wing trainer has separate window frames.
    a.hull('Cockpit',[(-1.3,.37,.03,.31),(-1.05,.42,.25,.42),(-.65,.44,.45,.46),(-.2,.44,.5,.46),(.35,.44,.47,.44),(.85,.4,.25,.37),(1.05,.35,.015,.28)],2,32)
    wing_height=-.28 if sport else .87
    span=9.4 if sport else 10.8
    a.wing('Airfoil wings',span,.85,.25 if not sport else -.3,1.55,.95,wing_height,0)
    a.wing('Horizontal stabilizer',3.55,-2.95,-3.35,1.0,.62,.18,0)
    for side in [-1,1]:
        a.rod('Window frame',(-.35,.89,side*.3),(-.35,.38,side*.49),.026,0)
        a.rod('Windshield frame',(.72,.68,side*.29),(.92,.35,side*.36),.025,0)
        a.rod('Main gear',(-.4,-.34,side*.4),(-.6,-1.07,side*1.0),.045,4)
        a.rod('Tire',(-.6,-1.14,side*.92),(-.6,-1.14,side*1.1),.245,3,24)
        a.rod('Wheel hub',(-.6,-1.14,side*1.102),(-.6,-1.14,side*1.112),.115,4,20)
        if not sport:a.rod('Angled wing strut',(-.25,-.23,side*.43),(-.15,.91,side*3.4),.035,0)
        a.box('Wingtip livery',(-.35,wing_height+.235,side*(span/2-.3)),(.6,.025,.3),1)
        a.rod('Navigation light',(-.3,wing_height+.2,side*(span/2-.05)),(-.25,wing_height+.2,side*(span/2-.05)),.045,5)
        # Long painted coachline follows the narrowing tail rather than floating off it.
        a.rod('Tail coachline',(-3.4,.03,side*.235),(-1.75,.04,side*.435),.026,1)
    a.rod('Nose gear',(2.0,-.25,0),(2.0,-1.0,0),.04,4)
    a.rod('Nose tire',(2,-1.14,-.08),(2,-1.14,.08),.21,3,24)
    a.mesh('Vertical stabilizer',[(-4.1,.12,-.055),(-2.82,.12,-.055),(-3.18,1.52,-.035),(-3.73,1.52,-.035),(-4.1,.12,.055),(-2.82,.12,.055),(-3.18,1.52,.035),(-3.73,1.52,.035)],[(0,3,2,1),(4,5,6,7),(0,4,7,3),(1,2,6,5),(3,7,6,2),(0,1,5,4)],1)
    a.box('Rudder detail',(-3.82,.69,0),(.025,1.02,.125),0)
    # Sculpted, tapered propeller blades rotate independently of the batched airframe.
    vertices=[(-.035,-1.13,-.065),(-.035,-.4,-.12),(-.035,.4,.02),(-.035,1.13,.04),(.035,-1.13,-.065),(.035,-.4,-.12),(.035,.4,.02),(.035,1.13,.04)]
    blade=a.mesh('Propeller',vertices,[(0,3,2,1),(4,5,6,7),(0,4,7,3),(1,2,6,5)],3,translation=[3.02,-.04,0])
    a.hull('Spinner',[(3.015,-.04,.22,.22),(3.12,-.04,.2,.2),(3.28,-.04,.12,.12),(3.39,-.04,.008,.008)],4,32)
    times=a.accessor([[i/80] for i in range(5)],'SCALAR',True)
    rots=a.accessor([[math.sin(i*math.pi/4),0,0,math.cos(i*math.pi/4)] for i in range(5)],'VEC4')
    a.doc['animations']=[{'name':'Propeller spin','samplers':[{'input':times,'output':rots,'interpolation':'LINEAR'}],'channels':[{'sampler':0,'target':{'node':blade,'path':'rotation'}}]}]
    a.finish(ROOT/'assets'/name)


if __name__=='__main__':
    build('skylark.glb',[.045,.29,.34,1])
    build('swift.glb',[.48,.045,.03,1],True)
