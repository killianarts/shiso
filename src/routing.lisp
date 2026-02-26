(defpackage #:shiso/routing
  (:use #:cl)
  (:export
   #:routes
   #:routes-mapper
   #:module
   #:module-routes
   #:module-prefix
   #:*routes*
   #:*global-routes-namespace*
   #:define-route
   #:define-routes
   #:define-module
   #:define-application
   #:*module-registry*
   #:register-module
   #:get-module
))
(in-package #:shiso/routing)

(defclass routes ()
  ((mapper :initarg :mapper :reader routes-mapper :initform nil)))

(defparameter *routes* (make-instance 'routes :mapper (myway:make-mapper)))

(defclass module (lack/component::lack-component)
  ((routes :initarg :routes :accessor module-routes)
   (prefix :initarg :prefix :accessor module-prefix :initform "")))

;; * Route Helpers

(defparameter *global-routes-namespace* :global)

(defun make-endpoint (fn param-keys)
  (if param-keys
      (lambda (params)
        (apply fn (mapcar (lambda (key) (getf params key)) param-keys)))
      (lambda (params)
        (declare (ignore params))
        (funcall fn))))

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
               for full-path = (concatenate 'string root path)
               for full-name = (concatenate 'string module-name ":" name)
               append (let ((methods (if (listp method) method (list method))))
                        (loop for m in methods
                              collect `(define-route ,m ,full-path
                                         :controller ,controller
                                         :name ,full-name)))))))



;; * define-module / define-application

(defvar *module-registry* (make-hash-table :test 'eq)
  "Global registry of defined modules, keyed by module name (keyword).")

(defun register-module (name module)
  (setf (gethash name *module-registry*) module))

(defun get-module (name)
  (or (gethash name *module-registry*)
      (error "Module ~A is not registered." name)))

(defmacro define-module (name &body options)
  "Define a module with routes on a per-module mapper (un-prefixed).

Usage:
  (define-module articles
    (:urls (:GET         \"/\"       #'controllers:index  \"index\")
           ((:GET :POST) \"/create\" #'controllers:create \"create\")))

Each URL spec is (METHOD PATH CONTROLLER NAME).
METHOD can be a keyword or a list of keywords.
Routes are registered with their original paths on the module's own mapper.
Route names are namespaced under the module name (e.g., articles:index).
The module instance is stored in the registry for url generation and mounting."
  (let* ((module-name-str (string-downcase (symbol-name name)))
         (module-keyword (intern (string-upcase (symbol-name name)) :keyword))
         (urls (cdr (assoc :urls options)))
         (module-routes-var (gensym "MODULE-ROUTES")))
    `(progn
       (let ((,module-routes-var (make-instance 'routes :mapper (myway:make-mapper))))
         ,@(loop for url-spec in urls
                 append
                 (destructuring-bind (method path controller route-name) url-spec
                   (let* ((full-name (concatenate 'string module-name-str ":" route-name))
                          (methods (if (listp method) method (list method))))
                     (loop for m in methods
                           collect `(define-route ,m ,path
                                      :controller ,controller
                                      :name ,full-name
                                      :routes ,module-routes-var)))))
         (register-module ,module-keyword
                          (make-instance 'module :routes ,module-routes-var)))
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
this macro runs so that their routes are in the registry."
  (let* ((app-var (intern (string-upcase (symbol-name name))))
         (modules (cdr (assoc :modules options))))
    `(progn
       ,@(loop for (prefix mod-name) in modules
               for mod-kw = (intern (string-upcase (symbol-name mod-name)) :keyword)
               collect `(setf (module-prefix (get-module ,mod-kw)) ,prefix))
       (defparameter ,app-var
         (lack:builder
          ,@(loop for (prefix mod-name) in modules
                  for mod-kw = (intern (string-upcase (symbol-name mod-name)) :keyword)
                  collect `(:mount ,prefix
                                   (lack:builder (get-module ,mod-kw))))
          (lambda (env)
            (declare (ignore env))
            '(404 (:content-type "text/html") ("Not found"))))))))
