# Handoff — `cookie-header-value` crashes on every cookieless request

**Status:** diagnosed, not fixed. Fix is one form; see below.
**Severity:** every Shiso app with i18n loaded returns nothing to a first-time
visitor. Under `:debugp t` the server process exits rather than serving a 500.
**Scope:** `src/i18n/negotiate.lisp`, one function.

---

## What happens

`shiso/i18n:wrap-locale` sits in the global middleware stack installed by
`shiso:start`, so `best-locale` runs on **every** request — not only on the
routes of a mounted `shiso-i18n` module. It calls `cookie-header-value`, which
signals:

```
malformed property list: #<HASH-TABLE :TEST EQUAL :COUNT 3 {700A27AC73}>.
```

Under Clack, `(getf env :headers)` is always a hash-table. `cookie-header-value`
knows that, but only for the branch where the cookie is *present*:

```lisp
;; src/i18n/negotiate.lisp:30
(defun cookie-header-value (env name)
  "Return the raw cookie named NAME from a Clack ENV, or NIL."
  (let* ((headers (getf env :headers))
         (cookie (and headers
                      (or (and (hash-table-p headers)
                               (or (gethash "cookie" headers)
                                   (gethash :cookie headers)))
                          (getf headers :cookie)))))   ; <- reached with a hash-table
```

The two arms of the outer `or` are not mutually exclusive. When `headers` is a
hash-table that has **no** cookie key, the first arm evaluates to `NIL` and the
`or` proceeds to its fallback, `(getf headers :cookie)` — `getf` on a
hash-table. The type check guards entry to the hash-table arm but not exit from
it.

So the trigger is not an unusual client. It is *any request that sends no
`Cookie` header*, which is every visitor's first one.

## Why it takes the process down instead of 500ing

`lack/middleware/backtrace` tries to print the condition together with the env.
The env holds `:raw-body`, a `flexi-streams::vector-input-stream`, which is not
printable readably, so printing signals `print-not-readable`. That escapes the
callback as `fast-http.error:cb-message-complete`, and SBCL's
`--disable-debugger` hook quits. Net effect in development: the server dies on
the first pageview with a backtrace that points at fast-http, several layers
away from the actual fault.

That second-order behaviour is arguably worth its own look, but it is not this
bug and should not be fixed in the same change.

## Reproduce

REPL, no server needed:

```lisp
(asdf:load-system "shiso")
(shiso/i18n::cookie-header-value (list :headers (make-hash-table :test #'equal))
                                 "shiso_language")
;; => error: malformed property list
```

Passing a table that *does* contain `"cookie"` returns correctly, which is why
this survived review.

End to end:

```sh
curl -sS http://127.0.0.1:5000/            # dies
curl -sS -H 'Cookie: x=1' http://127.0.0.1:5000/   # fine
```

## The fix

Make the branches exclusive — the same `cond` shape `env-accept-language`
already uses twenty lines below, which is why the `Accept-Language` path has
never had this fault:

```lisp
(defun cookie-header-value (env name)
  "Return the raw cookie named NAME from a Clack ENV, or NIL."
  (let* ((headers (getf env :headers))
         (cookie (cond ((null headers) nil)
                       ((hash-table-p headers)
                        (or (gethash "cookie" headers)
                            (gethash :cookie headers)))
                       (t (getf headers :cookie)))))
    (when cookie
      ...)))
```

Consider factoring the two readers into one `env-header (env name)` helper while
you are in here — they now differ only in the header they look up, and a third
caller would otherwise copy whichever of the two shapes it happened to see
first. Optional; the `cond` alone closes the bug.

### Blast radius

`negotiate.lisp` is the only file in `src/` that touches `env :headers` at all:

```
src/i18n/negotiate.lisp:32   cookie-header-value    <- broken
src/i18n/negotiate.lisp:48   env-accept-language    <- correct
```

Nothing else needs changing.

## Tests

**Do not write new tests — they already exist and should be failing.**
`t/i18n.lisp:127` `best-locale-prefers-cookie-then-header` has two assertions
that take the crashing path:

```lisp
(let ((headers (make-hash-table :test #'equal)))
  (setf (gethash "accept-language" headers) "ja-JP,en;q=0.8")   ; no cookie key
  (assert-eq :ja-jp (i18n:best-locale (list :headers headers))))
(assert-eq :en-us
           (i18n:best-locale (list :headers (make-hash-table :test #'equal))))
```

The coverage was right. It was never observed to fail because **the test system
does not currently load**:

```sh
sbcl --non-interactive \
  --eval '(require :asdf)' \
  --eval '(asdf:initialize-source-registry `(:source-registry (:tree ,(uiop:getcwd)) :ignore-inherited-configuration))' \
  --eval '(asdf:load-system "shiso/tests")'
# => Unhandled SB-PCL::INITARG-ERROR
#    #<STANDARD-CLASS MGL-PAX:SECTION> :LINK-TITLE-TO NIL :CONCEPTS NIL ...
```

`lisp-unit2` pulls in `mgl-pax`, and the vendored `mgl-pax` disagrees with the
vendored `trivial-utf-8` about `section`'s initargs. That is a vendoring
problem, separate from this bug, and it has to be cleared first or the fix
cannot be verified the intended way.

**Suggested order:**

1. Unbreak `shiso/tests` loading (vendored `mgl-pax` / `trivial-utf-8`).
2. Run `(lisp-unit2:run-tests :package :shiso/t/i18n)` and *watch it fail* —
   confirm the two assertions above are what breaks, so you know the test is
   really exercising this.
3. Apply the `cond`.
4. Re-run; then the whole suite, since `wrap-locale` is global.

If step 1 turns out to be deep, verify with the REPL repro above and say so in
the PR rather than skipping verification silently.

## How this was found

Scaffolding a new Shiso app (`winvillage`) that mounts `("/i18n" shiso-i18n)`
and boots with `shiso:load-localisations`. First `curl /` killed the server.
Nothing about that app provokes it — a bare `shiso new-application` would hit it
on its first pageview.

Two unrelated things noticed on the way, worth their own issues, **not part of
this change**:

- The installed `shiso` binary at the repo root is stale (built 5月18). It
  predates the templating work, so `shiso new-application` copies the skeleton
  verbatim without substituting `<% @var application-name %>` in either file
  contents or file names — the scaffolded project does not load. `make` fixes it.
- The default template path in that stale binary is `~/common-lisp/shiso/`,
  missing the `almighty/` segment; `SHISO_HOME` works around it.
