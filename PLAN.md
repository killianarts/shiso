# Shiso Framework — Complete Roadmap

## Context

This plan updates `vendored/shiso/PLAN.md`. The original plan covered Models,
Validators, Forms, and Admin (Phases 1-4). All four are implemented and tested
(96+ test cases), but forms haven't been exercised in a real application yet
and the admin templates need rework. This update adds solidification work and
new phases to build toward a complete Django-inspired framework.

## Vision

Shiso is a Django-inspired Common Lisp web framework where models are the
central abstraction. A single `define-model` form propagates through the entire
stack: database schema, form generation, input validation, and admin CRUD views.

**Philosophy:** Prefer simplicity over complexity, direct over indirect. Modules
(including the admin) are designed to be vendored and specialized rather than
extended through override mechanisms. See `ADMIN-PLAN.org` for the rationale.

## What's Built (Phases 1-4 — COMPLETE)

- **Phase 1: Models** — `define-model`, metadata registry, introspection API
- **Phase 2: Validators** — composable validators, auto-derivation from metadata
- **Phase 3: Forms** — field classes, model-form generation, validation, rendering
- **Phase 4: Admin** — registry, CRUD views, components, routing, module wrapper

All tested. What follows is solidification of this work plus new capabilities.

---

## Phase 5: Solidify Forms & Admin

### Goal

Exercise the forms system in a real application, fix rendering issues, and
make the admin templates production-quality.

### 5.1 Forms Testing & Fixes

Test forms end-to-end in the almightylisp.com application:
- Create a model with `define-model`, generate a form with `make-model-form`
- Submit via browser, verify `parse-body-params` → `validate-form` → `save-form`
- Test edit flow: load instance into form, submit changes, verify update
- Verify error display: submit invalid data, confirm per-field errors render
- Test each field type renders correctly (char, text, integer, boolean, choice, date, email)

Fix any issues discovered. Known areas to check:
- Form data key format (keyword vs string vs symbol) through the pipeline
- Boolean field parsing (checkbox sends no value when unchecked)
- Choice field rendering with pre-selected values
- Date field parsing and display format

### 5.2 Admin Template Rework

The current admin components (`ac-admin-page`, `ac-admin-table`, etc.) need
rework for usability:
- Improve layout: proper responsive design, better typography
- Table: sortable columns, row actions (edit/delete), empty state
- Forms: fieldset grouping (use `admin-fieldsets` config), proper error styling
- Flash messages: success/error after create/edit/delete operations
- Navigation: highlight current section, breadcrumbs

### 5.3 Wire Up Unused Admin Config

Several `admin-config` slots exist but aren't used in views:
- `list-filter` — add filter dropdowns to list view
- `search-fields` — add search box to list view
- `ordering` — apply default ordering to list queries
- `readonly` — render fields as read-only in edit forms
- `per-page` + pagination — add pagination to list view
- `fieldsets` — group fields in create/edit forms

### Files
- `vendored/shiso/src/admin/components.lisp`
- `vendored/shiso/src/admin/views.lisp`
- `vendored/shiso/src/forms/rendering.lisp`
- Corresponding `org/` files

---

## Phase 6: Settings & Configuration

### Goal

A centralized configuration system so applications don't scatter `get-env`
calls everywhere.

### Design

A `shiso/settings` package with a settings hash table populated from
environment variables and/or a settings form:

```lisp
(shiso:configure
  :database-url (or (uiop:getenv "DATABASE_URL") "sqlite3:///db.sqlite3")
  :secret-key (uiop:getenv "SECRET_KEY")
  :debug t
  :allowed-hosts '("localhost" "almightylisp.com")
  :static-url "/static/"
  :timezone "UTC")
```

Access via `(shiso:setting :database-url)`. Unknown keys signal an error
in non-debug mode.

### Database Connection

Currently Mito connection is manual. `shiso:configure` should establish the
connection automatically from `:database-url`, parsing the URL into
`mito:connect-toplevel` arguments.

### Files
- `vendored/shiso/src/settings.lisp` (new)
- `vendored/shiso/org/src/settings.org` (new)
- Update `shiso.asd`, `package.lisp`

---

## Phase 7: Middleware Framework

### Goal

Expose Lack's middleware system through a clean Shiso API so users can compose
middleware without understanding Lack internals.

### Design

Lack already provides the middleware infrastructure. Shiso wraps it:

