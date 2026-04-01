# Shiso Framework Roadmap

## Completed

- **Models** — `define-model`, field-type constructors, metadata registry, introspection API
- **Validators** — composable validators, auto-derivation from model metadata
- **Forms** — field classes, model-form generation, validation, rendering
- **Admin** — registry, CRUD views, components, routing, module wrapper

## Near-term

### Solidify Forms & Admin
- End-to-end form testing in a real app (submit, validate, save, edit, error display)
- Fix data pipeline issues (key formats, checkbox parsing, date handling)
- Admin template rework: responsive layout, sortable tables, row actions, flash messages
- Wire up unused admin config: filtering, search, pagination, ordering, fieldsets, readonly

### Settings & Configuration
- Centralized `shiso:configure` with `:database-url`, `:secret-key`, `:debug`, etc.
- Auto-establish Mito DB connection from `:database-url`
- Access via `(shiso:setting :key)`

### Middleware, Sessions & CSRF
- Wrap Lack middleware in `define-application` `:middleware` option
- Session accessors: `session-value`, `delete-session` (backed by Lack)
- Auto-include CSRF hidden field in form rendering

### Authentication & Authorization
- `define-user-model` with password hashing (bcrypt via Ironclad)
- `authenticate`, `login`, `logout`, `current-user`
- Permission guards: `login-required`, `staff-required`
- Admin restricted to staff users

### Error Handling
- Debug mode: backtrace + request info (via `lack-middleware-backtrace`)
- Production mode: custom 404/500 pages
- `define-error-handler` hook

## Medium-term

### Database Migrations
- `shiso:migrate` — run Mito auto-migrations for all registered models
- `shiso:show-migrations` — preview pending SQL

### Testing Utilities
- Test client: send requests through Lack app without a server
- `with-test-db` — temporary SQLite DB with auto-migration and cleanup

### CLI / Management Commands
- `shiso start`, `migrate`, `collectstatic`, `createsuperuser`, `make-module`, `shell`
- Evaluate clingon vs adopt for CLI framework

### File Uploads
- `file-field` form field, local filesystem storage, upload validation

## Long-term

### Email
- SMTP delivery via `cl-smtp`, configured through `shiso:configure`

### Caching
- Key-value cache with in-memory and Redis backends

### Internationalization
- Translation keys for form labels and help text

### Project Scaffolding
- `make-shiso-system` generates a complete project skeleton with vendored admin
