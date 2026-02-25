(defpackage #:shiso/t/modules
  (:use #:cl #:lisp-unit2))

(in-package #:shiso/t/modules)

;;; --- Helpers ---

(defun fresh-registry ()
  "Clear the module registry for a clean test."
  (clrhash shiso:*module-registry*))

(defmacro with-fresh-registry (&body body)
  `(progn
     (fresh-registry)
     (unwind-protect (progn ,@body)
       (fresh-registry))))

(defun mapper-routes-list (module)
  "Get all routes from a module's mapper as a list."
  (let ((raw (myway.mapper:mapper-routes
              (shiso:routes-mapper (shiso:module-routes module)))))
    (if (listp raw)
        raw
        (let ((routes nil))
          (map-set:ms-for-each
           (lambda (route) (push route routes))
           raw)
          routes))))

(defun find-module-route (module name namespace)
  "Find a route by name and namespace in a module."
  (find-if (lambda (route)
             (and (eq (myway.route:route-name route) name)
                  (eq (myway.route:route-namespace route) namespace)))
           (mapper-routes-list module)))

(defun route-url (route)
  "Get the URL string from a route's rule."
  (myway.rule::rule-url (myway.route:route-rule route)))

(defun route-methods (route)
  "Get the HTTP methods from a route's rule as a list."
  (let ((raw (slot-value (myway.route:route-rule route) 'myway.rule::methods)))
    (if (listp raw)
        raw
        (let ((methods nil))
          (map-set:ms-for-each
           (lambda (m) (push m methods))
           raw)
          methods))))

;;; --- Module Registry Tests ---

(define-test register-module-stores-module ()
  (with-fresh-registry
    (let ((mod (make-instance 'shiso:module
                              :routes (make-instance 'shiso:routes
                                                     :mapper (myway:make-mapper)))))
      (shiso:register-module :test mod)
      (assert-true (eq mod (shiso:get-module :test))
                   "get-module should return the registered module"))))

(define-test get-module-signals-error-for-missing ()
  (with-fresh-registry
    (assert-error 'error (shiso:get-module :nonexistent)
                  "get-module should signal an error for unregistered modules")))

(define-test register-module-overwrites-existing ()
  (with-fresh-registry
    (let ((mod1 (make-instance 'shiso:module
                               :routes (make-instance 'shiso:routes
                                                      :mapper (myway:make-mapper))))
          (mod2 (make-instance 'shiso:module
                               :routes (make-instance 'shiso:routes
                                                      :mapper (myway:make-mapper)))))
      (shiso:register-module :test mod1)
      (shiso:register-module :test mod2)
      (assert-true (eq mod2 (shiso:get-module :test))
                   "Re-registering should overwrite the previous module"))))

;;; --- define-module Macro Expansion Tests ---

(define-test define-module-expands-to-progn ()
  (let ((expansion (macroexpand-1
                    '(shiso:define-module test-mod
                       (:urls (:GET "/" #'identity "index"))))))
    (assert-true (eq 'progn (first expansion))
                 "define-module should expand to a progn")))

(define-test define-module-expansion-ends-with-quoted-name ()
  (let ((expansion (macroexpand-1
                    '(shiso:define-module my-mod
                       (:urls (:GET "/" #'identity "index"))))))
    (let ((last-form (car (last expansion))))
      (assert-true (and (listp last-form)
                        (eq 'quote (first last-form))
                        (eq 'my-mod (second last-form)))
                   "Last form should be the quoted module name"))))

(define-test define-module-expands-multiple-methods ()
  (let ((expansion (macroexpand-1
                    '(shiso:define-module test-mod
                       (:urls ((:GET :POST) "/create" #'identity "create"))))))
    ;; The let* body should have two connect forms (one for GET, one for POST)
    ;; plus the final module creation let
    (let* ((let-form (second expansion))       ; the let* form
           (body (cddr let-form))              ; body of the let*
           (connect-forms (butlast body)))     ; everything except the final let
      (assert-eql 2 (length connect-forms)
                  "Two methods should produce two connect forms"))))

;;; --- define-module Integration Tests ---

(define-test define-module-registers-in-registry ()
  (with-fresh-registry
    (eval '(shiso:define-module registry-test
             (:urls (:GET "/" (lambda () (shiso:http-response "hi")) "index"))))
    (let ((mod (shiso:get-module :registry-test)))
      (assert-true (typep mod 'shiso:module)
                   "Module should be registered and retrievable"))))

(define-test define-module-creates-routes ()
  (with-fresh-registry
    (eval '(shiso:define-module routes-test
             (:urls (:GET "/" (lambda () (shiso:http-response "index")) "index")
                    (:GET "/list" (lambda () (shiso:http-response "list")) "list"))))
    (let ((mod (shiso:get-module :routes-test)))
      (assert-eql 2 (length (mapper-routes-list mod))
                  "Module should have two routes registered"))))

(define-test define-module-namespaces-route-names ()
  (with-fresh-registry
    (eval '(shiso:define-module articles
             (:urls (:GET "/" (lambda () (shiso:http-response "index")) "index"))))
    (let ((mod (shiso:get-module :articles)))
      (assert-true (find-module-route mod :INDEX :ARTICLES)
                   "Route should be namespaced under module name"))))

(define-test define-module-handles-multiple-methods ()
  (with-fresh-registry
    (eval '(shiso:define-module multi-method
             (:urls ((:GET :POST) "/form" (lambda () (shiso:http-response "form")) "form"))))
    (let* ((mod (shiso:get-module :multi-method))
           (routes (mapper-routes-list mod)))
      (assert-eql 2 (length routes)
                  "Two methods should create two routes")
      (let ((all-methods (loop for r in routes append (route-methods r))))
        (assert-true (member :GET all-methods) "Should have a GET route")
        (assert-true (member :POST all-methods) "Should have a POST route")))))

(define-test define-module-sets-star-module-star ()
  (with-fresh-registry
    (eval '(shiso:define-module star-test
             (:urls (:GET "/" (lambda () (shiso:http-response "hi")) "index"))))
    (assert-true (boundp 'shiso::*module*)
                 "*module* should be bound")
    (assert-true (functionp (symbol-value 'shiso::*module*))
                 "*module* should be a Lack app function")))

(define-test define-module-creates-correct-route-urls ()
  (with-fresh-registry
    (eval '(shiso:define-module url-test
             (:urls (:GET "/users/:id" (lambda (id) (shiso:http-response id)) "show"))))
    (let* ((mod (shiso:get-module :url-test))
           (route (find-module-route mod :SHOW :URL-TEST)))
      (assert-true route "Route should exist")
      (assert-string= "/users/:id" (route-url route)
                      "Route URL should be preserved"))))

;;; --- define-application Macro Expansion Tests ---

(define-test define-application-expands-to-defparameter ()
  (let ((expansion (macroexpand-1
                    '(shiso:define-application my-app ()
                       (:modules '(blog shop))))))
    (assert-true (eq 'defparameter (first expansion))
                 "Should expand to defparameter")
    (assert-true (char= #\* (char (symbol-name (second expansion)) 0))
                 "Variable name should start with *")))

(define-test define-application-generates-mount-entries ()
  (let ((expansion (macroexpand-1
                    '(shiso:define-application my-app ()
                       (:modules '(blog shop))))))
    ;; expansion = (DEFPARAMETER *MY-APP* (LACK:BUILDER mount1 mount2 fallback))
    (let ((builder-args (cdr (third expansion)))) ; skip LACK/BUILDER:BUILDER symbol
      ;; Should have :mount for blog, :mount for shop, and the 404 lambda
      (assert-eql 3 (length builder-args)
                  "Should have two mount entries plus fallback"))))

(define-test define-application-bare-symbol-mounts-at-slash-name ()
  (let ((expansion (macroexpand-1
                    '(shiso:define-application my-app ()
                       (:modules '(blog))))))
    ;; expansion = (DEFPARAMETER *MY-APP* (LACK:BUILDER (:MOUNT "/blog" ...) (LAMBDA ...)))
    (let* ((builder-form (third expansion))
           (mount-entry (second builder-form))) ; first arg to builder
      (assert-eq :mount (first mount-entry))
      (assert-string= "/blog" (second mount-entry)
                      "Bare symbol should mount at /name"))))

(define-test define-application-tuple-uses-explicit-path ()
  (let ((expansion (macroexpand-1
                    '(shiso:define-application my-app ()
                       (:modules '(("/" core)))))))
    (let* ((builder-form (third expansion))
           (mount-entry (second builder-form)))
      (assert-eq :mount (first mount-entry))
      (assert-string= "/" (second mount-entry)
                      "Tuple should use the explicit path"))))

;;; --- define-application Integration Tests ---

(define-test define-application-creates-lack-app ()
  (with-fresh-registry
    (eval '(shiso:define-module app-mod
             (:urls (:GET "/" (lambda () (shiso:http-response "hi")) "index"))))
    (eval '(shiso:define-application integration-app ()
             (:modules '(app-mod))))
    (assert-true (boundp (intern "*INTEGRATION-APP*" :cl-user))
                 "Application variable should be bound")
    (assert-true (functionp (symbol-value (intern "*INTEGRATION-APP*" :cl-user)))
                 "Application should be a function (Lack app)")))

;;; --- Module call Method Tests ---

(defun make-test-env (path &key (method :GET))
  "Create a minimal Lack environment for testing."
  (list :request-method method
        :request-uri path
        :path-info path
        :query-string ""
        :server-name "localhost"
        :server-port 5000
        :server-protocol :http/1.1
        :url-scheme "http"
        :remote-addr "127.0.0.1"
        :remote-port 12345
        :content-type nil
        :content-length nil
        :headers (make-hash-table :test 'equal)
        :input (make-string-input-stream "")))

(define-test module-call-dispatches-to-matching-route ()
  (with-fresh-registry
    (eval '(shiso:define-module dispatch-test
             (:urls (:GET "/" (lambda () (shiso:http-response "hello")) "index"))))
    (let* ((mod (shiso:get-module :dispatch-test))
           (response (lack/component:call mod (make-test-env "/"))))
      (assert-true (listp response) "Response should be a list")
      (assert-eql 200 (first response) "Status should be 200"))))

(define-test module-call-returns-404-for-unmatched ()
  (with-fresh-registry
    (eval '(shiso:define-module notfound-test
             (:urls (:GET "/" (lambda () (shiso:http-response "hi")) "index"))))
    (let* ((mod (shiso:get-module :notfound-test))
           (response (lack/component:call mod (make-test-env "/nonexistent"))))
      (assert-true (listp response) "Response should be a list")
      (assert-eql 404 (first response) "Status should be 404"))))
