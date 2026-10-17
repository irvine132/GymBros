#!/usr/bin/env bash
# Start the existing Flutter web build on loopback, independent of the caller's pipes.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
web="$root/mobile/build/web"
state="$root/.local"
pidfile="$state/preview.pid"
log="$state/preview.log"
[[ -f "$web/index.html" && -f "$web/main.dart.js" ]] || { printf 'Missing web build: %s\n' "$web" >&2; exit 1; }
mkdir -p "$state"
chmod 700 "$state"
if [[ -f "$pidfile" ]]; then
  old_pid=$(<"$pidfile")
  if [[ "$old_pid" =~ ^[0-9]+$ ]] && kill -0 "$old_pid" 2>/dev/null; then
    if [[ "$(ps -p "$old_pid" -o args=)" != "python3 -m http.server 18082 --bind 127.0.0.1 --directory $web" ]]; then
      printf 'PID file belongs to a different process; inspect %s\n' "$pidfile" >&2
      exit 1
    fi
    printf 'Existing preview PID %s; checking HTTP\n' "$old_pid"
    bash "$root/scripts/preview_smoke.sh"
    exit 0
  fi
  rm -f "$pidfile"
fi
# Never replace an unknown listener (or another project's service).
if [[ -n "$(ss -H -ltn '( sport = :18082 )')" ]]; then
  printf 'Port 18082 occupied; inspect owner before starting preview\n' >&2
  exit 1
fi
# nohup + setsid + three file-backed descriptors survive a detached caller.
nohup setsid python3 -m http.server 18082 --bind 127.0.0.1 --directory "$web" \
  </dev/null >>"$log" 2>&1 &
pid=$!
printf '%s\n' "$pid" > "$pidfile"
for attempt in {1..20}; do
  if bash "$root/scripts/preview_smoke.sh" >/dev/null 2>&1; then
    printf 'Preview PID %s; log %s\n' "$pid" "$log"
    bash "$root/scripts/preview_smoke.sh"
    exit 0
  fi
  if ! kill -0 "$pid" 2>/dev/null; then break; fi
  sleep 0.25
done
printf 'Preview startup failed; inspect %s\n' "$log" >&2
if kill -0 "$pid" 2>/dev/null; then kill "$pid"; fi
rm -f "$pidfile"
exit 1
