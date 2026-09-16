"""Original low-poly GT coupe. Reuses the project's standard-library GLB writer."""
import math
from build_aircraft import Aircraft, ROOT


def build():
    car=Aircraft('street-gt.glb',[.95,.27,.035,1])
    # +X forward, +Y up, +Z right. Ground at wheel bottoms.
    cross=[(.78,-.78),(.65,-.95),(.32,-.9),(.27,-.72),(.27,.72),(.32,.9),(.65,.95),(.78,.78)]
    vertices=[(x,y*height,z*width) for x,height,width in [(-2.15,1,.87),(-1.6,1.12,1),(.9,1.08,1),(2.15,.95,.88)] for y,z in cross]
    faces=[tuple(reversed(range(8))),tuple(range(24,32))]
    for section in range(3):
        faces.extend((section*8+i,section*8+(i+1)%8,(section+1)*8+(i+1)%8,(section+1)*8+i) for i in range(8))
    car.mesh('Sculpted GT body',vertices,faces,1)
    car.box('Rear bumper',(-2.18,.38,0),(.08,.18,1.55),3)
    car.doc['materials'].append({'name':'Rear lights','pbrMetallicRoughness':{'baseColorFactor':[.95,.025,.035,1],'roughnessFactor':.25},'emissiveFactor':[.45,.01,.01]})
    car.mesh('Glass canopy',[(-1.35,.89,-.77),(.95,.89,-.77),(.3,1.53,-.63),(-.85,1.53,-.63),(-1.35,.89,.77),(.95,.89,.77),(.3,1.53,.63),(-.85,1.53,.63)],[(0,3,2,1),(4,5,6,7),(0,4,7,3),(1,2,6,5),(3,7,6,2)],2)
    car.box('Roof',(-.27,1.56,0),(1.14,.08,1.32),1)
    car.box('Hood stripe',(1.35,.83,0),(1.15,.025,.22),3)
    car.box('Rear spoiler',(-1.88,1.0,0),(.27,.09,1.85),3)
    car.box('Front grille',(2.13,.48,0),(.05,.23,1.06),3)
    for side in [-1,1]:
        car.box('LED headlight',(2.2,.69,side*.58),(.055,.1,.33),0)
        car.box('Tail lamp',(-2.2,.67,side*.53),(.055,.12,.32),6)
        car.box('Mirror',(.35,1.08,side*.91),(.24,.14,.19),3)
        car.box('Side sill',(0,.31,side*.93),(3.0,.15,.09),3)
        for x in [-1.35,1.35]:
            vertices=[]
            for z in [side*.91-.13,side*.91+.13]:
                vertices.extend((x+.34*math.cos(i*math.tau/24),.34+.34*math.sin(i*math.tau/24),z) for i in range(24))
            faces=[tuple(reversed(range(24))),tuple(range(24,48))]+[(i,(i+1)%24,(i+1)%24+24,i+24) for i in range(24)]
            car.mesh('Tire',vertices,faces,3)
            car.box('Wheel hub',(x,.34,side*1.05),(.34,.34,.02),4)
    car.finish(ROOT/'assets'/'street-gt.glb')

if __name__=='__main__': build()
