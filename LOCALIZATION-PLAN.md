# Localization for Shiso (Fluent backend)

Add request-scoped translations by wrapping [fosskers/fluent](https://github.com/fosskers/fluent). Shiso owns locale-on-the-request, catalog merge, and missing-key policy. Fluent owns “key + named args → string,” including CLDR plurals inside `.ftl` files.

This replaces the Phase 17 stub in `PLAN.md` (`cl-locale` vs `cl-i18n`). Datetime display localization (`shiso:l`, CLDR patterns, Fluent `DATETIME`) is explicitly **out of v1**. Keep `local-time` for parsing, storage, and HTML widget values.

## Goals

- Translate admin chrome, auth forms, validator messages, and form labels/help without evaluating locale at `define-model` / `defclass` time.
- Let applications add `.ftl` catalogs per module, overlaying framework strings.
- Negotiate locale per request (cookie → `Accept-Language` → default) without mutating a global Fluent struct (Woo is multithreaded).
- English-only apps keep working with no catalogs: missing keys render the Lisp fallback string (or the id).

## Non-goals (v1)

- URL prefixes (`/ja/login`) and translated path segments.
- Fluent `DATETIME` / `NUMBER` completeness; locale-aware date *display*.
- Content translation (translating model *instance* data).
- GNU gettext / `.po` / extraction scanners.
- `gettext_lazy` proxy objects.
- Exporting a function named `t` (that is `cl:t`).

---

## Key decisions

### 1. Wrap Fluent; do not expose it

Public API lives in `shiso/i18n` and is re-exported from `shiso`:

| Symbol | Role |
|---|---|
| `translate` | Lookup. `(translate "auth-email")`, `(translate "validators-max-length" :n 200)` |
| `with-locale` | `unwind-protect` / `let` bind of `*locale*` |
| `current-locale` | Request (or `with-locale`) locale |
| `load-localisations` | Build the process-wide Fluent context from locale trees |
| `available-locales` | Locales present in loaded catalogs, plus the default |

Apps never call `fluent:resolve`. Plurals are not a second Lisp API: pass `:count` (or whatever the message names) and let FTL selectors branch.

### 2. Store msgids; translate at use time

`define-model` continues to store strings on metadata. `make-login-form` continues to store `:label "…"`. Translation happens in renderers and in validators *during the request*, when `*locale*` is bound.

No lazy proxy. The footgun to document: do not call `translate` in a `defparameter` or at macro-expansion of `define-model`.

### 3. Keys are Fluent IDs; English can still live in Lisp

Fluent IDs are `[a-zA-Z][a-zA-Z0-9_-]*`. `"This field is required."` cannot be a key.

Convention:

- **Framework code** uses explicit IDs (`auth-email`, `validators-not-blank`, `admin-save`) and ships `locale/en-US/*.ftl` with the English text.
- **App model fields:** the Fluent id is derived from the **model name + slot name**, not from the `:verbose-name` string. `:verbose-name` is the English *fallback label* (what you already write for forms/admin). The catalog value for that id is the translation of that label.

  Example: model `question`, slot `question-text`, `:verbose-name "Question text"`.

  | Piece | Value |
  |---|---|
  | Derived id | `question-question-text` |
  | English fallback (Lisp) | `"Question text"` |
  | `locale/ja-JP/polls.ftl` | `question-question-text = 質問` |

  Help text uses `question-question-text-help` the same way. Renaming `:verbose-name` to `"The poll prompt"` does **not** change the id; translators still target `question-question-text`. If the catalog has no entry, render the Lisp verbose-name (or a humanized slot name if verbose-name is nil).
- **Ad-hoc UI copy** uses an explicit id in `translate` plus an English line in `en-US`.

`translate` never 500s the page:

1. Try `*locale*` via `fluent:resolve-with` (not `fluent:resolve`).
2. If missing, try `*fallback-locale*` ourselves. **Do not use Fluent’s built-in fallback-with-args path** — `resolve-with` currently passes the inputs list into `&rest` on the recursive call, which breaks messages that have arguments.
3. If still missing, return `:default` if supplied, else the original Lisp fallback (verbose-name / help-text / validator English), else the id.
4. `unknown-locale` → fallback locale, then default.

Log a warning in debug; stay quiet in production.

### 4. One process-wide catalog, per-request locale argument

Load every locale at startup into a `fluent` struct stored in `*fluent*`. Do **not** `setf fluent-locale` on that struct per request. `translate` always calls `resolve-with` with `*locale*`.

`*locale*` is a special, defaulting to `*default-locale*` (`:en-us`). Middleware and `with-locale` bind it.

### 5. Catalog layout and merge order

Mirror static-file discovery.

```
shiso/locale/en-US/validators.ftl
shiso/locale/en-US/admin.ftl
shiso/locale/en-US/auth.ftl
<module>/locale/en-US/<module>.ftl     ; next to routes.lisp, like static/
<app>/locale/en-US/<app>.ftl           ; project overlay
```

Each subdirectory name is a locale (`en-US` → `:en-us`). Multiple `.ftl` files in one locale dir are fused (Fluent already does this).

Merge **trees** in order, later wins on clashing ids:

1. Shiso’s own `locale/` (`asdf:system-relative-pathname`).
2. Each registered module’s `locale/` (detected at `define-module` like `static/`).
3. Application `locale/` from `load-localisations :root`.

Empty / missing dirs are fine. `load-localisations` is idempotent and callable from the REPL to pick up FTL edits.

### 6. Locale negotiation (middleware, after session)

Order, Django 4+ shaped:

1. Cookie `shiso_language` (name configurable later).
2. `Accept-Language` (q-values), matched against `available-locales` (exact then language parent `:ja-jp` → `:ja` only if that locale is loaded).
3. `*default-locale*`.

Reject unknown locales; never activate a catalog we did not load.

Install in `wrap-app` **after** session, **before** CSRF is not required (locale is not CSRF-sensitive) but after session so a future session-stored locale could be added without reordering. Cookie-only is enough for v1.

`html` `lang` attributes (admin currently hardcodes `"en"`) use `(locale-html-lang (current-locale))` → `"ja"` / `"en"`.

### 7. Language switcher is a tiny module, not routing prefixes

`shiso-i18n` module, peer to `shiso-auth`:

- `POST /i18n/set-language` with `language` + optional `next` (same safety rules as auth’s `next`).
- Sets the cookie, 302 to `next` or `/`.
- CSRF already wraps the app.

Apps that want a `<select>` include the form; we ship a small helper component or just document the POST.

Do **not** add `/ja/…` prefixes in v1.

### 8. Configuration without waiting on `define-settings`

Settings Phase 6 is not implemented. v1 uses specials + `load-localisations`:

```lisp
(shiso:load-localisations
  :root #p"locale/"              ; app overlay, optional
  :default-locale :en-us
  :fallback-locale :en-us)
```

Call from the app’s `main` / `start` **before** `shiso:start`, or lazily on first request if `*fluent*` is unbound (tests). Later, `define-settings` can feed these same keys.

Env overrides (optional, cheap): `SHISO_LOCALE`, `SHISO_FALLBACK_LOCALE`.

### 9. Datetime stays `local-time`

HTML `date` / `datetime-local` keep ISO patterns. Admin tables keep `format-timestring`. A future `shiso:l` can format then pass `:when` into `translate`. Not part of this work.

### 10. License / vendoring

Vendor `fluent`, `parcom`, `plurals`, `filepaths` (Fluent’s closure). MPL-2.0 on Fluent is file-level copyleft: keep MPL headers on those files; Shiso stays MIT. Add a one-line note under vendored licenses if such a file exists; otherwise mention it in `CHANGELOG.org`.

---

## Architecture

```
request
  wrap-app: session → locale mw → csrf → app
                │
                ├─ bind shiso/i18n:*locale*
                └─ cookie / Accept-Language / default
  controller / form render / validator
                │
                └─ (translate id :arg …)
                       resolve-with *fluent* *locale*
                       else fallback locale
                       else Lisp default / id
```

`shiso/i18n` files (new module, serial, before `auth` so auth/forms can call `translate`):

- `package.lisp`
- `locale.lisp` — `*locale*`, `*default-locale*`, `*fallback-locale*`, `*fluent*`, `with-locale`, `current-locale`, locale parsing (`en-US` / `en_US` / `en` → keyword)
- `catalog.lisp` — `load-localisations`, merge trees, module locale-root registry
- `translate.lisp` — `translate` + missing-key policy
- `negotiate.lisp` — Accept-Language parse, cookie, `best-locale`
- `middleware.lisp` — Lack middleware
- `routes.lisp` / `controllers.lisp` — `shiso-i18n` set-language module

Framework catalogs: `locale/en-US/{validators,admin,auth}.ftl`. Add `ja-JP` fixtures in tests only; do not ship a second production language until we have translations.

---

## Integration points (existing code)

### Validators (`src/validators.lisp`)

Today they return English at call time (`"This field is required."`, `(format nil "Must be ~D characters or fewer." n)`).

Change them to `translate` with named args:

```lisp
(translate "validators-not-blank"
           :default "This field is required.")
(translate "validators-max-length"
           :n n
           :default (format nil "Must be ~D characters or fewer." n))
```

`:default` keeps tests and English-only apps green without requiring catalogs to be loaded. Cross-field auth errors (`"Invalid email or password."`) follow the same pattern.

`run-validators` still returns a list of strings; they are already translated if `*locale*` is bound. Tests wrap `with-locale`.

FTL:

```ftl
validators-not-blank = This field is required.
validators-max-length = Must be { $n } characters or fewer.
validators-min-length = Must be at least { $n } characters.
# … min-value, max-value, matches-pattern, valid-email, one-of
```

### Forms

- `render-field` / `render-help-text`: if a label/help looks like a Fluent id (no spaces), `translate` it; otherwise `translate` the derived model-field id with `:default` the Lisp string.
- `model-form` `metadata-to-form-field`: pass model name through so derived ids are `question-question-text`. Store the derived id on the form-field (new optional slot `label-id`) **or** translate at render using model-name + field-name. Prefer translating at render so locale changes do not require rebuilding the form object.
- Choice display labels: `translate` each cdr with `:default` the original string.

### Models

No change to `define-model` syntax. `field-verbose-name` stays the English (or user-supplied) string. Derived id helper on the i18n package: `(message-id model-name field-name)` → `"question-question-text"`.

### Admin (`src/admin/components.lisp`, `controllers.lisp`)

Replace hardcoded `"Admin"`, `"Dashboard"`, `"Add New"`, `"Save"`, `"Delete"`, `"~A — Admin"`, `"~A List"`, column `string-capitalize` headings, flash copy. Use ids `admin-nav-title`, `admin-add-new`, `admin-save`, … Column headers: `(translate (message-id model field) :default (humanized-symbol field))`.

Set `html :lang` from `current-locale`.

### Auth

Login/signup field labels and the `"Invalid email or password."` clean error become ids + FTL. Controllers’ page titles similarly.

### Server

`wrap-app`: session → **locale middleware** → csrf.

`%start` (or first middleware invocation): `load-localisations` if `*fluent*` is nil, using an optional app root if the application stored one. Until settings exist, apps that want an overlay call `load-localisations` themselves in `main`.

### Modules

`define-module`: besides `static/`, record `locale/` if it exists (`module-locale-root`). `load-localisations` walks `*module-registry*`.

### Scaffolding

- App skeleton: `locale/en-US/app.ftl` (empty or a `site-name` term) and a comment in `main.lisp` / how-to.
- Module skeleton: `locale/en-US/<% @var module-name %>.ftl`.
- How-to: `docs/how-to/add-translations.org`.
- Tutorial: a short subsection, not a new polls rewrite.

### Tests (`t/i18n.lisp`)

- `translate` with a temp locale tree (write `.ftl` in the test, load, resolve, plural selector, fallback, missing key → default).
- `with-locale` does not leak (bind, nest, abort).
- Accept-Language matching.
- Validator messages change under `with-locale`.
- Form label render uses catalog when present, Lisp verbose-name otherwise.
- Middleware sets locale from cookie.

Do **not** hit the network. Use `lisp-unit2` like the rest of the suite.

---

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| Fluent `resolve-with` fallback + `&rest` bug | Never call their fallback; implement locale fallback in `translate` |
| Missing `DATETIME` / attributes | Out of scope; document |
| Strict errors 500 the admin | `handler-case` in `translate`; always a string |
| `t` as name | Use `translate` |
| Settings not built | Specials + `load-localisations`; compatible with later `define-settings` |
| MPL in MIT tree | Vendor as-is; do not relicense Fluent files |
| Young library (1.0.0, 2025) | Thin wrap; FTL files are the asset if we swap parsers later |
| Derived ids collide across models | Prefix with model name (`question-question-text`). Document uniqueness |

---

## Implementation order (PRs)

Each PR should be independently testable. Do not mix catalog content with the runtime in the first PR.

### PR 1 — Vendor Fluent and the `shiso/i18n` runtime

**Files:** `shiso.asd`, `src/i18n/{package,locale,catalog,translate}.lisp`, `locale/en-US/.gitkeep` or first empty tree, `t/i18n.lisp`, `vendored/` (fluent, parcom, plurals, filepaths), `CHANGELOG.org`.

**Does:** load trees, merge, `translate` / `with-locale` / missing-key policy. No middleware, no framework string changes.

**Depends on:** nothing.

### PR 2 — Module locale roots + app overlay

**Files:** `src/modules.lisp`, `src/routing.lisp` (`define-module`), `src/i18n/catalog.lisp`, tests.

**Does:** auto-detect `locale/` next to a module; merge order shiso → modules → app `:root`.

**Depends on:** PR 1.

### PR 3 — Request locale middleware + set-language

**Files:** `src/i18n/{negotiate,middleware}.lisp`, `src/i18n/routes.lisp`, `src/i18n/controllers.lisp`, `src/server.lisp` (`wrap-app`), `src/package.lisp`, `t/i18n.lisp`.

**Does:** cookie + Accept-Language; `POST /i18n/set-language`; bind `*locale*` per request. Mount `shiso-i18n` at `""` like auth (or `"/i18n"` if that is cleaner for fall-through — prefer a dedicated prefix `/i18n` so it cannot collide with app `""` modules).

**Depends on:** PR 1.

### PR 4 — Validators + auth + forms/admin consume `translate`

**Files:** `src/validators.lisp`, `locale/en-US/validators.ftl`, `src/auth/forms.lisp`, `locale/en-US/auth.ftl`, `src/forms/rendering.lisp`, `src/forms/model-form.lisp`, `src/admin/{components,controllers}.lisp`, `locale/en-US/admin.ftl`, existing tests updated for `with-locale`.

**Does:** all user-visible framework strings go through `translate` with `:default` English. Derived ids for model field labels. `html lang`.

**Depends on:** PR 1 (PR 3 for request locale in browser tests; unit tests only need `with-locale`).

### PR 5 — Scaffolding and docs

**Files:** `skeleton/app/`, `skeleton/module/`, `docs/how-to/add-translations.org`, `docs/explanation/` (short i18n paragraph in architecture or a new `i18n.org`), `docs/reference/i18n.org`, `PLAN.md` / `ROADMAP.md` (Phase 17 done, datetime l10n parked as a later phase), `README.org` if it lists features.

**Depends on:** PRs 1–4.

---

## Suggested first catalog slice (PR 4)

Keep the English identical to today’s strings so tests that compare copy stay stable:

```ftl
# validators.ftl
validators-not-blank = This field is required.
validators-max-length = Must be { $n } characters or fewer.
validators-min-length = Must be at least { $n } characters.
validators-min-value = Must be at least { $n }.
validators-max-value = Must be at most { $n }.
validators-matches-pattern = Does not match the expected pattern.
validators-valid-email = Enter a valid email address.
validators-one-of = Must be one of: { $choices }.

# auth.ftl
auth-email = Email
auth-password = Password
auth-invalid-credentials = Invalid email or password.

# admin.ftl
admin-nav-title = Admin
admin-dashboard = Dashboard
admin-add-new = Add New
admin-save = Save
admin-delete = Delete
admin-page-title = { $title } — Admin
admin-list-title = { $model } List
```

---

## App usage (what we are designing toward)

```lisp
;; main.lisp / start
(shiso:load-localisations :root #p"locale/" :default-locale :en-us)

;; a controller
(shiso:translate "home-welcome" :name (user-email u))

;; a model. The lookup key is derived from names:
;;   model QUESTION + slot QUESTION-TEXT → "question-question-text"
;; :verbose-name is English shown when that key is missing (en-US with
;; no catalog, or a locale that has not translated this field yet).
(shiso:define-model question
    ((question-text :field-type :char :max-length 200
                    :verbose-name "Question text")))
```

```ftl
# locale/ja-JP/polls.ftl
# Translates the field label (verbose-name "Question text"), keyed by
# model-slot — not by slugifying the English sentence.
question-question-text = 質問
home-welcome = ようこそ、{ $name } さん
```

Language switcher: POST to `(shiso:url "shiso-i18n:set-language")` with `language=ja-JP`.

---

## Open questions (recommended defaults)

If you disagree, say so before implementation; otherwise use the defaults.

1. **Derived field ids** (`question-question-text`) vs requiring every `:verbose-name` to already be a Fluent id. **Default: derived + Lisp fallback** so existing models do not break.
2. **set-language mount**: `/i18n/set-language` vs a root route. **Default: `/i18n` prefix.**
3. **Ship a second locale** with the framework (e.g. `ja-JP` for admin). **Default: English catalogs only; extra locales in tests.**
4. **Lazy load vs boot load.** **Default: `load-localisations` at start, plus lazy init if `*fluent*` is nil (tests).**


