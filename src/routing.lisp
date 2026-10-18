(defpackage #:shiso/routing
  (:use #:cl)
  (:local-nicknames (#:modules #:shiso/modules)
                    (#:errors #:shiso/errors)
                    (#:timing #:shiso/timing))
  (:export
   ;; Typed route parameters
   #:define-path-converter
   #:find-path-converter
   #:*path-converters*
   #:route-url-params
   #:allowed-methods-for
   #:describe-mount-routes
   #:*auto-options*
   #:routes
   #:routes-mapper
   #:*routes*
   #:define-route
   #:define-routes
   #:define-module
   #:define-application
   #:to-symbol
   #:to-symbol-form
   #:coerce-route-name
   ;; Path canonicalization (no trailing slash except bare "/")
   #:canonicalize-path
   #:canonicalize-redirect-url
   #:join-url-path
   #:full-path-from-env
   #:strip-trailing-slash-middleware
   #:make-module-mount-middleware
   #:application-sessionless-prefixes
))

(in-package #:shiso/routing)

;;; ----------------------------------------------------------------------
;;; Path helpers
;;;
;;; Canonical app URLs never end with "/" except for the site root "/".
;;; define-application installs middleware that 301-strips trailing
;;; slashes before dispatch. redirect-response, url reverse, and login
;;; ?next= all go through these helpers so app code cannot re-introduce
;;; a trailing slash that fights the stripper (infinite redirect loop).

(defun canonicalize-path (path)
  "Return PATH without a trailing slash, except bare \"/\".
   NIL or empty becomes \"/\"."
  (cond
    ((or (null path) (zerop (length path))) "/")
    ((string= path "/") "/")
    (t
     (let ((clean (string-right-trim '(#\/) path)))
       (if (zerop (length clean)) "/" clean)))))

(defun canonicalize-redirect-url (url)
  "Normalize a Location URL so its path has no trailing slash (except \"/\").
   Preserves query string and fragment. Leaves non-path URLs (e.g. absolute
   http(s) targets) unchanged so open-redirect-style absolute URLs are not
   rewritten here — callers that only allow local paths should validate first."
  (cond
    ((or (null url) (not (stringp url)) (zerop (length url))) url)
    ;; Local absolute path: /staff/ or /login?next=/x/
    ((char= (char url 0) #\/)
     (let* ((split (or (position #\? url) (position #\# url)))
            (path (if split (subseq url 0 split) url))
            (rest (if split (subseq url split) "")))
       (concatenate 'string (canonicalize-path path) rest)))
    (t url)))

(defun join-url-path (prefix path)
  "Join a module mount PREFIX with a route PATH without a trailing slash.

   \"/staff\" + \"/\"     → \"/staff\"
   \"/staff\" + \"/crm\"  → \"/staff/crm\"
   \"\"       + \"/login\" → \"/login\""
  (let* ((prefix (or prefix ""))
         (path (or path "/"))
         (joined
          (cond
            ((zerop (length prefix)) path)
            ((or (string= path "/") (zerop (length path))) prefix)
            ((char= (char path 0) #\/)
             (concatenate 'string prefix path))
            (t
             (concatenate 'string prefix "/" path)))))
    (canonicalize-path joined)))

(defun full-path-from-env (env)
  "Reconstruct the original request path from ENV.

   Module mounts move the mount prefix into :script-name and leave the
   remainder in :path-info (Lack convention). Guards and redirects must
   use this full path so login ?next= is /staff not / after a /staff mount."
  (let* ((script (or (getf env :script-name) ""))
         (path (or (getf env :path-info) "/"))
         (full (cond
                 ((zerop (length script)) path)
                 ((or (string= path "/") (zerop (length path))) script)
                 (t (concatenate 'string script path)))))
    (canonicalize-path full)))

(defclass routes ()
  ((mapper :initarg :mapper :reader routes-mapper :initform nil)))

(defparameter *routes* (make-instance 'routes :mapper (myway:make-mapper)))

(defun get-function-name (fn)
  (when (functionp fn)
    (multiple-value-bind (expression closure-p function-name)
        (function-lambda-expression fn)
      (if (symbolp function-name)
          function-name
          fn))))

;;; ----------------------------------------------------------------------
;;; Typed route parameters (Django's path converters)
;;;
;;; "/books/<int:id>" matches like "/books/:id", then converts ID with the
;;; INT converter: the controller gets 42, not "42". A value the converter
;;; rejects ("/books/abc") makes the route not match (MYWAY:NEXT-ROUTE), so
;;; a request no other route takes ends at the 404 fallback, not a 500.

(defstruct (path-converter (:constructor make-path-converter (name parse to-url)))
  name
  parse    ; string → (values value t), or (values nil nil) to reject
  to-url)  ; value → string, for SHISO:URL

(defvar *path-converters* (make-hash-table :test 'equal)
  "Converters by lowercase name. Looked up per request, so redefining one
takes effect at once.")

(defun find-path-converter (name &optional (errorp t))
  (or (gethash (string-downcase name) *path-converters*)
      (and errorp (error "Unknown path converter ~S in a route. Known: ~{~A~^, ~}."
                         name (sort (loop for key being the hash-keys of *path-converters*
                                          collect key)
                                    #'string<)))))

(defmacro define-path-converter (name (string &key (to-url '#'princ-to-string)) &body body)
  "Define the converter NAME for \"<name:param>\" in route paths. BODY sees
the matched text as STRING and returns (values converted-value t), or
(values nil nil) to reject it. TO-URL turns a value back into URL text for
SHISO:URL.
  (s:define-path-converter year (string)
    (if (= 4 (length string)) (values (parse-integer string) t) (values nil nil)))"
  `(progn
     (setf (gethash ,(string-downcase name) *path-converters*)
           (make-path-converter ,(string-downcase name)
                                (lambda (,string) ,@body)
                                ,to-url))
     ',name))

(defun ascii-char-in-p (char ranges extra)
  (or (find char extra)
      (loop for (low high) in ranges
            thereis (char<= low char high))))

(define-path-converter int (string)
  ;; Non-negative, digits only, like Django's int.
  (if (and (plusp (length string)) (every (lambda (c) (char<= #\0 c #\9)) string))
      (values (parse-integer string) t)
      (values nil nil)))

(define-path-converter slug (string)
  (if (and (plusp (length string))
           (every (lambda (c) (ascii-char-in-p c '((#\a #\z) (#\A #\Z) (#\0 #\9)) "-_"))
                  string))
      (values string t)
      (values nil nil)))

(define-path-converter uuid (string)
  (if (and (= (length string) 36)
           (loop for c across string
                 for i from 0
                 always (if (member i '(8 13 18 23))
                            (char= c #\-)
                            (digit-char-p c 16))))
      (values (string-downcase string) t)
      (values nil nil)))

(define-path-converter str (string)
  (if (plusp (length string)) (values string t) (values nil nil)))

(defun parse-typed-path (path)
  "Rewrite \"<type:name>\" segments of PATH to MyWay's \":name\". Returns the
rewritten path and an alist ((:NAME . \"type\") ...)."
  (let ((converters '()))
    (values (ppcre:regex-replace-all
             "<([A-Za-z][\\w-]*):([A-Za-z][\\w-]*)>" path
             (lambda (match type name)
               (declare (ignore match))
               (find-path-converter type)
               (push (cons (intern (string-upcase name) :keyword) (string-downcase type))
                     converters)
               (concatenate 'string ":" name))
             :simple-calls t)
            (nreverse converters))))

(defun convert-params (param-keys params converters)
  "The controller's arguments from MyWay's PARAMS, converted. Second value
NIL when a converter rejects its value."
  (let ((args '()))
    (dolist (key param-keys (values (nreverse args) t))
      (let ((raw (getf params key))
            (type (cdr (assoc key converters))))
        (if type
            (multiple-value-bind (value ok)
                (funcall (path-converter-parse (find-path-converter type)) raw)
              (unless ok
                (return (values nil nil)))
              (push value args))
            (push raw args))))))

;;; What a route was defined with, which MyWay's route doesn't keep: the
;;; typed pattern (for the debug 404 page) and its converters (for the 405
;;; probe and SHISO:URL). Weak keys: a redefined route's entry goes with it.

(defstruct route-info pattern converters)

(defvar *route-info* (make-hash-table :test 'eq #+sbcl :weakness #+sbcl :key))

(defun route-url-params (route params)
  "PARAMS for MYWAY:URL-FOR on ROUTE, typed values turned into URL text."
  (let ((converters (let ((info (gethash route *route-info*)))
                      (and info (route-info-converters info)))))
    (if converters
        (loop for (key value) on params by #'cddr
              for type = (cdr (assoc key converters))
              append (list key (if (and type value (not (stringp value)))
                                   (funcall (path-converter-to-url (find-path-converter type))
                                            value)
                                   value)))
        params)))

(defun make-endpoint (fn param-keys &key converters regexp label)
  "The MyWay handler for controller FN: calls it with the route's parameters,
converted when typed, or with a regex route's captures. LABEL,
\"module:name\", goes in the request's access-log line."
  (let ((fn (if (functionp fn)
                (let ((name (nth-value 2 (function-lambda-expression fn))))
                  (if (symbolp name) name fn))
                fn)))
    (cond
      (regexp
       (lambda (params)
         (timing:note-route label)
         (apply fn (getf params :captures))))
      (converters
       (lambda (params)
         (multiple-value-bind (args ok) (convert-params param-keys params converters)
           (cond (ok
                  (timing:note-route label)
                  (apply fn args))
                 ;; Not a match after all: let later routes try. NIL when
                 ;; none does; the module treats that as a miss.
                 (t (values (myway:next-route)))))))
      (param-keys
       (lambda (params)
         (timing:note-route label)
         (apply fn (mapcar (lambda (key) (getf params key)) param-keys))))
      (t
       (lambda (params)
         (declare (ignore params))
         (timing:note-route label)
         (funcall fn))))))

(defun to-symbol-form (fn-form)
  "Function version of to-symbol for use inside macro bodies at expansion time.
   Converts a controller designator form to a quoted symbol form.
   #'foo, 'foo, and bare foo all become (quote foo). Lambdas pass through."
  (cond
    ;; #'foo  ->  (function foo)
    ((and (consp fn-form)
          (eq (first fn-form) 'function))
     `',(second fn-form))
    ;; 'foo   ->  (quote foo)
    ((and (consp fn-form)
          (eq (first fn-form) 'quote)
          (symbolp (second fn-form)))
     `',(second fn-form))
    ;; bare symbol foo
    ((symbolp fn-form)
     `',fn-form)
    ;; lambda or other compound form — pass through
    (t fn-form)))

(defmacro to-symbol (fn-form)
  "Turn a function designator form (foo, #'foo, or 'foo) into the quoted symbol 'foo.
   All three calls expand to the same thing: 'FOO"
  (to-symbol-form fn-form))

(defun coerce-route-name (name)
  "Turn a route name designator into a keyword for vanilla MyWay.
Strings are uppercased and interned in the KEYWORD package (so
\"index\" → :INDEX and \"admin:users\" → a single keyword whose
name is \"ADMIN:USERS\")."
  (etypecase name
    (null nil)
    (keyword name)
    (symbol (intern (symbol-name name) :keyword))
    (string (intern (string-upcase name) :keyword))))

(defun define-route (method routing-rule &key controller name (regexp nil) (routes *routes*)
                                              module)
  "Register ROUTING-RULE on ROUTES (default `*routes*').
NAME is stored as a MyWay route name keyword (see `coerce-route-name').
MODULE, a string, names the route \"module:name\" in the access log.
Module routes should use a short name unique within that module's
mapper (e.g. \"index\"); reverse URLs with `shiso:url' as
\"module:index\". Global `define-routes' may use a unique dotted name
on the shared mapper."
  (multiple-value-bind (rule converters)
      (if regexp (values routing-rule nil) (parse-typed-path routing-rule))
    (let ((param-keys (unless regexp
                        (myway.rule::rule-param-keys (myway.rule::make-rule rule))))
          (name-kw (coerce-route-name name))
          (mapper (routes-mapper routes)))
      (prog1 (myway:connect mapper
                            rule
                            (make-endpoint controller param-keys
                                           :converters converters :regexp regexp
                                           :label (cond ((and module name)
                                                         (format nil "~A:~(~A~)" module name))
                                                        (name (format nil "~(~A~)" name))))
                            :method method
                            :name name-kw
                            :regexp regexp)
        (let ((route (myway:find-route mapper rule :method method :name name-kw
                                                   :regexp regexp)))
          (when route
            (setf (gethash route *route-info*)
                  (make-route-info :pattern routing-rule :converters converters))))))))

(defmacro define-routes (module &rest args)
  "Register routes on the global `*routes*' mapper.
Prepends :root to paths and prefixes each name with \"MODULE:\" so
names stay unique on the shared mapper (vanilla MyWay has no
namespaces). Prefer `define-module' for normal apps."
  (let ((root (getf args :root ""))
        (routes (member-if #'listp args))
        (module-name (string-downcase (symbol-name module))))
    `(progn
       ,@(loop for (method path controller name) in routes
               for controller-symbol = (to-symbol-form controller)
               for full-path = (concatenate 'string root path)
               for full-name = (concatenate 'string module-name ":" name)
               append (let ((methods (if (listp method) method (list method))))
                        (loop for m in methods
                              collect `(define-route ,m ,full-path
                                         :controller ,controller-symbol
                                         :name ,full-name)))))))

(defmacro define-module (name &body options)
  "Define a module with routes on a per-module mapper (un-prefixed).

Usage:
  (define-module articles
    (:urls (:GET         \"/\"       'controllers:index  \"index\")
           ((:GET :POST) \"/create\" 'controllers:create \"create\")))

Each URL spec is (METHOD PATH CONTROLLER NAME).
METHOD can be a keyword or a list of keywords.
Routes are registered with their original paths on the module's own
mapper under the short NAME (e.g. :INDEX). Reverse with
(shiso:url \"articles:index\") — the module half selects the mapper;
MyWay only sees the short name.
The module instance is stored in the registry for url generation and mounting.

A :guard option attaches an authentication/authorization guard that runs
before any route in this module is dispatched. See `shiso/auth/guards'
for the recognized specs (e.g. (:require :staff))."
  (let* ((module-keyword (intern (string-upcase (symbol-name name)) :keyword))
         (urls (cdr (assoc :urls options)))
         (guard (cadr (assoc :guard options)))
         (module-routes-var (gensym "MODULE-ROUTES"))
         ;; Detect static directory at compile time
         (source-path (or *compile-file-pathname* *load-pathname*))
         (module-dir (when source-path
                       (uiop:pathname-directory-pathname source-path)))
         (static-dir (when module-dir
                       (merge-pathnames "static/" module-dir)))
         (static-root (when (and static-dir (uiop:directory-exists-p static-dir))
                        (namestring static-dir)))
         (locale-dir (when module-dir
                       (merge-pathnames "locale/" module-dir)))
         (locale-root (when (and locale-dir (uiop:directory-exists-p locale-dir))
                        (namestring locale-dir))))
    `(progn
       (let ((,module-routes-var (make-instance 'routes :mapper (myway:make-mapper))))
         ,@(loop for url-spec in urls
                 append
                 (destructuring-bind (method path controller route-name) url-spec
                   (let* ((controller-symbol (to-symbol-form controller))
                          (methods (if (listp method) method (list method))))
                     (loop for m in methods
                           collect `(define-route ,m ,path
                                      :controller ,controller-symbol
                                      :name ,route-name
                                      :routes ,module-routes-var
                                      :module ,(string-downcase (symbol-name name)))))))
         (modules:register-module ,module-keyword
                          (make-instance 'modules:module
                                         :routes ,module-routes-var
                                         :static-root ,static-root
                                         :locale-root ,locale-root
                                         :guard ',guard)))
       ',name)))

(defmacro define-application (name () &body options)
  "Define an application that mounts each module at an explicit prefix.

Usage:
  (define-application my-app ()
    (:modules
      (\"\" pages)
      (\"/books\" books)
      (\"/articles\" articles)))

  (:after-database #'seed-data) is called once SHISO:START has connected to
the database and made its tables.

Each entry in :modules is (PREFIX MODULE-NAME &key (SESSIONS T)). The
prefix string is used directly — \"\" means mount at root, \"/books\" means
mount at /books. With :SESSIONS NIL, requests under the prefix get no
session: no session row is read or written, and there is no login and no
CSRF check there. For modules that serve files, such as images.
Modules must be loaded (and their define-module forms evaluated) before
this macro runs so that their routes are in the registry.
Modules are late-bound: the registry is consulted at dispatch time, so
re-evaluating define-module takes effect immediately.
Static files are served by a global middleware under /static/ that searches
the project's static/ directory and per-module static/ directories."
  (let* ((app-var (intern (string-upcase (symbol-name name))))
         (modules (mapcar #'parse-mount (cdr (assoc :modules options))))
         (sessionless (loop for (prefix nil sessions) in modules
                            unless sessions collect prefix))
         ;; Detect project-wide static/ directory at compile time
         ;; Walk up from the source file's directory to find static/
         (source-path (or *compile-file-pathname* *load-pathname*))
         (static-root (when source-path
                        (loop for dir = (uiop:pathname-directory-pathname source-path)
                                then (uiop:pathname-parent-directory-pathname dir)
                              for static-dir = (merge-pathnames "static/" dir)
                              when (uiop:directory-exists-p static-dir)
                                return (namestring static-dir)
                              until (equal dir (uiop:pathname-parent-directory-pathname dir))))))
    `(progn
      ;; CACHED-STATIC versions URLs from the files the middleware below serves.
      ,@(when static-root
          `((setf shiso/static:*project-static-root* ,(pathname static-root))))
      ;; Run once the database is connected (see shiso/database).
      ,@(let ((after (second (assoc :after-database options))))
          (when after
            `((setf (symbol-value (uiop:find-symbol* '#:*after-database* '#:shiso/database))
                    ,after))))
      (defparameter ,app-var
       (let ((app
       (lack:builder
        ;; Multi-root static middleware: project static/ + module static/ dirs
        ,@(when static-root
            `((lambda (app)
                (shiso/static:make-static-middleware
                 app
                 :path "/static/"
                 :project-root ,(pathname static-root)
                 :module-roots (shiso/static:module-static-roots)))))
        ;; Canonical paths have no trailing slash (except "/"). 301 first
        ;; so mounts and routes never see slash-terminated path-info.
        #'shiso/routing:strip-trailing-slash-middleware
        ;; Module mounts. Each mount is a hand-rolled middleware (rather
        ;; than lack's :mount) so that a module which doesn't match the
        ;; request can fall through to the next mounted module instead of
        ;; returning its own 404. The module's lack/component:call returns
        ;; a second value indicating whether it handled the request.
        ,@(loop for (prefix mod-name) in modules
                for mod-kw = (intern (string-upcase (symbol-name mod-name)) :keyword)
                collect `(shiso/routing:make-module-mount-middleware
                          ,prefix ,mod-kw))
        ;; No module took the request: 405 when some route accepts the path
        ;; with another method (modules collect those on a miss), else 404.
        ;; Signalled for shiso/errors' middleware to render.
        (lambda (env)
          (shiso/routing::not-handled
           env
           ',(loop for (prefix mod-name) in modules
                   collect (cons prefix
                                 (intern (string-upcase (symbol-name mod-name)) :keyword))))))))
         ;; Per request: the methods modules collect for the 405.
         (lambda (env)
           (let ((shiso/errors:*allowed-methods* nil))
             (funcall app env)))))
      ;; Read by SHISO:START, which wraps the app in the session middleware.
      (setf (shiso/routing:application-sessionless-prefixes ,app-var) ',sessionless)
      ',app-var)))

(defun parse-mount (entry)
  "(PREFIX MODULE-NAME SESSIONS) from a :modules entry of DEFINE-APPLICATION."
  (destructuring-bind (prefix module-name &key (sessions t)) entry
    (when (and (not sessions) (equal prefix ""))
      (error "The module ~A is mounted at \"\" with :sessions nil, but every ~
path starts with \"\". Mount it at a prefix of its own." module-name))
    (list prefix module-name sessions)))

(defvar *sessionless-prefixes* (make-hash-table :test 'eq #+sbcl :weakness #+sbcl :key)
  "Application function → the mount prefixes DEFINE-APPLICATION gave
:sessions nil.")

(defun application-sessionless-prefixes (app)
  "The mount prefixes under which APP's requests get no session."
  (values (gethash app *sessionless-prefixes*)))

(defun (setf application-sessionless-prefixes) (prefixes app)
  (setf (gethash app *sessionless-prefixes*) prefixes))

(defvar *auto-options* t
  "When true, an OPTIONS request for a path some route serves, but not with
OPTIONS, gets 204 with an Allow header instead of 405.")

(defun sort-methods (methods)
  "METHODS without duplicates, in the usual order: GET, HEAD, POST, …"
  (let ((order '(:get :head :post :put :patch :delete :options)))
    (sort (remove-duplicates methods)
          #'< :key (lambda (m) (or (position m order) (length order))))))

(defun not-handled (env mounts)
  "DEFINE-APPLICATION's fallback, when no mounted module took ENV."
  (let ((allowed errors:*allowed-methods*))
    (cond
      ((and allowed *auto-options* (eq (getf env :request-method) :options))
       (list 204
             (list :allow (format nil "~{~A~^, ~}" (sort-methods (cons :options allowed))))
             '()))
      (allowed
       (errors:signal-or-render
        (make-condition 'errors:method-not-allowed :allowed (sort-methods allowed)) env))
      (t
       (errors:signal-or-render
        (make-condition 'errors:not-found :mounts mounts) env)))))

(defparameter +probe-methods+ '(:get :post :put :patch :delete :options))

(defun route-accepts-path-p (route method path)
  "Whether ROUTE matches PATH for METHOD, converters included. Uses MyWay's
rule matcher directly: MYWAY:DISPATCH would call the controller."
  (multiple-value-bind (matchp params)
      (myway.rule:match-rule (myway:route-rule route) method path :allow-head nil)
    (and matchp
         (let* ((info (gethash route *route-info*))
                (converters (and info (route-info-converters info))))
           (or (null converters)
               (nth-value 1 (convert-params
                             (myway.rule::rule-param-keys (myway:route-rule route))
                             params converters)))))))

(defun allowed-methods-for (mapper path)
  "Methods for which some route in MAPPER serves PATH; HEAD with GET."
  (let ((methods (loop for method in +probe-methods+
                       when (some (lambda (route) (route-accepts-path-p route method path))
                                  (myway:mapper-routes mapper))
                         collect method)))
    (if (member :get methods) (append methods '(:head)) methods)))

(defun describe-mount-routes (mounts)
  "Rows (:pattern :methods :name) for the debug 404 page, in the order a
request meets them: static files, the trailing-slash redirect, then each
mounted module's routes."
  (append
   (when shiso/static:*project-static-root*
     (list (list :pattern "/static/…" :methods '(:get :head)
                 :name (format nil "static files: ~A and module static/ dirs"
                               shiso/static:*project-static-root*))))
   (list (list :pattern "…/ → 301 without the slash" :methods '(:any)
               :name "trailing slash"))
   (loop for (prefix . module-name) in mounts
         for module = (ignore-errors (modules:get-module module-name))
         when module
           append (loop for route in (myway:mapper-routes
                                      (routes-mapper (modules:module-routes module)))
                        for rule = (myway:route-rule route)
                        for info = (gethash route *route-info*)
                        collect (list :pattern (join-url-path
                                                prefix
                                                (if info
                                                    (route-info-pattern info)
                                                    (myway.rule::rule-url rule)))
                                      :methods (coerce (map-set::map-set-index
                                                        (myway.rule::rule-methods rule))
                                                       'list)
                                      :name (let ((name (myway:route-name route)))
                                              (and name (format nil "~(~A:~A~)"
                                                                module-name name))))))))

(setf errors:*route-describer* 'describe-mount-routes)

(defun strip-trailing-slash-middleware (app)
  "Lack middleware: 301-redirect PATH/ → PATH for any path longer than \"/\".
   Preserves the query string on the Location header.
   Runs before module mounts so dispatch always sees the canonical form."
  (lambda (env)
    (let ((path (getf env :path-info)))
      (if (and path
               (> (length path) 1)
               (char= (char path (1- (length path))) #\/))
          (let* ((clean (canonicalize-path path))
                 (qs (getf env :query-string))
                 (location (if (and qs (plusp (length qs)))
                               (concatenate 'string clean "?" qs)
                               clean)))
            (list 301
                  (list :location location)
                  (list "")))
          (funcall app env)))))

(defun make-module-mount-middleware (prefix mod-kw)
  "Return Lack middleware that mounts module MOD-KW at PREFIX.

   On match, moves PREFIX from :path-info into :script-name (Lack convention)
   so guards and helpers can rebuild the original URL via full-path-from-env.
   Unhandled requests restore both keys and fall through to the next mount."
  (let ((prefix (or prefix ""))
        (prefix-len (length (or prefix ""))))
    (lambda (app)
      (lambda (env)
        (let ((path-info (getf env :path-info)))
          (if (and path-info
                   (>= (length path-info) prefix-len)
                   (string= path-info prefix :end1 prefix-len)
                   (or (zerop prefix-len)
                       (= (length path-info) prefix-len)
                       (char= (aref path-info prefix-len) #\/)))
              (let ((mod (modules:get-module mod-kw))
                    (saved-path-info path-info)
                    (saved-script-name (getf env :script-name)))
                (setf (modules:module-prefix mod) prefix)
                (when (plusp prefix-len)
                  (setf (getf env :script-name)
                        (concatenate 'string
                                     (or saved-script-name "")
                                     prefix))
                  (setf (getf env :path-info)
                        (if (= (length path-info) prefix-len)
                            "/"
                            (subseq path-info prefix-len))))
                (multiple-value-bind (response handledp)
                    (lack/component:call mod env)
                  (cond
                    (handledp response)
                    (t
                     (setf (getf env :path-info) saved-path-info)
                     (if saved-script-name
                         (setf (getf env :script-name) saved-script-name)
                         (remf env :script-name))
                     (funcall app env)))))
              (funcall app env)))))))
