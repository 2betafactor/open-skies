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
        self.doc = dict(asset={'version': '2.0', 'generator': 'Open Skies aircraft workshop'},
                        scene=0, scenes=[{'nodes': []}], nodes=[], meshes=[], accessors=[], bufferViews=[],
                        materials=[], buffers=[])
        for label, rgba, metal, rough in [
            ('Ivory enamel', [0.91, .93, .88, 1], .2, .35),
            ('Livery', color, .25, .3),
            ('Midnight canopy', [.025, .10, .16, 1], .65, .18),
            ('Graphite rubber', [.035, .045, .05, 1], .0, .9),
            ('Brushed metal', [.55, .61, .64, 1], .8, .3),
            ('Amber tips', [1, .61, .12, 1], .1, .35),
        ]:
            self.doc['materials'].append({'name': label, 'doubleSided': True, 'pbrMetallicRoughness': {
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

    def mesh(self, name, vertices, faces, material, translation=None):
        positions, normals = [], []
        for face in faces:
            for i in range(1, len(face) - 1):
                a, b, c = [vertices[j] for j in (face[0], face[i], face[i+1])]
                u, v = [b[j]-a[j] for j in range(3)], [c[j]-a[j] for j in range(3)]
                n = [u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2], u[0]*v[1]-u[1]*v[0]]
                length = math.sqrt(sum(x*x for x in n)) or 1
                n = [x/length for x in n]
                positions.extend([a,b,c]); normals.extend([n,n,n])
        mesh = len(self.doc['meshes'])
        self.doc['meshes'].append({'name': name, 'primitives': [{'attributes': {
            'POSITION': self.accessor(positions, 'VEC3', True), 'NORMAL': self.accessor(normals, 'VEC3')}, 'material': material}]})
        node = {'mesh': mesh, 'name': name}
        if translation:
            node['translation'] = translation
        self.doc['nodes'].append(node)
        index = len(self.doc['nodes']) - 1
        self.doc['scenes'][0]['nodes'].append(index)
        return index

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
        return self.mesh(name,vertices,faces,mat)

    def wing(self, name, span, root_x, tip_x, root_chord, tip_chord, height, mat):
        # Airfoil cross-section with rounded leading edge and thin trailing edge.
        section=[(0,0),(.1,.09),(.4,.11),(1,0),(.4,-.025),(.1,-.025)]
        vertices=[]
        for z,x,chord,y in [(-span/2,tip_x,tip_chord,height+.22),(0,root_x,root_chord,height),(span/2,tip_x,tip_chord,height+.22)]:
            vertices += [(x-u*chord,y+h*chord,z) for u,h in section]
        faces=[tuple(reversed(range(6))),tuple(range(12,18))]
        for j in range(2):
            for i in range(6): faces.append((j*6+i,j*6+(i+1)%6,(j+1)*6+(i+1)%6,(j+1)*6+i))
        self.mesh(name,vertices,faces,mat)

    def finish(self, file):
        self.doc['buffers']=[{'byteLength':len(self.binary)}]
        meta=json.dumps(self.doc,separators=(',',':')).encode()
        meta += b' ' * (-len(meta)%4)
        self.binary += b'\0' * (-len(self.binary)%4)
        body=struct.pack('<I4s',len(meta),b'JSON')+meta+struct.pack('<I4s',len(self.binary),b'BIN\0')+self.binary
        file.write_bytes(struct.pack('<4sII',b'glTF',2,12+len(body))+body)
        print(file.name, file.stat().st_size, 'bytes')


def build(name, color, sport=False):
    a=Aircraft(name,color)
    a.hull('Streamlined fuselage', [(-4,0,.12,.12),(-3,0,.27,.3),(-1,0,.55,.57),(.6,0,.67,.64),(2,0,.5,.5),(2.8,0,.38,.38),(3.05,0,.27,.27)],0)
    a.hull('Engine cowling',[(2.05,0,.505,.505),(2.65,0,.42,.42),(3.08,0,.275,.275)],1)
    a.hull('Panoramic cockpit',[(-1.35,.38,.05,.38),(-.85,.53,.48,.49),(.35,.53,.51,.49),(1.1,.43,.12,.38)],2)
    a.wing('Main wings',10.8 if not sport else 9.4, .8, .3 if not sport else -.3,1.65,1.05, .8 if not sport else -.25,1)
    a.wing('Tail stabilizer',3.7,-2.8,-3.15,1.05,.65,.23,0)
    for side in [-1,1]:
        a.box('Wingtip marking',(0,.98 if not sport else -.02,side*(5.05 if not sport else 4.35)),(.85,.05,.3),5)
        a.box('Fuselage stripe',(-1,-.02,side*.52),(2.9,.13,.035),1)
        a.box('Landing leg',(.3,-.9,side*.95),(.13,1.4,.12),4)
        # Wheels are cylinders with their axle along the span.
        vertices=[]
        for z in [side*1.05-.12,side*1.05+.12]:
            vertices.extend((.3+.32*math.cos(i*math.tau/24),-1.5+.32*math.sin(i*math.tau/24),z) for i in range(24))
        faces=[tuple(reversed(range(24))),tuple(range(24,48))]+[(i,(i+1)%24,(i+1)%24+24,i+24) for i in range(24)]
        a.mesh('Main wheel',vertices,faces,3)
        if not sport: a.box('Wing support',(-.05,.2,side*1.65),(.09,1.3,.09),4)
    a.box('Tail wheel',(-3.45,-.47,0),(.25,.35,.19),3)
    a.mesh('Swept vertical tail',[(-3.95,.1,-.07),(-2.7,.1,-.07),(-3.05,1.8,-.07),(-3.75,1.8,-.07),(-3.95,.1,.07),(-2.7,.1,.07),(-3.05,1.8,.07),(-3.75,1.8,.07)],[(0,3,2,1),(4,5,6,7),(0,4,7,3),(1,2,6,5),(3,7,6,2)],1)
    # Propeller is a separate rotating node, with a one-second looping animation.
    blade=a.box('Propeller',(0,0,0),(.09,2.65,.17),3)
    a.doc['nodes'][blade]['translation']=[3.15,0,0]
    a.hull('Polished spinner',[(3.13,0,.25,.25),(3.4,0,.15,.15),(3.56,0,.01,.01)],4)
    times=a.accessor([[i/4] for i in range(5)],'SCALAR',True)
    rots=a.accessor([[math.sin(i*math.pi/4),0,0,math.cos(i*math.pi/4)] for i in range(5)],'VEC4')
    a.doc['animations']=[{'name':'Propeller spin','samplers':[{'input':times,'output':rots,'interpolation':'LINEAR'}],'channels':[{'sampler':0,'target':{'node':blade,'path':'rotation'}}]}]
    a.finish(ROOT/'assets'/name)


if __name__=='__main__':
    build('skylark.glb',[.035,.36,.39,1])
    build('swift.glb',[.72,.09,.055,1],True)