```lisp
(shiso:define-application my-app ()
  (:middleware
    (:session :store (lack.session.store.dbi:make-dbi-store ...))
    (:csrf)
    (:accesslog))
  (:modules
    ("" pages)
    ("/admin" admin)))
```

The `:middleware` option in `define-application` expands each entry into
the appropriate Lack middleware wrapper. This is sugar — users can still
use raw Lack middleware directly.

### Already Available in Lack
- `lack-middleware-session` — session management (memory, DBI, Redis backends)
- `lack-middleware-csrf` — CSRF token validation
- `lack-middleware-auth-basic` — HTTP Basic Auth
- `lack-middleware-accesslog` — request logging
- `lack-middleware-backtrace` — error page with backtrace
- `lack-middleware-deflater` — response compression
- `lack-middleware-dbpool` — database connection pooling

### Files
- Modify `vendored/shiso/src/routing.lisp` — extend `define-application`
- `vendored/shiso/org/src/routing.org`

---

## Phase 8: Sessions & CSRF

### Goal

Integrate Lack's session and CSRF middleware into Shiso's API and make them
easy to use in controllers and templates.

### Design

#### Sessions
Lack's `lack-middleware-session` stores sessions in `(getf env :lack.session)`.
Shiso wraps this:

```lisp
;; In a controller:
(shiso:session-value :user-id)
(setf (shiso:session-value :user-id) 42)
(shiso:delete-session)
```

Session storage backends (all provided by Lack):
- Memory (default, development)
- DBI (production, uses existing DB connection)
- Redis (high-performance, via `cl-redis`)

#### CSRF
Lack's `lack-middleware-csrf` provides `csrf-token` and `csrf-html-tag`.
Shiso wraps:

```lisp
;; In a template:
(shiso:csrf-field)  ; → <input type="hidden" name="_csrf_token" value="...">

;; Forms rendering auto-includes CSRF field when method is POST
```

The form rendering system (`render-form`) should automatically include the
CSRF hidden field.

### Dependencies
- `lack-middleware-session` (vendored)
- `lack-middleware-csrf` (vendored)
- `lack-session-store-dbi` (for production sessions)

### Files
- `vendored/shiso/src/sessions.lisp` (new)
- `vendored/shiso/src/csrf.lisp` (new — or combine with sessions)
- Modify `vendored/shiso/src/forms/rendering.lisp` — auto-include CSRF
- Modify `vendored/shiso/src/requests.lisp` — session accessors
- Update `shiso.asd`, `package.lisp`

---

## Phase 9: Authentication & Authorization

### Goal

User model, login/logout, password hashing, and permission checking. The
admin module requires this to restrict access.

### Design

#### User Model

A built-in `user` model (or a `define-user-model` macro that extends any
model with auth fields):

```lisp
(shiso/auth:define-user-model user
  ((username :col-type (:varchar 150) :unique t)
   (email    :col-type (:varchar 254))
   (is-staff :col-type :boolean :initform nil)
   (is-superuser :col-type :boolean :initform nil)))
```

Password is stored hashed (bcrypt via Ironclad). Not exposed as a regular
model field.

#### Password Hashing

Ironclad is already vendored and provides bcrypt:

```lisp
(shiso/auth:make-password "raw-password")  ; → bcrypt hash string
(shiso/auth:check-password "raw" hash)     ; → t or nil
```

#### Login/Logout

```lisp
(shiso/auth:authenticate :username "foo" :password "bar")  ; → user or nil
(shiso/auth:login request user)   ; stores user-id in session
(shiso/auth:logout request)       ; clears session
(shiso/auth:current-user)         ; → user instance or nil
```

#### Permission Guards

```lisp
;; Decorator-style for controllers:
(shiso/auth:login-required 'my-controller)

;; In define-module or define-application:
(:middleware (:auth :login-url "/login"))

;; Staff-only (for admin):
(shiso/auth:staff-required 'admin-controller)
```

#### Admin Integration

The admin module wraps all views with `staff-required`. Only users with
`is-staff = t` can access the admin.

### Dependencies
- `ironclad` (vendored — bcrypt KDF)
- Sessions (Phase 8)

### Files
- `vendored/shiso/src/auth.lisp` (new)
- `vendored/shiso/org/src/auth.org` (new)
- Modify admin views to require staff auth
- Update `shiso.asd`, `package.lisp`

---

## Phase 10: Error Handling

### Goal

Structured error pages, condition handling, and debug mode with useful
error information during development.

### Design

