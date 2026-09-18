"""Validate actual GLB buffers, bounds, materials and indexed geometry."""
import unittest,json,struct,math
from pathlib import Path
class FleetAssets(unittest.TestCase):
 def test_glb_geometry(self):
  for name in ['aerion','wayfarer']:
   b=(Path(__file__).resolve().parents[1]/'assets'/f'{name}.glb').read_bytes()
   magic,version,total=struct.unpack_from('<III',b)
   self.assertEqual((magic,version,total),(0x46546c67,2,len(b)))
   size,kind=struct.unpack_from('<II',b,12);self.assertEqual(kind,0x4e4f534a)
   model=json.loads(b[20:20+size]);binary=b[28+size:]
   self.assertEqual(model['nodes'][0]['extras']['forwardAxis'],'+Z')
   def values(index):
    a=model['accessors'][index];v=model['bufferViews'][a['bufferView']];n={'VEC3':3,'SCALAR':1}[a['type']]
    return struct.unpack_from('<'+('f' if a['componentType']==5126 else 'I')*a['count']*n,binary,v.get('byteOffset',0))
   self.assertLessEqual(len(model['meshes'][0]['primitives']),8)
   self.assertLess(len(b),450000)
   for primitive in model['meshes'][0]['primitives']:
    pos=values(primitive['attributes']['POSITION']);norm=values(primitive['attributes']['NORMAL']);indices=values(primitive['indices'])
    self.assertTrue(all(math.isfinite(x) for x in pos+norm))
    self.assertLess(max(indices),len(pos)//3)
    self.assertLess(max(abs(x) for x in pos),10)
    self.assertEqual(len(indices)%3,0)
    for i in range(0,len(norm),3):self.assertAlmostEqual(sum(x*x for x in norm[i:i+3]),1,places=4)
