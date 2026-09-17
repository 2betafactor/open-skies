import json
import struct
import unittest
from pathlib import Path


class AircraftAssetsTest(unittest.TestCase):
    def test_optimized_models_are_self_contained_and_indexed(self):
        for name in ('skylark', 'swift'):
            with self.subTest(model=name):
                data=(Path(__file__).resolve().parents[1]/'assets'/f'{name}.glb').read_bytes()
                magic,version,length=struct.unpack_from('<4sII',data)
                self.assertEqual((magic,version,length),(b'glTF',2,len(data)))
                self.assertLess(len(data),90000)
                json_length=struct.unpack_from('<I',data,12)[0]
                doc=json.loads(data[20:20+json_length])
                self.assertEqual(len(doc['nodes']),2)
                self.assertNotIn('uri',doc['buffers'][0])
                binary=data[28+json_length:]
                self.assertEqual(len(binary),doc['buffers'][0]['byteLength'])
                for mesh in doc['meshes']:
                    for primitive in mesh['primitives']:
                        accessor=doc['accessors'][primitive['indices']]
                        view=doc['bufferViews'][accessor['bufferView']]
                        indices=struct.unpack_from('<'+'H'*accessor['count'],binary,view['byteOffset'])
                        count=doc['accessors'][primitive['attributes']['POSITION']]['count']
                        self.assertLess(max(indices),count)
                        self.assertEqual(accessor['count']%3,0)
                target=doc['animations'][0]['channels'][0]['target']['node']
                self.assertEqual(doc['nodes'][target]['name'],'Propeller')

if __name__=='__main__': unittest.main()
