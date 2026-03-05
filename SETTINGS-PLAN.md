# Centralized Settings System for Shiso

## Context

Configuration is scattered across the framework: server defaults in `%start`, middleware in `define-application`, env vars parsed ad-hoc in user code (`main.lisp`, `dev.lisp`), admin prefix as a mutable global, hardcoded values in components. The user wants a single place — like Django's `settings.py` — to configure middleware, DB, modules, i18n, environment, etc.

## Design: `define-settings` macro + `*settings*` special variable
```comment
How do we get a setting?

Maybe using CLOS to be able to get easy accessor creation?
```
Settings are a hash table stored in `*settings*`. A `define-settings` macro provides a declarative DSL. Framework code reads from `*settings*` at runtime, so re-evaluating the form takes effect immediately (hot-reload).

### What the user's settings file looks like

```lisp
;; src/settings.lisp
(in-package #:almightylisp)

(shiso:define-settings
  ;; Server
  (:server :host "0.0.0.0"
           :port 5000
           :debugp nil
           :server :woo)

  ;; Modules mounted at prefixes
  (:modules
   ("" pages)
   ("/books" books)
   ("/articles" articles)
   ("/admin" shiso-admin))

  ;; Global middleware (applied to all requests, outermost first)
  (:middleware
   :accesslog
   (:static :path "/static/" :root #p"static/"))

  ;; Database
  (:database :driver :sqlite3
             :name "db/almighty.db")

  ;; App metadata
  (:site-name "Almighty Lisp")
  (:secret-key "change-me-in-production"))
```

Environment overrides via `.env` file or actual env vars:

```lisp
;; Any setting can be overridden by env var
;; SHISO_HOST=0.0.0.0  overrides (:server :host ...)
;; SHISO_PORT=8080      overrides (:server :port ...)
;; SHISO_DEBUGP=true    overrides (:server :debugp ...)
```

## Implementation

### 1. New file: `vendored/shiso/src/settings.lisp`

