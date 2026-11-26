#!/usr/bin/env bash
set -euo pipefail
tmp=$(mktemp -d)
export LOOM_TASKBOARD_DB="$tmp/tasks.db" LOOM_TASKBOARD_PORT=18880
racket examples/taskboard/app.rkt >"$tmp/server.log" 2>&1 &
pid=$!
trap 'kill "$pid" 2>/dev/null || true; cat "$tmp/server.log"; rm -rf "$tmp"' EXIT
base=http://127.0.0.1:18880
for i in $(seq 1 40); do
  if curl -fsS -c "$tmp/cookies" -D "$tmp/headers" "$base/" >"$tmp/page"; then break; fi
  sleep 1
done
grep -q 'Taskboard' "$tmp/page"
grep -qi "^Cache-Control: no-store" "$tmp/headers"
curl -fsS -c "$tmp/other" "$base/" >"$tmp/other-page"
token=$(python3 - "$tmp/page" <<'PY'
from html.parser import HTMLParser
import sys
class Parser(HTMLParser):
    token = None
    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if tag == "input" and a.get("name") == "csrf":
            self.token = a["value"]
p = Parser()
p.feed(open(sys.argv[1]).read())
assert p.token
print(p.token)
PY
)
test "$(curl -b "$tmp/cookies" -s -o /dev/null -w '%{http_code}' -d 'title=bad' "$base/tasks")" = 403
test "$(curl -b "$tmp/other" -s -o /dev/null -w '%{http_code}' -d "csrf=$token&title=bad" "$base/tasks")" = 403
test "$(curl -s -o /dev/null -w '%{http_code}' -d "csrf=$token&title=bad" "$base/tasks")" = 403
test "$(curl -b "$tmp/cookies" -s -o /dev/null -w '%{http_code}' --data-urlencode "csrf=$token" --data-urlencode 'title=Test <script>' "$base/tasks")" = 303
curl -b "$tmp/cookies" -fsS "$base/" >"$tmp/page"
grep -q 'Test &lt;script&gt;' "$tmp/page"
id=$(grep -oE '/tasks/[0-9a-f]{32}/toggle' "$tmp/page" | head -1 | cut -d/ -f3)
test -n "$id"
test "$(curl -b "$tmp/cookies" -s -o /dev/null -w '%{http_code}' -d "csrf=$token" "$base/tasks/$id/toggle")" = 303
curl -b "$tmp/cookies" -fsS "$base/" | grep -q 'Done'
test "$(curl -b "$tmp/cookies" -s -o /dev/null -w '%{http_code}' -d "csrf=$token" "$base/tasks/$id/delete")" = 303
curl -b "$tmp/cookies" -fsS "$base/" >"$tmp/page"
! grep -q 'Test &lt;script&gt;' "$tmp/page"
test "$(curl -b "$tmp/cookies" -s -o /dev/null -w '%{http_code}' "$base/tasks")" = 405
echo "Taskboard HTTP smoke passed"
