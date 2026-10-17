#!/usr/bin/env bash
# Check a running loopback Flutter preview and its local API without credentials.
set -euo pipefail
preview="${GYM_BRO_PREVIEW:-http://127.0.0.1:18082}"
api="${GYM_BRO_API:-http://127.0.0.1:18081/api/v1}"
for url in "$preview/" "$preview/index.html" "$preview/main.dart.js"; do
  code=$(curl --silent --show-error --max-time 8 -o /dev/null -w '%{http_code}' "$url")
  if [[ "$code" != 200 ]]; then
    printf 'FAIL: %s returned HTTP %s (expected 200)\n' "$url" "$code" >&2
    exit 1
  fi
  printf 'PASS: %s HTTP 200\n' "$url"
done
code=$(curl --silent --show-error --max-time 8 -o /dev/null -w '%{http_code}' "$api/me")
if [[ "$code" != 401 ]]; then
  printf 'FAIL: unauthenticated API returned HTTP %s (expected 401)\n' "$code" >&2
  exit 1
fi
printf 'PASS: unauthenticated API HTTP 401\n'