```lisp
(defpackage #:shiso/settings
  (:use #:cl)
  (:export
   #:*settings*
   #:define-settings
   #:setting
   #:setting-or))

(in-package #:shiso/settings)

(defparameter *settings* (make-hash-table :test 'eq)
  "Global settings table. Keys are keywords.")

(defun setting (key &optional default)
  "Get a setting value. KEY is a keyword."
  (gethash key *settings* default))

(defun (setf setting) (value key)
  (setf (gethash key *settings*) value))

(defun setting-or (key default)
  "Get a setting, falling back to DEFAULT."
  (multiple-value-bind (val found) (gethash key *settings*)
    (if found val default)))

(defun env-override (env-var)
  "Check for SHISO_<VAR> environment variable."
  (uiop:getenv (concatenate 'string "SHISO_" (string-upcase (string env-var)))))

(defun parse-env-value (string expected-type)
  "Coerce an env var string to the expected type."
  (cond
    ((eq expected-type 'integer)
     (parse-integer string :junk-allowed t))
    ((eq expected-type 'boolean)
     (string-equal string "true"))
    ((eq expected-type 'keyword)
     (intern (string-upcase string) :keyword))
    (t string)))

(defun apply-server-settings (plist)
  "Process (:server ...) settings with env var overrides."
  (let ((settings (copy-list plist)))
    ;; Apply env overrides for known server keys
    (loop for (key type) in '((:host string) (:port integer)
                              (:debugp boolean) (:server keyword))
          for env-val = (env-override (string key))
          when env-val
            do (setf (getf settings key) (parse-env-value env-val type)))
    (setf (setting :server) settings)))

(defmacro define-settings (&body clauses)
  "Define application settings. Re-evaluating updates *settings* immediately.

Each clause is a list starting with a keyword:
  (:server :host \"0.0.0.0\" :port 5000 ...)
  (:modules (\"\" pages) (\"/books\" books) ...)
  (:middleware :accesslog (:static :path \"/static/\" :root #p\"static/\"))
  (:database :driver :sqlite3 :name \"db/app.db\")
  (:any-key value)"
  `(progn
     (clrhash *settings*)
     ,@(loop for clause in clauses
             collect
             (let ((key (first clause))
                   (body (rest clause)))
               (case key
                 (:server
                  `(apply-server-settings (list ,@body)))
                 (:modules
                  `(setf (setting :modules) (list ,@(loop for m in body
                                                          collect `(list ,@(loop for x in m
                                                                                 collect (if (stringp x)
                                                                                             x
                                                                                             `',x)))))))
                 (:middleware
                  `(setf (setting :middleware)
                         (list ,@(loop for mw in body
                                       collect (if (listp mw) `(list ,@mw) `',mw)))))
                 (otherwise
                  (if (= 1 (length body))
                      `(setf (setting ,key) ,(first body))
                      `(setf (setting ,key) (list ,@body)))))))))
```

### 2. Modify `%start` to read from settings (`vendored/shiso/src/server.lisp`)

```lisp
(defun %start (app-symbol &key
               (host (getf (shiso/settings:setting :server) :host "127.0.0.1"))
               (port (getf (shiso/settings:setting :server) :port 5000))
               (debugp (getf (shiso/settings:setting :server) :debugp t))
               (server (getf (shiso/settings:setting :server) :server :woo)))
  (when *server-connection*
    (restart-case (error "Server is already running.")
      (restart-server ()
        :report "Restart the server"
        (stop))))
  (setf *server-connection*
        (clack:clackup (lambda (env) (funcall (symbol-value app-symbol) env))
                       :server server :address host :port port :debug debugp)))
```

Keyword args still override settings, so `(shiso:start my-app :port 3000)` works as before. Settings are the new defaults; explicit args win.

### 3. Modify `define-application` to read middleware and modules from settings (`vendored/shiso/src/routing.lisp`)

Add a new convenience macro that builds the app from settings alone:

```lisp
(defmacro define-application (name () &body options)
  "Define an application. If OPTIONS is empty, reads from *settings*."
  (let* ((app-var (intern (string-upcase (symbol-name name))))
         (modules (cdr (assoc :modules options))))
    (if modules
        ;; Existing behavior — explicit :modules in the form
        <existing expansion unchanged>
        ;; No options — build from settings at load time
        `(defparameter ,app-var
           (%build-app-from-settings)))))

(defun %build-app-from-settings ()
  "Build a Lack app from the current *settings*."
  (let* ((module-specs (shiso/settings:setting :modules))
         (middleware (shiso/settings:setting :middleware))
         (mount-apps
           (loop for (prefix mod-name) in module-specs
                 for mod-kw = (intern (string-upcase (string mod-name)) :keyword)
                 collect
                 (let ((kw mod-kw) (pfx prefix))
                   (lambda (env)
                     (let ((mod (get-module kw)))
                       (setf (module-prefix mod) pfx)
                       (lack/component:call mod env)))))))
    ;; For now, return the dispatch function directly.
    ;; Full middleware + mount composition happens here.
    (apply #'lack:builder
           (append middleware
                   (loop for (prefix mod-name) in module-specs
                         for mod-kw = (intern (string-upcase (string mod-name)) :keyword)
                         for mod = (gethash mod-kw *module-registry*)
                         for static-root = (when mod (module-static-root mod))
                         collect `(:mount ,prefix
                                  ,(lack:builder
                                    ,@(when static-root
                                        `((:static :path "/static/"
                                                   :root ,static-root)))
                                    (lambda (env)
                                      (let ((m (get-module ,mod-kw)))
                                        (setf (module-prefix m) ,prefix)
                                        (lack/component:call m env))))))
                   (list (lambda (env)
                           (declare (ignore env))
                           '(404 (:content-type "text/html") ("Not found"))))))))
```

**Wait — this gets complicated fast.** `lack:builder` is itself a macro that expects its args at compile time. Building the Lack app dynamically from runtime settings requires calling `lack:builder` differently or building the middleware chain manually.

### Simpler approach: keep `define-application` as a macro, have it read settings at expansion time

Since settings are evaluated before the application file (ASDF serial order), the settings hash table is populated at load time. `define-application` can read from it during macro expansion:

```lisp
(defmacro define-application (name () &body options)
  (let* ((app-var (intern (string-upcase (symbol-name name))))
         ;; Read from options if provided, else from settings
         (modules (or (cdr (assoc :modules options))
                      (shiso/settings:setting :modules)))
         (extra-middleware (or (cdr (assoc :middleware options))
                              (shiso/settings:setting :middleware))))
    `(defparameter ,app-var
       (lack:builder
        ,@(or extra-middleware nil)
        ,@(loop for (prefix mod-name) in modules
                for mod-kw = (intern (string-upcase (if (symbolp mod-name)
                                                        (symbol-name mod-name)
                                                        (string mod-name)))
                                     :keyword)
                for mod = (gethash mod-kw *module-registry*)
                for static-root = (when mod (module-static-root mod))
                collect `(:mount ,prefix
                          (lack:builder
                           ,@(when static-root
                               `((:static :path "/static/"
                                          :root ,static-root)))
                           (lambda (env)
                             (let ((mod (get-module ,mod-kw)))
                               (setf (module-prefix mod) ,prefix)
                               (lack/component:call mod env))))))
        (lambda (env)
          (declare (ignore env))
          '(404 (:content-type "text/html") ("Not found")))))))
```

This way `define-application` can be called with zero options and it pulls modules + middleware from settings:

```lisp
;; User's main.lisp — settings already loaded
(shiso:define-application *app* ())
(shiso:start *app*)
```

### 4. Changes to `shiso.asd`

Add `settings.lisp` as the first file in the serial component list (before `routing.lisp`):

```
:components ((:file "settings")
             (:file "routing")
             (:file "requests")
             (:file "server")
             ...)
```

### 5. Changes to `vendored/shiso/src/package.lisp`

Add imports and exports:

```lisp
(:import-from #:shiso/settings
              #:*settings*
              #:define-settings
              #:setting
              #:setting-or)
...
(:export
 ...
 #:*settings*
 #:define-settings
 #:setting
 #:setting-or)
```

### 6. User's app changes

**Before** (`src/main.lisp`):
```lisp
(defun get-env-int (env default) ...)
(defun get-env (env default) ...)
(defun envp (env) ...)

(shiso:define-application *almightylisp-application* ()
  (:modules
   ("/books" books)
   ("/articles" articles)))

(defun start-server (&key (host ...) (port ...) (debugp ...))
  (shiso:start *almightylisp-application* :host host :port port :debugp debugp))
```

**After** (`src/settings.lisp` + `src/main.lisp`):
```lisp
;; src/settings.lisp
(in-package #:almightylisp)

(shiso:define-settings
  (:server :host "0.0.0.0" :port 5000 :debugp nil)
  (:modules
   ("/books" books)
   ("/articles" articles)))
```

```lisp
;; src/main.lisp
(in-package #:almightylisp)

(shiso:define-application *almightylisp-application* ())

(defun start-server ()
  (shiso:start *almightylisp-application*))

(defun stop-server ()
  (shiso:stop))
```

No more env-parsing boilerplate — `define-settings` handles it via `SHISO_HOST`, `SHISO_PORT`, etc.

## Files to create/modify

| File | Action |
|------|--------|
| `vendored/shiso/src/settings.lisp` | **Create** — settings package |
| `vendored/shiso/org/src/settings.org` | **Create** — literate source |
| `vendored/shiso/shiso.asd` | **Modify** — add `settings` component first |
| `vendored/shiso/src/server.lisp` | **Modify** — `%start` reads defaults from settings |
| `vendored/shiso/src/routing.lisp` | **Modify** — `define-application` reads from settings when no options given |
| `vendored/shiso/src/package.lisp` | **Modify** — export new symbols |
| `vendored/shiso/org/src/server.org` | **Modify** — update prose + code |
| `vendored/shiso/org/src/routing.org` | **Modify** — update prose + code |

## Hot-reload behavior

- `*settings*` is a hash table updated in place by `define-settings` (clrhash + setf)
- `%start` reads settings at call time via keyword defaults — re-evaluating `define-settings` changes the defaults for the next `start` call
- `define-application` reads settings at macro-expansion time — must re-evaluate after changing `:modules` or `:middleware` (same as today)
- `setting` is a plain function call — any code using `(shiso:setting :foo)` at runtime gets the latest value immediately

## Verification

1. Create `vendored/shiso/src/settings.lisp`, add to `shiso.asd`
2. `(asdf:test-system :shiso)` — all existing tests pass (settings are optional, defaults preserved)
3. Write a settings file, call `define-application` with no options, verify app works
4. Set `SHISO_PORT=3000`, call `start`, verify it binds to 3000
5. Re-evaluate `define-settings` with different `:server` values, restart, verify new values take effect
