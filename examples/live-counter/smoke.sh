#!/usr/bin/env bash
set -euo pipefail
tmp=$(mktemp -d)
export LOOM_LIVE_PORT=18881
racket examples/live-counter/app.rkt >"$tmp/server.log" 2>&1 &
pid=$!
trap 'kill "$pid" 2>/dev/null || true; cat "$tmp/server.log"; rm -rf "$tmp"' EXIT
base=http://127.0.0.1:18881
for i in $(seq 1 40); do
  if curl -fsS -c "$tmp/cookies" "$base/" >"$tmp/page"; then break; fi
  sleep 1
done
grep -q 'Live Counter' "$tmp/page"
curl -fsS "$base/live.mjs" >"$tmp/live.mjs"
grep -q 'export function attachLive' "$tmp/live.mjs"
curl -fsS "$base/boot.mjs" >"$tmp/boot.mjs"
grep -q 'attachLive' "$tmp/boot.mjs"
python3 - "$tmp/page" "$tmp" <<'PY'
import json,sys,pathlib
from html.parser import HTMLParser
class Page(HTMLParser):
    def handle_starttag(self, tag, attrs):
        a=dict(attrs)
        if a.get("id")=="live":
            self.live=a
p=Page()
p.feed(pathlib.Path(sys.argv[1]).read_text())
d=pathlib.Path(sys.argv[2])
(d/"csrf").write_text(p.live["data-csrf"])
(d/"event").write_text(json.dumps(dict(id=p.live["data-id"],version=0,event="inc",payload=None)))
PY
csrf=$(cat "$tmp/csrf")
test "$(curl -s -o "$tmp/result" -w '%{http_code}' -b "$tmp/cookies" -H "X-Loom-CSRF: $csrf" -H 'Content-Type: application/json' --data-binary @"$tmp/event" "$base/live")" = 200
python3 - "$tmp/result" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
assert d["version"]==1 and d["status"]=="ok"
assert d["view"]["children"][0]["children"][0]["children"]==["1"]
PY
test "$(curl -s -o /dev/null -w '%{http_code}' -b "$tmp/cookies" -H "X-Loom-CSRF: $csrf" -H 'Content-Type: application/json' --data-binary @"$tmp/event" "$base/live")" = 409
test "$(curl -s -o /dev/null -w '%{http_code}' -H "X-Loom-CSRF: $csrf" -H 'Content-Type: application/json' --data-binary @"$tmp/event" "$base/live")" = 403
echo "Live Counter HTTP smoke passed"
