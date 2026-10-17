# Authentication Plan

Add session-based authentication to shiso. Unified user model (like
`django.contrib.auth`) — the admin module consumes it via an
`is-staff` flag; apps built on shiso can use it for their own end
users.

## Decisions

- **Mechanism:** session cookies (server-side state, cookie carries
  session id).
- **Credentials (v1):** email + password.
- **Scope:** unified `user` model. No `stripe-customer-id` on the base
  model — Stripe-specific fields belong on a subclass in a future
  billing module.
- **Hashing:** `cl-pass` (PBKDF2-SHA256, wraps ironclad).
- **Session store:** DB-backed from day one. Use Lack's built-in
  `lack/middleware/session/store/dbi` pointed at Mito's connection.
  DDL owned by a Mito model so it participates in the normal
  `ensure-table-exists` migration story.
- **CSRF:** `lack-middleware-csrf` (ships with Lack). No custom code.

## New module: `shiso/auth`

Peer to `models`/`forms`/`admin`. Files:

- `package.lisp` — `shiso/auth` package; exports `current-user`,
  `login-required`, `staff-required`, `login-user`, `logout-user`,
  `make-user`, `verify-password`, `hash-password`.
- `password.lisp` — thin wrapper over `cl-pass`. Two functions:
  `hash-password (plaintext)` and `verify-password (plaintext hash)`.
- `user.lisp` — Mito model `user`: `email` (unique, indexed),
  `password-hash`, `is-active` (default T), `is-staff` (default NIL),
  `last-login-at` (nullable). Email is the login identifier.
- `session.lisp` — Mito model `session` (id PK string, session_data
  text, Mito timestamps) so Lack's DBI store has a real table to
  read/write. Helpers `login-user`, `logout-user`, `current-user`
  (memoized on `*request*`).
- `guards.lisp` — `check-guard`, `login-required`, `staff-required`,
  module-level guard handling.
- `forms.lisp` — `login-form`, `signup-form` using `shiso/forms`.
- `controllers.lisp` — `login-view`, `logout-view`, `signup-view`.
- `routes.lisp` — `:GET/:POST /login`, `:POST /logout`,
  `:GET/:POST /signup`. Module name `shiso-auth`.

## Wiring changes

- `shiso.asd`: add `:cl-pass`, `:lack-middleware-session`,
  `:lack-middleware-csrf` to `:depends-on`. Add `auth` module
  *before* `admin` (admin will use it). Add `t/auth.lisp` to the
  test system.
- `server.lisp`: wrap the Clack app in a Lack middleware stack:
  session (DBI store) → CSRF → app. Session store connector returns
  Mito's current DBI connection.
- `requests.lisp`: expose session writes to controllers; memoize
  `current-user` per request.
- `admin/middleware.lisp`: gate admin via `:require :staff`. On
  failure: 302 → `/login?next=…` (anonymous) or 403 (authenticated
  non-staff).

## Guards — design

Three layers, in priority order:

### A. Module-level guard

`:guard` option on `define-module`. The module's
`lack/component:call` checks the guard before dispatching to a
route:

```lisp
(routing:define-module shiso-admin
  (:guard (:require :staff
           :on-anonymous (redirect "/login")
           :on-forbidden (status 403)))
  (:urls ...))
```

`:require` accepts:

- `:login` — any authenticated user
- `:staff` — authenticated + `is-staff = T`
- `:anonymous` — only for unauthenticated users (login/signup pages)
- `(:predicate fn-symbol)` — custom check (analog of
  `user_passes_test`)

### B. Per-route override

Within a guarded module, a route may opt out or tighten:

```lisp
(:GET  "/login"  'login-view "login" :guard :none)
(:POST "/super"  'nuke       "nuke"  :guard (:predicate is-superuser-p))
```

### C. Per-controller decorator

For controllers defined outside a routing module, or for finer
control:

```lisp
(define-controller dashboard (req)
  :require :login
  ...body...)
```

### Failure responses (shared)

- Anonymous + login required → 302 `/login?next=<current-url>`;
  controller honours `next` after login.
- Authenticated but lacks permission → 403.
- Authenticated user hitting `:anonymous`-only page → 302 to
  `*post-login-redirect*` (default `/`).

All three layers route through one `check-guard` function.

## Out of scope for v1

- Password reset (needs mailer)
- Email verification
- Remember-me / persistent cookies
- Rate limiting on login attempts
- Stripe Customer creation / webhooks / billing
- Permission objects (Django's `Permission` / groups) — `is-staff`
  is enough for v1

## Implementation order

1. `shiso.asd` — deps + auth module entry + test entry
2. `shiso/auth` package + user model + session model + password
   helpers
3. Server middleware stack (session + CSRF) and request integration
4. Guards (module-level + per-controller)
5. Login/logout/signup forms, controllers, routes
6. Admin module wired to `:require :staff`
7. Tests (`t/auth.lisp`)
