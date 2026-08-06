(defpackage #:shiso/routing
  (:use #:cl)
  (:local-nicknames (#:modules #:shiso/modules))
  (:export
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

(defun make-endpoint (fn param-keys)
  (let ((fn (if (functionp fn)
                (let ((name (nth-value 2 (function-lambda-expression fn))))
                  (if (symbolp name) name fn))
                fn)))
    (if param-keys
        (lambda (params)
          (apply fn (mapcar (lambda (key) (getf params key)) param-keys)))
        (lambda (params)
          (declare (ignore params))
          (funcall fn)))))

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

(defun define-route (method routing-rule &key controller name (regexp nil) (routes *routes*))
  "Register ROUTING-RULE on ROUTES (default `*routes*').
NAME is stored as a MyWay route name keyword (see `coerce-route-name').
Module routes should use a short name unique within that module's
mapper (e.g. \"index\"); reverse URLs with `shiso:url' as
\"module:index\". Global `define-routes' may use a unique dotted name
on the shared mapper."
  (let ((param-keys (myway.rule::rule-param-keys
                     (myway.rule::make-rule routing-rule)))
        (name-kw (coerce-route-name name)))
    (myway:connect (routes-mapper routes)
                   routing-rule
                   (make-endpoint controller param-keys)
                   :method method
                   :name name-kw
                   :regexp regexp)))

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
                        (namestring static-dir))))
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
                                      :routes ,module-routes-var)))))
         (modules:register-module ,module-keyword
                          (make-instance 'modules:module
                                         :routes ,module-routes-var
                                         :static-root ,static-root
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

Each entry in :modules is (PREFIX MODULE-NAME). The prefix string is used
directly — \"\" means mount at root, \"/books\" means mount at /books.
Modules must be loaded (and their define-module forms evaluated) before
this macro runs so that their routes are in the registry.
Modules are late-bound: the registry is consulted at dispatch time, so
re-evaluating define-module takes effect immediately.
Static files are served by a global middleware under /static/ that searches
the project's static/ directory and per-module static/ directories."
  (let* ((app-var (intern (string-upcase (symbol-name name))))
         (modules (cdr (assoc :modules options)))
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
    `(defparameter ,app-var
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
        (lambda (env)
          (declare (ignore env))
          '(404 (:content-type "text/html") ("Not found")))))))

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
