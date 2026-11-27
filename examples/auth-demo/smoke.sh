#!/usr/bin/env bash
set -euo pipefail
tmp=$(mktemp -d)
export LOOM_AUTH_PORT=18883 LOOM_DEMO_PASSWORD=local-test-password-only
racket examples/auth-demo/app.rkt >"$tmp/server.log" 2>&1 &
pid=$!
trap 'kill "$pid" 2>/dev/null || true; cat "$tmp/server.log"; rm -rf "$tmp"' EXIT
base=http://127.0.0.1:18883
for i in $(seq 1 40); do
  if curl -fsS --max-time 5 -c "$tmp/a" "$base/session" >"$tmp/session"; then break; fi
  sleep 1
done
csrf=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["csrf"])' <"$tmp/session")
cp "$tmp/a" "$tmp/old"
request() {
  curl -sS --max-time 10 -o "$tmp/result" -w '%{http_code}' "$@"
}
login() {
  request -b "$tmp/a" -c "$tmp/a" -H 'Content-Type: application/json' -H "X-Loom-CSRF: $1" --data-binary "$2" "$base/login"
}
test "$(request -b "$tmp/a" "$base/account")" = 401
test "$(login wrong '{"username":"alice","password":"local-test-password-only"}')" = 403
test "$(login "$csrf" '{"username":"unknown","password":"wrong"}')" = 401
test "$(login "$csrf" '{"username":"alice","password":"wrong"}')" = 401
test "$(login "$csrf" '{"username":"ALICE","password":"local-test-password-only"}')" = 200
next=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["csrf"])' <"$tmp/result")
test "$csrf" != "$next"
test "$(request -b "$tmp/old" "$base/account")" = 401
test "$(request -b "$tmp/a" "$base/account")" = 200
python3 -c 'import json,sys; assert json.load(sys.stdin)["user"]=="alice"' <"$tmp/result"
test "$(request -c "$tmp/b" "$base/session")" = 200
test "$(request -b "$tmp/b" "$base/account")" = 401
test "$(request -b "$tmp/b" -H "X-Loom-CSRF: $next" -X POST "$base/logout")" = 403
test "$(request -b "$tmp/a" -H "X-Loom-CSRF: $csrf" -X POST "$base/logout")" = 403
cp "$tmp/a" "$tmp/authenticated"
test "$(request -b "$tmp/a" -c "$tmp/a" -H "X-Loom-CSRF: $next" -X POST "$base/logout")" = 200
test "$(request -b "$tmp/authenticated" "$base/account")" = 401
test "$(request -b "$tmp/a" -c "$tmp/a" "$base/session")" = 200
csrf=$(python3 -c 'import json,sys; print(json.load(sys.stdin)["csrf"])' <"$tmp/result")
for i in 1 2 3; do
  test "$(login "$csrf" '{"username":"alice","password":"wrong"}')" = 401
done
test "$(login "$csrf" '{"username":"alice","password":"local-test-password-only"}')" = 429
echo "Authentication HTTP smoke passed"
