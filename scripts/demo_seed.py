#!/usr/bin/env python3
"""Create two disposable local accounts and verify the cross-account Slice A flow.

Credentials are randomly generated and saved in .local/demo-accounts.json (gitignored,
mode 0600), never printed. Run only against a loopback development API/database.
"""
import json
import os
from pathlib import Path
import re
import secrets
import urllib.error
import urllib.request
import uuid
from typing import Any

BASE = os.environ.get('GYM_BRO_API', 'http://127.0.0.1:18081/api/v1')
if not BASE.startswith(('http://127.0.0.1:', 'http://localhost:')):
    raise SystemExit('Refusing non-loopback API')
filename = os.environ.get('GYM_BRO_DEMO_FILENAME', 'demo-accounts.json')
if not re.fullmatch(r'[a-z0-9-]{1,48}\.json', filename):
    raise SystemExit('Invalid demo filename')
output = Path(__file__).resolve().parents[1] / '.local' / filename
if output.exists():
    raise SystemExit(f'Existing credentials at {output}; keep them or move them manually before reseeding')


def call(method: str, path: str, data: Any = None, token: str | None = None) -> tuple[int, Any]:
    request = urllib.request.Request(
        BASE + path,
        data=json.dumps(data).encode() if data is not None else None,
        headers={'Content-Type': 'application/json', **({'Authorization': f'Bearer {token}'} if token else {})},
        method=method,
    )
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            return response.status, json.load(response) if response.status != 204 else None
    except urllib.error.HTTPError as error:
        return error.code, None


def require(status, expected):
    if status != expected:
        raise RuntimeError(f'Unexpected HTTP status {status}, expected {expected}')


suffix = secrets.token_hex(4)
accounts = []
for name in ('alice', 'bob'):
    handle = name + suffix
    password = secrets.token_urlsafe(24)
    email = f'{handle}@example.test'
    status, auth = call('POST', '/auth/register', {'handle': handle, 'email': email, 'password': password})
    require(status, 201)
    require(call('GET', '/me', token=auth['token'])[0], 200)
    accounts.append({'handle': handle, 'email': email, 'password': password, 'token': auth['token']})
a, b = accounts
workout = {
    'clientId': str(uuid.uuid4()), 'title': 'Demo squat ' + suffix,
    'exercises': [{'name': 'Squat', 'sets': [{'reps': 5, 'weight': 80, 'unit': 'kg'}]}],
}
status, session = call('POST', '/sessions', workout, a['token'])
require(status, 201)
sid = session['id']
require(call('GET', f'/sessions/{sid}', token=b['token'])[0], 404)
require(call('GET', '/feed', token=b['token'])[0], 200)
require(call('POST', f'/sessions/{sid}/complete', {}, a['token'])[0], 200)
status, post = call('POST', f'/sessions/{sid}/posts', {}, a['token'])
require(status, 201)
require(call('GET', f"/posts/{post['id']}", token=b['token'])[0], 200)
status, again = call('POST', f'/sessions/{sid}/posts', {}, a['token'])
require(status, 200)
assert again['id'] == post['id']
assert any(item['id'] == post['id'] for item in call('GET', '/feed', token=b['token'])[1])

private = Path(__file__).resolve().parents[1] / '.local'
private.mkdir(mode=0o700, exist_ok=True)
os.chmod(private, 0o700)
fd = os.open(output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(fd, 'w') as file:
    json.dump({'accounts': [{k: entry[k] for k in ('handle', 'email', 'password')} for entry in accounts], 'postId': post['id']}, file)
print(f'PASS: two-account flow; credentials saved privately at {output}')
