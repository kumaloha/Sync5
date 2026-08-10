#!/usr/bin/env bash
set -euo pipefail
if [ -n "${ZSH_VERSION:-}" ]; then
  setopt no_bg_nice
fi
PROG="$(basename "$0")"

usage() {
  printf 'usage: %s all|<id>|<id,id,...>\n' "$PROG" >&2
}

if [ "$#" -ne 1 ]; then
  usage
  exit 2
fi

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)"
MANIFEST="$REPO_ROOT/assets/jokers/manifest.json"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
PORT="61356"
SERVER_PORT="61355"
SELECTOR="$1"
TMPDIR=""
SERVER_PID=""
CHROME_PID=""

if [ ! -f "$MANIFEST" ]; then
  printf 'missing manifest: %s\n' "$MANIFEST" >&2
  exit 1
fi
if [ ! -x "$CHROME" ]; then
  printf 'missing Chrome executable: %s\n' "$CHROME" >&2
  exit 1
fi

ALL_IDS="$(jq -r '.cards[]?.id' "$MANIFEST")"
if [ -z "$ALL_IDS" ]; then
  printf 'manifest has no card IDs\n' >&2
  exit 1
fi

if [ "$SELECTOR" = "all" ]; then
  IDS="$ALL_IDS"
else
  if printf '%s' "$SELECTOR" | grep -Eq '(^|,)[[:space:]]*($|,)'; then
    printf 'malformed selector: empty joker ID in %s\n' "$SELECTOR" >&2
    usage
    exit 2
  fi
  IDS="$(printf '%s\n' "$SELECTOR" | tr ',' '\n')"
fi

if [ -z "$IDS" ]; then
  printf 'malformed selector: empty selector\n' >&2
  usage
  exit 2
fi

DUPLICATES="$(printf '%s\n' "$IDS" | awk 'NF { seen[$0]++; if (seen[$0] == 2) print $0 }')"
if [ -n "$DUPLICATES" ]; then
  printf 'duplicate requested id(s): %s\n' "$(printf '%s' "$DUPLICATES" | paste -sd, -)" >&2
  exit 2
fi

UNKNOWN="$(comm -23 <(printf '%s\n' "$IDS" | sort) <(printf '%s\n' "$ALL_IDS" | sort))"
if [ -n "$UNKNOWN" ]; then
  printf 'unknown requested id(s): %s\n' "$(printf '%s' "$UNKNOWN" | paste -sd, -)" >&2
  exit 2
fi

port_is_free() {
  python3 - "$1" <<'PY'
import socket
import sys

port = int(sys.argv[1])
sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
try:
    sock.bind(("127.0.0.1", port))
except OSError:
    sys.exit(1)
finally:
    sock.close()
PY
}

preflight_port() {
  local port="$1"
  local label="$2"
  if ! port_is_free "$port"; then
    printf 'port %s (%s) is already occupied; aborting before rendering\n' "$port" "$label" >&2
    exit 1
  fi
}

ensure_pid_alive() {
  local pid="$1"
  local label="$2"
  if ! kill -0 "$pid" >/dev/null 2>&1; then
    printf '%s process exited before it became ready\n' "$label" >&2
    return 1
  fi
}

print_log_tail() {
  local path="$1"
  local label="$2"
  if [ -f "$path" ]; then
    printf '\n--- %s tail (%s) ---\n' "$label" "$path" >&2
    tail -n 40 "$path" >&2 || true
  fi
}

preflight_port "$SERVER_PORT" "HTTP server"
preflight_port "$PORT" "Chrome DevTools"

mkdir -p "$REPO_ROOT/assets/jokers/cards" "$REPO_ROOT/assets/jokers/previews"
TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/sync5-joker-render.XXXXXX")"

cleanup() {
  local status="$?"
  if [ "$status" -ne 0 ] && [ -n "$TMPDIR" ]; then
    print_log_tail "$TMPDIR/http.log" "http.log"
    print_log_tail "$TMPDIR/chrome.log" "chrome.log"
  fi
  if [ -n "$CHROME_PID" ]; then
    kill "$CHROME_PID" >/dev/null 2>&1 || true
    wait "$CHROME_PID" >/dev/null 2>&1 || true
  fi
  if [ -n "$SERVER_PID" ]; then
    kill "$SERVER_PID" >/dev/null 2>&1 || true
    wait "$SERVER_PID" >/dev/null 2>&1 || true
  fi
  rm -rf "$TMPDIR" || true
}
trap cleanup EXIT INT TERM

