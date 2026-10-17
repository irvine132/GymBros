#!/usr/bin/env python3
"""Check the release AOT library contains the intended public test API URL."""
import sys
import zipfile

expected = b'https://hermes-dev-hub.taildf8f08.ts.net/gym-bro/api/v1'
with zipfile.ZipFile(sys.argv[1]) as apk:
    library = apk.read('lib/arm64-v8a/libapp.so')
if expected not in library:
    raise SystemExit('FAIL: expected HTTPS API URL absent from arm64 AOT library')
if b'http://127.0.0.1:18081/api/v1' in library:
    raise SystemExit('FAIL: loopback API URL present in arm64 AOT library')
print('PASS: arm64 AOT contains public HTTPS API URL; loopback API URL absent')
