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

## Model schemas (development preview)

```racket
(require loom/model)
(define-model user [name string #t] [age integer #f])
(validate-model user (hasheq 'name "Alice")) ; => '()
(model-schema user)
```

Model declarations support required fields, basic types, unknown-field rejection and JSON Schema metadata. They do not generate SQL, persist data, coerce input or enforce authorization. Define separate input/output schemas for sensitive fields.

## Model repositories (development preview)

`loom/repository` maps explicit models to existing SQLite tables with `make-repository`, `repository-insert!`, `repository-get`, `repository-update!`, `repository-delete!` and bounded `repository-list`. Supply an explicit required string or integer key; use migrations to create the table. Updates replace all non-key fields, absent optional fields become SQL NULL, and values are parameterized. No automatic ID generation, authorization, relationships or PostgreSQL repository support yet.

## Full-stack example

See [Taskboard](examples/taskboard/README.md) for a local SQLite application with real HTTP acceptance tests. Not a production multi-user deployment.

## Web sessions and CSRF (development preview)

`loom/session-http` binds opaque server-side sessions to host-only cookies and associates each session with a random CSRF token. `start-web-session` returns the ID, state and cookie header; applications explicitly attach headers and validate submitted tokens before mutations. `end-web-session` revokes the current session and returns a clearing header. Duplicate or malformed session cookie candidates are rejected. Production defaults require HTTPS. This is not authentication or automatic middleware; applications must enforce authorization, no-store caching for token-bearing responses, and CSRF validation on every relevant mutation. The store remains process-local.

`loom/csrf-middleware` provides opt-in URL-encoded form protection for unsafe HTTP methods, exposing validated fields through `current-verified-form`. Safe methods must remain read-only. Taskboard demonstrates independent browser sessions and no-store responses. JSON APIs require a separate policy.

## Live components (runtime preview)

`loom/live` introduces `make-live-component`, `live-mount`, `live-snapshot` and `live-dispatch!`. Components have an initial state factory, a pure renderer and explicitly registered event reducers. Each instance owns a version and serializes updates; stale versions and unknown events do not mutate state. Renderer failures do not commit the proposed state. Use immutable state and bounded, pure callbacks that never reenter the same instance. Browser transport, session ownership, lifecycle limits and DOM updates are not implemented yet.

`loom/live-registry` adds owner-scoped instance IDs, absolute expiry, global and per-owner capacity, explicit unmount and owner revocation. Owners must come from trusted authenticated server-side session context. Operations currently share a registry lock, including rendering; callbacks must be bounded and non-reentrant. The registry is process-local; session logout must explicitly revoke the owner. No HTTP transport yet.

`loom/live-http` provides a POST JSON event handler with session and CSRF validation, instance ownership, version conflicts, bounded buffered payloads and a structured render tree. Mount using the validated session's `web-session-csrf` as the internal owner key. Never accept a client-supplied owner. Use the handler on a separate JSON route, not behind URL-encoded form middleware. Responses are no-store. Browser runtime, automatic revocation, transport limits and server push remain outstanding.

### Browser runtime preview

`loom/assets/live.mjs` exports `attachLive(root, {endpoint, id, version, csrf})`. It sends same-origin JSON events from `button[data-live-event]`, handles stale versions without replay, and replaces the component subtree using validated DOM nodes, not HTML strings. Only a conservative fragment subset is supported. One event may be in flight; extra events are dropped. Applications must serve the module and bootstrap session configuration. Node tests use a DOM stub, not an actual browser. Focus preservation, server push, recovery and real browser acceptance remain outstanding.

### Live Counter

Run `racket examples/live-counter/app.rkt` and visit http://127.0.0.1:8080/. This localhost example serves the browser runtime, mounts independent session-owned counters and updates the component without navigation. HTTP smoke and Chromium acceptance tests are configured in CI. Reloading mounts a new instance; expired instances are reclaimed on subsequent registry access. Not production-ready.
