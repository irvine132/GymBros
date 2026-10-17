#!/usr/bin/env bash
# Start Gym Bro's loopback-only test gateway without touching the API or preview.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
state="$root/.local"
mkdir -p "$state"
chmod 700 "$state"
if [[ -f "$state/public-api.pid" ]]; then
  pid=$(<"$state/public-api.pid")
  if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
    [[ "$(ps -p "$pid" -o args=)" == "python3 $root/scripts/public_api_gateway.py" ]] || {
      printf 'PID belongs to another process; refusing to replace\n' >&2; exit 1;
    }
    printf 'Gateway PID %s\n' "$pid"
    exit 0
  fi
fi
[[ -z "$(ss -H -ltn '( sport = :18083 )')" ]] || { printf 'Port 18083 occupied\n' >&2; exit 1; }
nohup setsid python3 "$root/scripts/public_api_gateway.py" </dev/null >>"$state/public-api.log" 2>&1 &
pid=$!
printf '%s\n' "$pid" >"$state/public-api.pid"
for attempt in {1..20}; do
  code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 2 http://127.0.0.1:18083/gym-bro/api/v1/me 2>/dev/null || true)
  if [[ "$code" == 401 ]]; then printf 'Gateway PID %s, anonymous /me 401\n' "$pid"; exit 0; fi
  if ! kill -0 "$pid" 2>/dev/null; then break; fi
  sleep 0.25
done
printf 'Gateway startup failed; inspect %s\n' "$state/public-api.log" >&2
exit 1
