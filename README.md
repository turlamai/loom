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

## Forms and security middleware

`loom/forms` parses bounded URL-encoded forms and preserves repeated fields. `loom/security` offers opt-in `security-headers` middleware with conservative CSP, frame denial, nosniff and referrer policy defaults. Existing application headers are respected. These helpers do not implement CSRF, authentication, TLS or transport-level limits.

## Cookies

`loom/cookies` exposes `cookie-values`, `set-cookie-header` and `clear-cookie-header`. Cookies default to host-only, Secure, HttpOnly and SameSite=Lax. Duplicate valid request values remain visible; applications must reject ambiguous session cookies. Cookie values are not signed or encrypted by these helpers. Use HTTPS in production; explicit non-Secure cookies are for local development only.

## Sessions

`loom/session` provides a bounded, synchronized in-memory store with cryptographically random opaque IDs, absolute expiry, deletion and rotation. Use immutable session values; the store does not copy them. It is process-local and loses state on restart. Cookie binding, authentication, CSRF and distributed storage are not implemented here.

## Database (development preview)

`loom/db` wraps the official Racket database library with SQLite and PostgreSQL connection helpers, scoped connection cleanup, explicit transactions and parameterized queries. SQLite transaction commit and rollback are covered by unit tests; PostgreSQL integration, pooling and migrations are not yet verified. Keep credentials outside source code and configure TLS for production.

## Migrations (development preview)

`loom/migrate` applies consecutive numbered migrations in a transaction and records their versions and descriptions. Reapplying the same plan is a no-op; truncated or renamed histories are rejected. Run migrations from a single deployment process. Migration code is trusted and must not commit independently. This is not a checksum, down-migration or distributed locking mechanism. SQLite tests cover rollback; PostgreSQL requires integration verification.
