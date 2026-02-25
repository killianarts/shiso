(uiop:define-package #:shiso
  (:use #:cl)
  (:nicknames #:shiso/main)
  (:export #:http-response
           #:*request*
           #:*response
           #:start
           #:stop
           #:*routes*
           #:routes
           #:routes-mapper
           #:define-route
           #:current-path
           #:static
           #:module
           #:module-routes
           #:make-module
           #:define-module
           #:define-application
           #:*module-registry*
           #:get-module
           #:register-module))

(in-package #:shiso/main)


;; * Request/Response

(defclass routes ()
  ((mapper :initarg :mapper :reader routes-mapper :initform nil)))

(defparameter *routes* (make-instance 'routes :mapper (myway:make-mapper)))

(defclass module (lack/component::lack-component)
  ((routes :initarg :routes :accessor module-routes)))

(defun make-module ()
  (make-instance 'application :routes *routes*))

(defparameter *request* nil)
(defparameter *response* nil)

(defmethod lack/component:call ((this application) env)
  (let ((*request* (handler-case (lack/request:make-request env)
                     (error (e)
                       (warn "~A" e)
                       (return-from lack/component:call '(400 () ("Bad Request")))))))
    (multiple-value-bind (response foundp)
        (myway:dispatch (routes-mapper (slot-value this 'routes))
                        (lack/request:request-path-info *request*)
                        :method (lack/request:request-method *request*))
      (if foundp
          (if (functionp response)
              response
              (destructuring-bind (status headers body) response
                (lack/response:finalize-response (lack/response:make-response status headers body))))
          (lack/response:finalize-response (lack/response:make-response 404 '(:content-type "text/html") '("Not found")))))))

(defmethod lack/component:call ((this module) env)
  (let ((*request* (handler-case (lack/request:make-request env)
                     (error (e)
                       (warn "~A" e)
                       (return-from lack/component:call '(400 () ("Bad Request")))))))
    (multiple-value-bind (response foundp)
        (myway:dispatch (routes-mapper (module-routes this))
                        (lack/request:request-path-info *request*)
                        :method (lack/request:request-method *request*))
      (if foundp
          (if (functionp response)
              response
              (destructuring-bind (status headers body) response
                (lack/response:finalize-response
                 (lack/response:make-response status headers body))))
          (lack/response:finalize-response
           (lack/response:make-response 404 '(:content-type "text/html") '("Not found")))))))

(defun http-response (body &key (code 200) (headers nil))
  (let ((headers (append `(:content-type "text/html; charset=utf-8") headers)))
    `(,code ,headers (,body))))

;; * Lack Mounting

(defparameter *blog-routes* (make-instance 'routes :mapper (myway:make-mapper)))
(defun blog-index ()
  (http-response "This is the blog index."))
(defun blog-list ()
  (http-response "This is the blog list page."))
(myway:connect (routes-mapper *blog-routes*) "/" (make-endpoint 'blog-index nil))
(myway:connect (routes-mapper *blog-routes*) "/list" (make-endpoint 'blog-list nil))

(defparameter *blog-app*
  (lack:builder (myway:to-app (routes-mapper *blog-routes*))))

(defparameter *shop-routes* (make-instance 'routes :mapper (myway:make-mapper)))
(defun shop-index ()
  (http-response "This is the shop index."))
(defun shop-cart ()
  (http-response "This is the shop cart page."))
(myway:connect (routes-mapper *shop-routes*) "/" (make-endpoint 'shop-index nil))
(myway:connect (routes-mapper *shop-routes*) "/cart" (make-endpoint 'shop-cart nil))

(defparameter *shop-app*
  (lack:builder (myway:to-app (routes-mapper *shop-routes*))))

(defun core-index ()
  (http-response "This is the core index."))
(myway:connect (routes-mapper *routes*) "/core" (make-endpoint 'core-index nil))

(defparameter *core-app*
  (lack:builder (:mount "/blog" *blog-app*) (:mount "/shop" *shop-app*) (myway:to-app (routes-mapper *routes*))))

#+nil
(shiso:start *core-app* :port 5001)

#+nil
(dex:get "http://localhost:5001/shop")

;; * Module Registry

(defvar *module-registry* (make-hash-table :test 'eq)
  "Global registry of defined modules, keyed by module name (keyword).")

(defun register-module (name module)
  (setf (gethash name *module-registry*) module))

(defun get-module (name)
  (or (gethash name *module-registry*)
      (error "Module ~A is not registered." name)))

;; * Routes

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

(defun define-route (method routing-rule &key controller name (regexp nil))
  (let ((param-keys (myway.rule::rule-param-keys
                     (myway.rule::make-rule routing-rule))))
    (multiple-value-bind (name namespace)
        (get-name-and-namespace name)
      (myway:connect (routes-mapper (application-routes *app*))
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

(defun url (name &rest params)
  "Return the url for a named route given the parameters. For use in templates."
  (myway:url-for (myway:find-route-by-name (routes-mapper *routes*) name) params))

;; * Module & Application Definition

(defmacro define-module (name &body options)
  "Define a module with its own routes and register it globally.

Usage:
  (define-module articles
    (:urls (:GET         \"/\"       #'controllers:index  \"index\")
           ((:GET :POST) \"/create\" #'controllers:create \"create\")))

Each URL spec is (METHOD PATH CONTROLLER NAME).
METHOD can be a keyword or a list of keywords.
Route names are namespaced under the module name (e.g., articles:index)."
  (let* ((module-name-str (string-downcase (symbol-name name)))
         (module-keyword (intern (string-upcase (symbol-name name)) :keyword))
         (routes-var (gensym "ROUTES-"))
         (mapper-var (gensym "MAPPER-"))
         (module-var (gensym "MODULE-"))
         (urls (cdr (assoc :urls options))))
    `(progn
       (let* ((,mapper-var (myway:make-mapper))
              (,routes-var (make-instance 'routes :mapper ,mapper-var)))
         ;; Connect each URL to the mapper
         ,@(loop for url-spec in urls
                 append
                 (destructuring-bind (method path controller route-name) url-spec
                   (let* ((full-name (concatenate 'string module-name-str ":" route-name))
                          (methods (if (listp method) method (list method))))
                     (loop for m in methods
                           collect
                           `(let* ((param-keys (myway.rule::rule-param-keys
                                                (myway.rule::make-rule ,path)))
                                   (endpoint (make-endpoint ,controller param-keys)))
                              (multiple-value-bind (route-name-kw namespace-kw)
                                  (get-name-and-namespace ,full-name)
                                (myway:connect ,mapper-var ,path endpoint
                                               :method ,m
                                               :name route-name-kw
                                               :namespace namespace-kw)))))))
         ;; Create the module instance
         (let ((,module-var (make-instance 'module :routes ,routes-var)))
           ;; Create *module* as a lack:builder wrapping the module
           (defparameter *module*
             (lack:builder ,module-var))
           ;; Register in global registry
           (register-module ,module-keyword ,module-var)))
       ',name)))

(defmacro define-application (name () &body options)
  "Define an application that composes modules via Lack's :mount middleware.

Usage:
  (define-application my-app ()
    (:modules '(blog shop)))

  ;; With explicit mount points:
  (define-application my-app ()
    (:modules '((\"/\" core) blog shop)))

Bare symbol BLOG mounts at /blog. Tuple (\"/\" CORE) mounts at /."
  (let* ((app-var (intern (concatenate 'string "*" (string-upcase (symbol-name name)) "*")))
         (modules-form (cadr (assoc :modules options))))
    `(defparameter ,app-var
       (lack:builder
        ,@(loop for mod-spec in (cadr modules-form) ; unwrap the quote
                collect
                (if (listp mod-spec)
                    (destructuring-bind (mount-path mod-name) mod-spec
                      `(:mount ,mount-path (get-module ,(intern (string-upcase (symbol-name mod-name)) :keyword))))
                    `(:mount ,(concatenate 'string "/" (string-downcase (symbol-name mod-spec)))
                             (get-module ,(intern (string-upcase (symbol-name mod-spec)) :keyword)))))
        ;; Base app: return 404 for unmatched routes
        (lambda (env)
          (declare (ignore env))
          '(404 (:content-type "text/html") ("Not found")))))))

;; * Server
(defparameter *server-connection* nil)

(defun start (app &key (host "127.0.0.1") (port 5000) (debugp t))
  (when *server-connection*
    (restart-case (error "Server is already running.")
      (restart-server ()
        :report "Restart the server"
        (stop))))
  (setf *server-connection*
        (clack:clackup app :server :woo :address host :port port :debug debugp)))

(defun stop ()
  (prog1
      (clack:stop *server-connection*)
    (setf *server-connection* nil)))

;; * Template Utils
(defun current-path ()
  "Get the path to the current page."
  (lack/request:request-path-info *request*))

(defun static (path)
  (let ((scheme (lack.request:request-uri-scheme *request*))
        (server-name (lack.request:request-server-name *request*)))
    (format nil "~a://~a/~a" scheme server-name path)))

