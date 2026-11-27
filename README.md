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

`loom/assets/live.mjs` exports `attachLive(root, {endpoint, id, version, csrf})`. It sends same-origin JSON events from `button[data-live-event]`, handles stale versions without replay, and reconciles the component subtree using validated DOM nodes, not HTML strings. Only a conservative fragment subset is supported. One event may be in flight; extra events are dropped. Applications must serve the module and bootstrap session configuration. Node tests use a DOM stub, not an actual browser. Compatible nodes are reused; stable sibling keys use `data-live-key`. Unchanged input defaults preserve local edits, changed defaults reset the control. Keyed moves and replacement of incompatible nodes may lose focus; this is not a general virtual DOM or controlled form implementation. Server push and reconnect remain outstanding.

### Live Counter

Run `racket examples/live-counter/app.rkt` and visit http://127.0.0.1:8080/. This localhost example serves the browser runtime, mounts independent session-owned counters and updates the component without navigation. HTTP smoke and Chromium acceptance tests are configured in CI. Reloading mounts a new instance; expired instances are reclaimed on subsequent registry access. Not production-ready.

### Live state recovery

`make-live-snapshot-handler` provides a read-only POST JSON endpoint accepting `{id}` with the same session cookie and `X-Loom-CSRF` header as event requests. Configure `snapshotEndpoint` in `attachLive` and call `client.resync()` to retrieve the authoritative view and version after an ambiguous network failure. Events are never automatically replayed. The Live Counter includes a Refresh state control. Expired instances require remounting; automatic reconnect and server push are not implemented.

Opt in with `autoRecover: true` and `onRecovered` in `attachLive`. Failed event requests block further events until a read-only snapshot succeeds (when configured). Recovery retries at 250, 1000 and 3000 ms after successive failures; an online event starts a new retry cycle. Disposal cancels retries. Try `/?auto=1` in Live Counter. This does not replay mutations or remount expired instances and is not WebSocket reconnect.

### Live invalidation bus

`loom/live-bus` provides bounded, process-local topic subscriptions and coalescing change notifications. Trusted application code must authorize topic membership before subscribing; owner IDs control unsubscribe and bulk revocation, not topic access by themselves. One consumer per subscription uses `sync` on `live-next-evt`, obtaining `changed` or `closed`. Notifications carry no payload and are not durable; readers fetch authoritative state after invalidation. Explicit cleanup is required. Network transport and automatic session revocation are not included.

### Live HTTP notifications

`loom/live-notify` exports `make-live-notification-handler`. It accepts a POST JSON `{id}` with the session cookie and `X-Loom-CSRF` header. A trusted `(session id)` callback authorizes instance ownership and resolves a topic; authorization is checked again after the wait. The temporary subscription is released on exit. The default wait is 15 seconds (maximum 25). Responses are `changed` or `timeout`; both require reading authoritative state because notifications between requests are not durable. Capacity exhaustion returns 503. WebSocket transport is not included yet.

`loom/assets/live-notify.mjs` exports `subscribeLive({endpoint,id,csrf,refresh,onError})`. Serve it as a same-origin module and pass `refresh: () => client.resync()` or an application-specific authoritative read. Both timeout and change trigger refresh. Failures retry with exponential delay capped at 30 seconds; authorization/invalid-instance failures stop polling. Call `dispose()` on teardown. No automatic event replay. Shared-state browser integration is exercised by Live Taskboard.

### Live Taskboard

Run `racket examples/live-taskboard/app.rkt` and open `http://127.0.0.1:8080/` in two independent browser sessions. Add, toggle and delete shared SQLite tasks; notifications trigger authoritative snapshot refresh without navigation. Set `LOOM_LIVE_BOARD_DB` for a persistent database path; otherwise a temporary database file is used. This is a local, intentionally shared guest board, not a production authenticated application. The demo commits database effects before rendering; failed rendering does not undo committed changes. Browser polling can delay updates and does not guarantee durable delivery. Chromium acceptance is configured for both examples.

### Authentication and authorization policy

`loom/auth` provides request-scoped principal resolution, `require-authentication`, `require-role` and `require-resource`. Install `authentication-middleware` outside protected handlers. Resolve trusted session data on every request. Unauthenticated requests receive 401, insufficient roles 403, absent or denied resources 404. See [session transitions](docs/session-transition.md) and [resource policies](docs/resource-policy.md). Credential verification and complete login flows remain application responsibilities.
