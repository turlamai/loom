#!/usr/bin/env bash
set -euo pipefail
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
cd "$dir"
if raco loom migrate --json > missing.out 2> missing.err; then
  echo "missing migration module unexpectedly succeeded" >&2; exit 1
fi
cat > migrations.rkt <<'RKT'
#lang racket/base
(require loom/db loom/migrate)
(provide connect migrations)
(define (connect) (open-sqlite "app.db"))
(define migrations
  (list (migration 1 "create tasks"
          (lambda (c) (query-exec c "CREATE TABLE tasks (id INTEGER PRIMARY KEY)")))
        (migration 2 "seed"
          (lambda (c) (query-exec c "INSERT INTO tasks VALUES (1)")))))
RKT
raco loom migrate --json > first.json
raco loom migrate --json > second.json
raco loom inspect --json > inspect.json
python3 - <<'PY'
import json
assert json.load(open("first.json")) == {"schema_version": 1, "applied": [1,2]}
assert json.load(open("second.json")) == {"schema_version": 1, "applied": []}
assert json.load(open("inspect.json"))["migrations"] is True
PY
test "$(raco loom migrate)" = "Database is up to date."
python3 - <<'PY'
import sqlite3
with sqlite3.connect("app.db") as c:
    assert c.execute("SELECT id FROM tasks").fetchall() == [(1,)]
    assert c.execute("SELECT count(*) FROM loom_schema_migrations").fetchone() == (2,)
PY
# A changed history must fail without modifying the database.
sed -i 's/create tasks/changed history/' migrations.rkt
if raco loom migrate --json > changed.out 2> changed.err; then
  echo "changed history unexpectedly succeeded" >&2; exit 1
fi
python3 - <<'PY'
import sqlite3
with sqlite3.connect("app.db") as c:
    assert c.execute("SELECT id FROM tasks").fetchall() == [(1,)]
    assert c.execute("SELECT description FROM loom_schema_migrations WHERE version=1").fetchone() == ("create tasks",)
PY
