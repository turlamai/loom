# Architecture and delivery plan

Status: proposal; interfaces remain unstable.

## Principles

Racket-first, explicit application state, composable functions, convention without hidden effects. SSR is the baseline; live updates are progressive enhancement. Use official web-server and db; optional JavaScript browser runtime. Permit, Commerce and Keel are optional integrations.

## Milestones

- 0.1: HTTP adapter, routing, HTML, CLI, tests, configuration and security baseline. Verify clean install and real HTTP requests.
- 0.2: SQLite/PostgreSQL, migrations, forms, sessions, authentication and OpenAPI. Verify CRUD, CSRF, authorization and rollback.
- 0.3: live components, authenticated events, bounded state, reconnect and backpressure. Verify browser and multi-client behavior.
- 0.5: jobs, mail, storage, admin and optional commercial integrations. Verify deployable SaaS example.
- 1.0: compatibility, security review, performance, operations and bilingual guides.

Package catalog name is not yet verified. Long-lived workflows use durable explicit state; continuations are optional and short-lived.
