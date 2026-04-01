(defpackage #:shiso/routing
  (:use #:cl)
  (:local-nicknames (#:modules #:shiso/modules))
  (:export
   #:routes
   #:routes-mapper
   #:*routes*
   #:*global-routes-namespace*
   #:define-route
   #:define-routes
   #:define-module
   #:define-application
   #:to-symbol
   #:to-symbol-form
))

(in-package #:shiso/routing)

(defclass routes ()
  ((mapper :initarg :mapper :reader routes-mapper :initform nil)))

(defparameter *routes* (make-instance 'routes :mapper (myway:make-mapper)))

(defparameter *global-routes-namespace* :global)

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

(defun get-name-and-namespace (name)
  (let ((pos (position #\: name)))
    (if pos
        (values (intern (string-upcase (subseq name (1+ pos))) :keyword)
                (intern (string-upcase (subseq name 0 pos)) :keyword))
        (values (intern (string-upcase name) :keyword)
                *global-routes-namespace*))))

(defun define-route (method routing-rule &key controller name (regexp nil) (routes *routes*))
  (let ((param-keys (myway.rule::rule-param-keys
                     (myway.rule::make-rule routing-rule))))
    (multiple-value-bind (name namespace)
        (get-name-and-namespace name)
      (myway:connect (routes-mapper routes)
                     routing-rule
                     (make-endpoint controller param-keys)
                     :method method
                     :name name
                     :namespace namespace
                     :regexp regexp))))

(defmacro define-routes (module &rest args)
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
Routes are registered with their original paths on the module's own mapper.
Route names are namespaced under the module name (e.g., articles:index).
The module instance is stored in the registry for url generation and mounting."
  (let* ((module-name-str (string-downcase (symbol-name name)))
         (module-keyword (intern (string-upcase (symbol-name name)) :keyword))
         (urls (cdr (assoc :urls options)))
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
                   (let* ((full-name (concatenate 'string module-name-str ":" route-name))
                          (controller-symbol (to-symbol-form controller))
                          (methods (if (listp method) method (list method))))
                     (loop for m in methods
                           collect `(define-route ,m ,path
                                      :controller ,controller-symbol
                                      :name ,full-name
                                      :routes ,module-routes-var)))))
         (modules:register-module ,module-keyword
                          (make-instance 'modules:module
                                         :routes ,module-routes-var
                                         :static-root ,static-root)))
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
        ;; Strip trailing slashes (redirect 301)
        (lambda (app)
          (lambda (env)
            (let ((path (getf env :path-info)))
              (if (and (> (length path) 1)
                       (char= (char path (1- (length path))) #\/))
                  (let ((clean (string-right-trim "/" path)))
                    (list 301
                          (list :location clean)
                          (list "")))
                  (funcall app env)))))
        ;; Module mounts
        ,@(loop for (prefix mod-name) in modules
                for mod-kw = (intern (string-upcase (symbol-name mod-name)) :keyword)
                collect `(:mount ,prefix
                          (lambda (env)
                            (let ((mod (modules:get-module ,mod-kw)))
                              (setf (modules:module-prefix mod) ,prefix)
                              (lack/component:call mod env)))))
        (lambda (env)
          (declare (ignore env))
          '(404 (:content-type "text/html") ("Not found")))))))
