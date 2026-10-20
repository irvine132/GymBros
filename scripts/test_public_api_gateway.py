import unittest
from public_api_gateway import admitted, route, _windows


class GatewayTest(unittest.TestCase):
    def test_route_allowlist_and_normalization(self):
        self.assertEqual(route('GET', '/gym-bro/api/v1/feed?offset=1'), '/api/v1/feed?offset=1')
        # Tailscale --set-path strips /gym-bro before forwarding to this loopback gateway.
        self.assertEqual(route('GET', '/api/v1/me'), '/api/v1/me')
        self.assertEqual(route('GET', '/api/v1/me/summary'), '/api/v1/me/summary')
        self.assertEqual(route('GET', '/api/v1/exercises'), '/api/v1/exercises')
        self.assertEqual(route('GET', '/api/v1/feed/following?limit=20'), '/api/v1/feed/following?limit=20')
        self.assertEqual(route('GET', '/api/v1/users?query=alice'), '/api/v1/users?query=alice')
        self.assertEqual(route('POST', '/api/v1/users/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/follow'), '/api/v1/users/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/follow')
        self.assertEqual(route('DELETE', '/api/v1/users/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/follow'), '/api/v1/users/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/follow')
        self.assertEqual(route('PUT', '/api/v1/me/profile'), '/api/v1/me/profile')
        identifier = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
        for method, path in [('GET', '/templates'), ('GET', f'/templates/{identifier}'),
                             ('PUT', f'/templates/{identifier}'), ('POST', f'/posts/{identifier}/copy'),
                             ('POST', f'/templates/{identifier}/sessions'), ('POST', '/wods'),
                             ('PUT', f'/wods/{identifier}'), ('POST', '/hyrox'),
                             ('PUT', f'/hyrox/{identifier}')]:
            self.assertEqual(route(method, '/gym-bro/api/v1' + path), '/api/v1' + path)
        for method, path in [('GET', f'/posts/{identifier}/comments?limit=1'),
                             ('POST', f'/posts/{identifier}/comments'),
                             ('POST', f'/posts/{identifier}/likes'),
                             ('DELETE', f'/posts/{identifier}/likes'),
                             ('DELETE', f'/posts/{identifier}/comments/{identifier}')]:
            self.assertEqual(route(method, '/gym-bro/api/v1' + path), '/api/v1' + path)
        self.assertIsNone(route('GET', f'/posts/{identifier}/comments?cursor=%0a'))
        self.assertIsNone(route('POST', f'/posts/{identifier}/comments?owner=other'))
        self.assertIsNone(route('DELETE', f'/posts/{identifier}/comments/not-a-uuid'))
        self.assertIsNone(route('GET', '/api/v1/wods'))
        self.assertIsNone(route('PUT', '/api/v1/wods/not-a-uuid'))
        self.assertIsNone(route('GET', '/api/v1/hyrox'))
        self.assertIsNone(route('PUT', '/api/v1/hyrox/not-a-uuid'))
        self.assertIsNone(route('GET', '/api/v1/templates?owner=other'))
        self.assertIsNone(route('DELETE', '/api/v1/templates/' + identifier))
        self.assertIsNone(route('GET', '/api/v1/users?query=%2e%2e%2fadmin'))
        self.assertIsNone(route('GET', '/api/v1/feed/following?cursor=%0a'))
        self.assertEqual(route('GET', '/api/v1/feed?offset=1'), '/api/v1/feed?offset=1')
        self.assertEqual(route('POST', '/gym-bro/api/v1/auth/login'), '/api/v1/auth/login')
        self.assertEqual(route('POST', '/gym-bro/api/v1/sessions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/posts'),
                         '/api/v1/sessions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/posts')
        self.assertEqual(route('POST', '/gym-bro/api/v1/sessions/' + identifier + '/complete-expected'),
                         '/api/v1/sessions/' + identifier + '/complete-expected')
        self.assertIsNone(route('GET', '/api/v1/sessions/' + identifier + '/complete-expected'))
        self.assertIsNone(route('POST', '/api/v1/sessions/not-a-uuid/complete-expected'))
        for path in ('/gym-bro/api/v1/admin', '/api/v1/admin', '/gym-bro/api/v1/../admin',
                     '/gym-bro/api/v1/feed?offset=-1', '/api/v1/feed?offset=-1',
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