- Debug mode (from settings): show backtrace, request info, local variables
- Production mode: render custom 404/500 pages
- `lack-middleware-backtrace` provides the debug page — integrate it
- Custom error page hook: `(shiso:define-error-handler 404 ...)`

### Files
- `vendored/shiso/src/errors.lisp` (new)
- `vendored/shiso/org/src/errors.org` (new)

---

## Phase 11: Database Migrations

### Goal

Wrap Mito's migration capabilities so schema changes are easy to apply.

### Design

Mito provides migration introspection:
- `mito:migrate-table` — auto-migrates a single table
- `mito:ensure-table-exists` — creates table if missing
- `mito:migration-expressions` — returns SQL for pending changes

Shiso wraps these into convenience functions:

```lisp
(shiso:migrate)           ; migrate all registered models
(shiso:migrate 'article)  ; migrate one model
(shiso:show-migrations)   ; show pending SQL without executing
```

This is lighter than Django's migration files approach — Mito compares
the live schema to the class definition and generates ALTER statements
on the fly. For v1 this is sufficient. File-based migrations can be
added later if needed.

### Files
- `vendored/shiso/src/migrations.lisp` (new)
- `vendored/shiso/org/src/migrations.org` (new)

---

## Phase 12: Testing Utilities

### Goal

A test client for writing integration tests against Shiso applications,
plus helpers for test database setup.

### Design

```lisp
(shiso/test:with-test-app (app)
  (let ((response (shiso/test:get app "/articles")))
    (assert-eql 200 (response-status response))
    (assert-search "Articles" (response-body response))))

(shiso/test:with-test-db ()
  (let ((article (mito:create-dao 'article :title "Test")))
    ...))
```

- Test client sends requests through the Lack app without starting a server
- `with-test-db` creates a temporary SQLite database, runs migrations, cleans up
- Response inspection helpers

### Dependencies
- `lisp-unit2` (already used)

### Files
- `vendored/shiso/src/test-utils.lisp` (new)
- `vendored/shiso/org/src/test-utils.org` (new)

---

## Phase 13: CLI / Management Commands

### Goal

A command-line interface for common tasks: starting the server, running
migrations, creating users, collecting static files.

### Design

Use an existing CL CLI library. Candidates:
- **clingon** — modern, well-maintained, subcommand support
- **adopt** — simpler, by Steve Losh
- **unix-opts** — lightweight getopt-style

Evaluate and pick one. Commands to implement:

```
shiso start              # start dev server
shiso migrate            # run migrations
shiso collectstatic      # collect static files
shiso createsuperuser    # create admin user
shiso make-module NAME   # scaffold a new module
shiso shell              # drop into REPL with app loaded
```

### Files
- `vendored/shiso/src/cli.lisp` (new)
- `vendored/shiso/org/src/cli.org` (new)

---

## Phase 14: File Uploads

### Goal

Support file upload fields in forms and models.

### Design

Lack/http-body already parses multipart form data. Shiso needs:
- A `file-field` form field class
- File storage abstraction (local filesystem initially)
- Model field type for file references (path stored in DB)
- Upload size/type validation

```lisp
(define-model document
  ((title :col-type (:varchar 200))
   (file  :col-type (:varchar 500) :widget :file
          :validators ((max-file-size (* 10 1024 1024))))))
```

### Files
- Modify `vendored/shiso/src/forms/fields.lisp` — add `file-field`
- `vendored/shiso/src/uploads.lisp` (new) — storage backend
- `vendored/shiso/org/src/uploads.org` (new)

---

## Phase 15: Email

### Goal

Send emails from the application (password resets, notifications, etc.).

### Design

Use `cl-smtp` for SMTP delivery. Shiso wraps with configuration from settings:

```lisp
(shiso:configure
  :email-host "smtp.example.com"
  :email-port 587
  :email-user "..."
  :email-password "...")

(shiso:send-mail
  :to "user@example.com"
  :subject "Welcome"
  :body (render-email-template ...))
```

### Dependencies
- `cl-smtp` (add to dependencies)

### Files
- `vendored/shiso/src/email.lisp` (new)
- `vendored/shiso/org/src/email.org` (new)

---

## Phase 16: Caching

### Goal

Cache expensive computations and database queries.

### Design

Simple key-value cache with pluggable backends:

```lisp
(shiso:cache-get "key")
(shiso:cache-set "key" value :ttl 300)
(shiso:with-cache ("expensive-query" :ttl 60)
  (mito:select-dao ...))
```

Backends:
- In-memory (development, default)
- Redis (production, via `cl-redis`)