cd "$REPO_ROOT"
python3 -m http.server "$SERVER_PORT" --bind 127.0.0.1 >"$TMPDIR/http.log" 2>&1 &
SERVER_PID="$!"

for _ in $(seq 1 100); do
  ensure_pid_alive "$SERVER_PID" "HTTP server"
  if curl -fsS "http://127.0.0.1:$SERVER_PORT/assets/jokers/manifest.json" >/dev/null 2>&1; then
    break
  fi
  sleep 0.05
done
ensure_pid_alive "$SERVER_PID" "HTTP server"
curl -fsS "http://127.0.0.1:$SERVER_PORT/assets/jokers/manifest.json" >/dev/null

"$CHROME" \
  --headless=new \
  --hide-scrollbars \
  --disable-gpu \
  --remote-debugging-address=127.0.0.1 \
  --remote-debugging-port="$PORT" \
  --user-data-dir="$TMPDIR/chrome-profile" \
  about:blank >"$TMPDIR/chrome.log" 2>&1 &
CHROME_PID="$!"

for _ in $(seq 1 100); do
  ensure_pid_alive "$CHROME_PID" "Chrome"
  if curl -fsS "http://127.0.0.1:$PORT/json/version" >/dev/null 2>&1; then
    break
  fi
  sleep 0.05
done
ensure_pid_alive "$CHROME_PID" "Chrome"
VERSION_JSON="$(curl -fsS "http://127.0.0.1:$PORT/json/version")"
DEVTOOLS_ENDPOINT="$(printf '%s' "$VERSION_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("webSocketDebuggerUrl", ""))')"
if [ -z "$DEVTOOLS_ENDPOINT" ]; then
  printf 'Chrome DevTools endpoint missing from /json/version\n' >&2
  exit 1
fi
for _ in $(seq 1 100); do
  ensure_pid_alive "$CHROME_PID" "Chrome"
  if grep -Fq "$DEVTOOLS_ENDPOINT" "$TMPDIR/chrome.log"; then
    break
  fi
  sleep 0.05
done
if ! grep -Fq "$DEVTOOLS_ENDPOINT" "$TMPDIR/chrome.log"; then
  printf 'Chrome DevTools endpoint was not emitted by the launched Chrome process\n' >&2
  exit 1
fi

render_one() {
  local id="$1"
  local scale="$2"
  local width="$3"
  local height="$4"
  local out="$5"
  local url="http://127.0.0.1:$SERVER_PORT/tools/art/joker_card_renderer.html?id=$id&scale=$scale"

  python3 - "$PORT" "$url" "$width" "$height" "$out" <<'PY'
import base64
import atexit
import json
import os
import socket
import struct
import sys
import time
import urllib.parse
import urllib.request

port, url, width, height, out = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), sys.argv[5]

def request_json(endpoint, data=None, method=None):
    payload = None if data is None else json.dumps(data).encode()
    req = urllib.request.Request(f"http://127.0.0.1:{port}{endpoint}", data=payload, method=method)
    if data is not None:
        req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, timeout=5) as response:
        return json.loads(response.read().decode())

target = request_json("/json/new?" + urllib.parse.quote(url, safe=":/?&=%"), method="PUT")
target_id = target["id"]

def close_target():
    try:
        request_json("/json/close/" + urllib.parse.quote(target_id, safe=""))
    except Exception:
        pass

atexit.register(close_target)
ws_url = target["webSocketDebuggerUrl"]
parts = urllib.parse.urlparse(ws_url)
sock = socket.create_connection((parts.hostname, parts.port), timeout=5)
key = base64.b64encode(os.urandom(16)).decode()
handshake = (
    f"GET {parts.path} HTTP/1.1\r\n"
    f"Host: {parts.hostname}:{parts.port}\r\n"
    "Upgrade: websocket\r\n"
    "Connection: Upgrade\r\n"
    f"Sec-WebSocket-Key: {key}\r\n"
    "Sec-WebSocket-Version: 13\r\n\r\n"
)
sock.sendall(handshake.encode())
response = sock.recv(4096)
if b" 101 " not in response:
    raise SystemExit("Chrome DevTools websocket handshake failed")

