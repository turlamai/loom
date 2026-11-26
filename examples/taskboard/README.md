# Loom Taskboard

**English** · [简体中文](README.zh-CN.md)

A local, single-user SQLite demonstration of routing, HTML, forms, model validation, migration and persistence. Run from the installed checkout:

```sh
racket examples/taskboard/app.rkt
```

Open http://127.0.0.1:8080/. The database defaults to `taskboard.db`; set `LOOM_TASKBOARD_DB` to use another file and `LOOM_TASKBOARD_PORT` to change the port. Run `bash examples/taskboard/smoke.sh` on Linux with curl and Python 3 for HTTP acceptance.

This is a localhost demonstration, not a deployable multi-user application. The process-wide form token is not a session-bound CSRF implementation. No authentication, authorization, production transport limits or concurrent migration support.