### Dependencies
- `cl-redis` (optional, for Redis backend)

### Files
- `vendored/shiso/src/cache.lisp` (new)
- `vendored/shiso/org/src/cache.org` (new)

---

## Phase 17: Internationalization

### Goal

Support translated strings in templates and form labels.

### Design

Evaluate CL i18n libraries:
- `cl-locale` — locale-based string lookup
- `cl-i18n` — gettext-style translation

Integration with forms: `field-verbose-name` and `field-help-text` become
translation keys when i18n is enabled.

### Dependencies
- `cl-locale` or `cl-i18n` (evaluate and pick)

### Files
- `vendored/shiso/src/i18n.lisp` (new)
- `vendored/shiso/org/src/i18n.org` (new)

---

## Phase 18: Project Scaffolding

### Goal

A `make-shiso-system` function that generates a complete project skeleton,
including the admin module vendored into the user's project.

### Design

```lisp
(shiso:make-shiso-system "my-project"
  :directory #p"/path/to/projects/"
  :modules '(pages articles)
  :include-admin t)
```

Generates:
```
my-project/
  my-project.asd
  src/
    main.lisp           ; define-application, server start
    settings.lisp       ; shiso:configure form
    modules/
      pages/
        controllers.lisp
        routes.lisp
        templates/
        static/
      articles/
        controllers.lisp
        models.lisp
        routes.lisp
        templates/
        static/
      admin/              ; vendored copy of shiso's admin module
        ...
  static/
  t/
    ...
```

The admin module is copied (not referenced) into the project — users own it.

### Files
- Modify `vendored/shiso/src/scaffold.lisp`
- `vendored/shiso/org/src/scaffold.org`

---

## Implementation Priority

| Priority | Phase | Description | Key Dependencies |
|----------|-------|-------------|------------------|
| **NOW** | 5 | Solidify forms & admin | — |
| **HIGH** | 6 | Settings & configuration | — |
| **HIGH** | 7 | Middleware framework | Lack (vendored) |
| **HIGH** | 8 | Sessions & CSRF | Lack middleware (vendored) |
| **HIGH** | 9 | Auth & permissions | Ironclad (vendored), Phase 8 |
| **HIGH** | 10 | Error handling | Phase 6 (debug setting) |
| **MED** | 11 | Database migrations | Mito |
| **MED** | 12 | Testing utilities | lisp-unit2 |
| **MED** | 13 | CLI commands | clingon or adopt (new dep) |
| **MED** | 14 | File uploads | http-body (vendored) |
| **LOW** | 15 | Email | cl-smtp (new dep) |
| **LOW** | 16 | Caching | cl-redis (new dep, optional) |
| **LOW** | 17 | Internationalization | cl-locale or cl-i18n (new dep) |
| **LOW** | 18 | Project scaffolding | Phase 9 (admin to vendor) |

Phases 5-10 form the core of a production-capable framework.
Phases 11-14 are developer experience improvements.
Phases 15-18 are nice-to-haves that round out Django parity.

---

## Third-Party Dependencies Summary

### Already Vendored / Available
- **Lack middleware** — sessions, CSRF, basic auth, accesslog, backtrace, compression, dbpool
- **Ironclad** — bcrypt password hashing, full crypto suite
- **http-body** — multipart file upload parsing
- **Mito** — ORM with built-in migration support
- **cl-ppcre** — regex for validators
- **lisp-unit2** — testing

### New Dependencies Needed
| Library | Phase | Purpose |
|---------|-------|---------|
| clingon or adopt | 13 | CLI command framework |
| cl-smtp | 15 | Email delivery |
| cl-redis | 16 | Redis cache backend (optional) |
| cl-locale or cl-i18n | 17 | Internationalization |

---

## Open Questions (carried forward + new)

1. **Database configuration** — Settled: Phase 6 introduces `shiso:configure`
   with `:database-url` parsing.

2. **Migrations** — Mito handles auto-migration. Phase 11 wraps it. File-based
   migration history deferred.

3. **Authentication strategy** — Sessions + bcrypt (Phase 9). JWT deferred
   (no good CL library; build later if API auth is needed).

4. **CSS/Styling** — Admin uses inline CSS currently. Consider shipping a
   default CSS file in admin's `static/` directory. Tailwind optional.

5. **Template system** — Almighty-html (Lisp s-expressions) is the template
   system. No Jinja-style templates planned — this is a deliberate divergence
   from Django where CL's macro system provides equivalent power.