next_id = 0
pending = {}

def recv_exact(n):
    data = b""
    while len(data) < n:
        chunk = sock.recv(n - len(data))
        if not chunk:
            raise SystemExit("Chrome DevTools websocket closed")
        data += chunk
    return data

def read_frame():
    first, second = recv_exact(2)
    length = second & 0x7F
    if length == 126:
        length = struct.unpack("!H", recv_exact(2))[0]
    elif length == 127:
        length = struct.unpack("!Q", recv_exact(8))[0]
    if second & 0x80:
        mask = recv_exact(4)
        payload = bytes(b ^ mask[i % 4] for i, b in enumerate(recv_exact(length)))
    else:
        payload = recv_exact(length)
    if first & 0x0F == 8:
        raise SystemExit("Chrome DevTools websocket closed")
    return json.loads(payload.decode())

def write_frame(payload):
    data = json.dumps(payload).encode()
    header = bytearray([0x81])
    if len(data) < 126:
        header.append(0x80 | len(data))
    elif len(data) < 65536:
        header.append(0x80 | 126)
        header.extend(struct.pack("!H", len(data)))
    else:
        header.append(0x80 | 127)
        header.extend(struct.pack("!Q", len(data)))
    mask = os.urandom(4)
    header.extend(mask)
    sock.sendall(bytes(header) + bytes(b ^ mask[i % 4] for i, b in enumerate(data)))

def call(method, params=None):
    global next_id
    next_id += 1
    message_id = next_id
    write_frame({"id": message_id, "method": method, "params": params or {}})
    deadline = time.time() + 10
    while time.time() < deadline:
        msg = read_frame()
        if msg.get("id") == message_id:
            if "error" in msg:
                raise SystemExit(f"{method} failed: {msg['error']}")
            return msg.get("result", {})
    raise SystemExit(f"{method} timed out")

call("Page.enable")
call("Runtime.enable")
call("Emulation.setDeviceMetricsOverride", {
    "width": width,
    "height": height,
    "deviceScaleFactor": 1,
    "mobile": False,
    "screenWidth": width,
    "screenHeight": height,
})
call("Page.navigate", {"url": url})

deadline = time.time() + 20
while time.time() < deadline:
    result = call("Runtime.evaluate", {
        "expression": "({ready: document.documentElement.dataset.ready, fatal: document.documentElement.dataset.fatal || ''})",
        "returnByValue": True,
    })
    value = result.get("result", {}).get("value", {})
    if value.get("fatal"):
        raise SystemExit(value["fatal"])
    if value.get("ready") == "true":
        break
    time.sleep(0.05)
else:
    raise SystemExit("renderer readiness marker timed out")

shot = call("Page.captureScreenshot", {"format": "png", "fromSurface": True, "captureBeyondViewport": False})
with open(out, "wb") as f:
    f.write(base64.b64decode(shot["data"]))
sock.close()
PY

  if [ ! -f "$out" ]; then
    printf 'missing output: %s\n' "$out" >&2
    exit 1
  fi
  local actual_w actual_h
  actual_w="$(sips -g pixelWidth "$out" 2>/dev/null | awk '/pixelWidth/ { print $2 }')"
  actual_h="$(sips -g pixelHeight "$out" 2>/dev/null | awk '/pixelHeight/ { print $2 }')"
  if [ "$actual_w" != "$width" ] || [ "$actual_h" != "$height" ]; then
    printf 'bad dimensions for %s: expected %sx%s, found %sx%s\n' "$out" "$width" "$height" "${actual_w:-?}" "${actual_h:-?}" >&2
    exit 1
  fi
  printf 'saved %s (%sx%s)\n' "${out#$REPO_ROOT/}" "$width" "$height"
}

while IFS= read -r id; do
  [ -n "$id" ] || continue
  render_one "$id" 8 1240 1376 "$REPO_ROOT/assets/jokers/cards/joker_$id.png"
  render_one "$id" 1 155 172 "$REPO_ROOT/assets/jokers/previews/joker_$id.png"
done <<EOF
$IDS
EOF
