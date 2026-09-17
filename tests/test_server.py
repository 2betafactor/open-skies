import json
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from pathlib import Path
import server


class ScoresTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        server.DATA = str(Path(cls.temp.name) / 'data')
        server.SCORES = str(Path(server.DATA) / 'scores.json')
        cls.http = server.ThreadingHTTPServer(('127.0.0.1', 0), server.Handler)
        cls.url = f'http://127.0.0.1:{cls.http.server_port}'
        threading.Thread(target=cls.http.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.http.shutdown()
        cls.http.server_close()
        cls.temp.cleanup()

    def request(self, path, data=None):
        body = json.dumps(data).encode() if data is not None else None
        try:
            response = urllib.request.urlopen(urllib.request.Request(self.url + path, data=body))
        except urllib.error.HTTPError as e:
            response = e
        return response.status, json.loads(response.read())

    def test_invalid_scores(self):
        for data in ([], {'distanceKm': 'oops'}, {'timeSec': -1}, {'topSpeedKmh': float('inf')}, {'path': [[181, 0, 0, 0]]}, {'path': [[0, 0]]}, {'world': 'invalid'}, {'vehicle': '../other.glb'}):
            with self.subTest(data=data):
                self.assertEqual(self.request('/api/scores', data)[0], 400)

    def test_sandbox_replay_round_trip(self):
        path = [[0, 0, 350, 0], [0, .001, 350, 0]]
        status, result = self.request('/api/scores', {'world': 'sandbox', 'vehicle': 'swift', 'path': path, 'distanceKm': 1})
        self.assertEqual(status, 201)
        status, flight = self.request('/api/flight?id=' + result['id'])
        self.assertEqual(flight['world'], 'sandbox')
        self.assertEqual(flight['vehicle'], 'swift')
        self.assertEqual(flight['path'], path)
        self.assertNotIn('path', result['board'][0])

    def test_static_assets_revalidate_after_deploy(self):
        for path in ('/', '/src/main.js', '/src/home.css', '/assets/plane.glb'):
            with urllib.request.urlopen(self.url + path) as response:
                self.assertEqual(response.headers.get('Cache-Control'), 'no-cache')
                self.assertEqual(response.status, 200)

    def test_private_files_not_served(self):
        for path in ('/scores.json', '/.git/config', '/server.py', '/src/'):
            self.assertEqual(self.request(path)[0], 404)


if __name__ == '__main__':
    unittest.main()
