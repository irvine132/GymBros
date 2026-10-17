#!/usr/bin/env python3
"""Exercise the Gym Bro test API through public Funnel IPv4/TLS, without logging secrets.

Creates two disposable accounts in the non-production database. A public DNS address
is resolved independently by the operator and supplied as GYM_BRO_PUBLIC_IP; TLS
still validates the stable ts.net hostname. No passwords or tokens are persisted.
"""
import http.client
import ipaddress
import json
import os
import secrets
import socket
import ssl
from typing import Any
import uuid

HOST = 'hermes-dev-hub.taildf8f08.ts.net'
IP = os.environ['GYM_BRO_PUBLIC_IP']
if not ipaddress.IPv4Address(IP).is_global:
    raise SystemExit('A public IPv4 address is required')
BASE = '/gym-bro/api/v1'


class PublicHTTPS(http.client.HTTPSConnection):
    def connect(self):
        sock = socket.create_connection((IP, 443), self.timeout)
        self.sock = ssl.create_default_context().wrap_socket(sock, server_hostname=HOST)


def call(method, path, data=None, token=None):
    conn = PublicHTTPS(HOST, timeout=12)
    headers = {'Content-Type': 'application/json'}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    try:
        conn.request(method, BASE + path, json.dumps(data) if data is not None else None, headers)
        reply = conn.getresponse()
        body = reply.read()
        return reply.status, json.loads(body) if reply.status < 300 and body else None
    finally:
        conn.close()


def require(method, path, expected, data=None, token=None) -> Any:
    status, result = call(method, path, data, token)
    if status != expected:
        raise AssertionError(f'{method} {path.split("?")[0]}: HTTP {status}, expected {expected}')
    return result


suffix = secrets.token_hex(4)
require('GET', '/me', 401)
require('GET', '/admin', 404)
accounts = []
for name in ('alice', 'bob'):
    handle = name + suffix
    email = handle + '@example.test'
    password = secrets.token_urlsafe(24)
    auth = require('POST', '/auth/register', 201,
                   {'handle': handle, 'email': email, 'password': password})
    login = require('POST', '/auth/login', 200, {'email': email, 'password': password})
    require('GET', '/me', 200, token=login['token'])
    accounts.append(login['token'])
a, b = accounts
workout = {'clientId': str(uuid.uuid4()), 'title': 'Public smoke ' + suffix,
           'exercises': [{'name': 'Squat', 'sets': [{'reps': 5, 'weight': 80, 'unit': 'kg'}]}]}
session = require('POST', '/sessions', 201, workout, a)
sid = session['id']
require('GET', '/sessions/' + sid, 404, token=b)
require('PUT', '/sessions/' + sid, 404, workout, b)
require('GET', '/feed', 200, token=b)
require('POST', '/sessions/' + sid + '/complete', 200, {}, a)
post = require('POST', '/sessions/' + sid + '/posts', 201, {}, a)
require('GET', '/posts/' + post['id'], 200, token=b)
feed = require('GET', '/feed', 200, token=b)
assert any(item['id'] == post['id'] for item in feed)
require('POST', '/auth/logout', 204, {}, b)
require('GET', '/me', 401, token=b)
print('PASS: public IPv4 TLS registration/login, private IDOR denied, session, publication, cross-account feed/detail, logout; no credentials printed')
