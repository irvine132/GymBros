import unittest
from public_api_gateway import admitted, route, _windows


class GatewayTest(unittest.TestCase):
    def test_route_allowlist_and_normalization(self):
        self.assertEqual(route('GET', '/gym-bro/api/v1/feed?offset=1'), '/api/v1/feed?offset=1')
        self.assertEqual(route('POST', '/gym-bro/api/v1/auth/login'), '/api/v1/auth/login')
        self.assertEqual(route('POST', '/gym-bro/api/v1/sessions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/posts'),
                         '/api/v1/sessions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/posts')
        for path in ('/gym-bro/api/v1/admin', '/gym-bro/api/v1/../admin',
                     '/gym-bro/api/v1/feed?offset=-1', '/api/v1/feed',
                     '/gym-bro/api/v1/sessions/not-a-uuid', '/gym-bro/api/v1/feed/extra'):
            self.assertIsNone(route('GET', path), path)
        self.assertIsNone(route('DELETE', '/gym-bro/api/v1/sessions'), 'unexpected method')

    def test_global_write_limits(self):
        _windows['auth'].clear()
        for _ in range(30):
            self.assertTrue(admitted('POST', '/api/v1/auth/login'))
        self.assertFalse(admitted('POST', '/api/v1/auth/login'))
        _windows['auth'].clear()


if __name__ == '__main__':
    unittest.main()
