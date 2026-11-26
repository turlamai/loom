# Loom

The modern full-stack web framework for [Racket](https://racket-lang.org/).

**Human-first. Agent-native. Racket-first.**

**English** · [简体中文](README.zh-CN.md)

[![CI](https://github.com/turlamai/loom/actions/workflows/ci.yml/badge.svg)](https://github.com/turlamai/loom/actions/workflows/ci.yml)

Loom is an early development prototype, not a production-ready framework. It aims to combine composable server-rendered components, explicit routes, secure defaults and optional live interactions without requiring a frontend build pipeline.

## Start here

From a checkout with Racket installed:

```sh
raco pkg install --auto --name loom-dev --link .
raco test loom/main.rkt
racket examples/hello.rkt
```

Open http://127.0.0.1:8080/. Package catalog availability is not verified.

## Documentation

- [Architecture and roadmap](docs/architecture.md)
- [Engineering contract](AGENTS.md)
- [Website hosting](docs/hosting.md)

The planned homepage is https://loom.jrtx.site/. Rivet and Glaze remain independent desktop frameworks.
