# Loom

The modern full-stack web framework for [Racket](https://racket-lang.org/).

**Human-first. Agent-native. Racket-first.**

**English** · [简体中文](README.zh-CN.md)

[![CI](https://github.com/turlamai/loom/actions/workflows/ci.yml/badge.svg)](https://github.com/turlamai/loom/actions/workflows/ci.yml)

Loom is an early development prototype, not a production-ready framework. It aims to combine composable server-rendered components, explicit routes, secure defaults and optional live interactions without requiring a frontend build pipeline.

## Start here

From a checkout with Racket installed:

```sh
raco pkg install --auto --name loom-dev --link "$(pwd)"
raco test loom/main.rkt
racket examples/hello.rkt
```

Open http://127.0.0.1:8080/. Package catalog availability is not verified.

## Documentation

- [Architecture and roadmap](docs/architecture.md)
- [Engineering contract](AGENTS.md)
- [Website hosting](docs/hosting.md)

The planned homepage is https://loom.jrtx.site/. Rivet and Glaze remain independent desktop frameworks.

## CLI (development preview)

```sh
raco loom new hello
cd hello
raco loom doctor
raco loom inspect --json
raco loom test
raco loom dev
```

## HTML components

```racket
(require loom loom/html)
(define-component (welcome name)
  (element 'h1 "Hello, " name))
(html-response (page-layout #:title "Welcome" (welcome "Racket")))
```

The constrained builder accepts text and validated elements, rejects executable tags and event attributes, and checks URL schemes. Raw `html-response` X-expressions remain a trusted-code escape hatch. This is not a general HTML sanitizer or a complete security policy.

## HTTP helpers (development preview)

`loom/http` provides JSON responses, bounded JSON parsing, query and header lookup preserving repeated values, and local redirects. The JSON size limit applies after the web server has read the body; configure transport limits separately. Parsing errors need application-level HTTP error handling.
