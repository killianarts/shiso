(defpackage #:shiso/t/routes
  (:use #:cl #:lisp-unit2))

(in-package #:shiso/t/routes)

(defmacro with-fresh-routes (&body body)
  "Bind shiso:*routes* to a fresh routes instance for testing."
  `(let ((shiso:*routes* (make-instance 'shiso:routes
                                        :mapper (myway:make-mapper))))
     ,@body))

(defun registered-routes ()
  "Return all routes from the current *routes* mapper."
  (myway.mapper:mapper-routes
   (shiso:routes-mapper shiso:*routes*)))

(defun find-route (name)
  "Find a route by MyWay name keyword."
  (find-if (lambda (route)
             (eq (myway.route:route-name route) name))
           (registered-routes)))

(defun route-url (route)
  "Get the URL string from a route's rule."
  (myway.rule::rule-url (myway.route:route-rule route)))

(define-test define-route-registers-a-route ()
  (with-fresh-routes
    (shiso:define-route :GET "/test"
      :controller (lambda () "test")
      :name "test")
    (let ((route (find-route :TEST)))
      (assert-true route "Route should be registered")
      (assert-string= "/test" (route-url route)))))

(define-test define-route-coerces-string-name-to-keyword ()
  (with-fresh-routes
    (shiso:define-route :GET "/admin/index"
      :controller (lambda () "admin index")
      :name "admin:index")
    (let ((route (find-route (intern "ADMIN:INDEX" :keyword))))
      (assert-true route "Compound name should be registered as one keyword")
      (assert-string= "/admin/index" (route-url route)))))

(define-test define-routes-expands-to-define-route-calls ()
  (let* ((form `(shiso::define-routes test-mod :root "/app"
                  (:GET "/" #'identity "index")
                  (:GET "/list" #'identity "list")))
         (expansion (macroexpand-1 form)))
    (assert-true (eq 'progn (first expansion)))
    (assert-eql 2 (length (rest expansion))
                "Should expand to two define-route calls")))

(define-test define-routes-concatenates-root-with-path ()
  (let* ((form `(shiso::define-routes test-mod :root "/app"
                  (:GET "/users" #'identity "users")))
         (expansion (macroexpand-1 form))
         (call (second expansion)))
    (assert-string= "/app/users" (third call)
                    "Root should be concatenated with path")))

(define-test define-routes-prefixes-module-name-to-route-name ()
  (let* ((form `(shiso::define-routes admin :root "/admin"
                  (:GET "/users" #'identity "users")))
         (expansion (macroexpand-1 form))
         (call (second expansion)))
    (assert-string= "admin:users" (getf (cdddr call) :name)
                    "Module name should be prefixed to route name for global uniqueness")))

(define-test define-routes-expands-multiple-methods-to-separate-calls ()
  (let* ((form `(shiso::define-routes admin :root "/admin"
                  ((:GET :POST) "/create" #'identity "create")))
         (expansion (macroexpand-1 form))
         (calls (rest expansion)))
    (assert-eql 2 (length calls)
                "Two methods should produce two define-route calls")
    (assert-eq :GET (second (first calls))
               "First call should use :GET")
    (assert-eq :POST (second (second calls))
               "Second call should use :POST")))

(define-test define-routes-with-empty-root ()
  (let* ((form `(shiso::define-routes teaser :root ""
                  (:GET "/" #'identity "index")))
         (expansion (macroexpand-1 form))
         (call (second expansion)))
    (assert-string= "/" (third call)
                    "Empty root should leave path unchanged")))

(define-test define-routes-registers-all-routes ()
  (with-fresh-routes
    (eval '(shiso::define-routes admin :root "/admin"
            (:GET "/" (lambda () "index") "index")
            (:GET "/users" (lambda () "users") "users")
            (:DELETE "/delete" (lambda () "delete") "delete")))
    (assert-eql 3 (length (registered-routes))
                "All three routes should be registered")
    (assert-true (find-route (intern "ADMIN:INDEX" :keyword))
                 "admin:index should exist")
    (assert-true (find-route (intern "ADMIN:USERS" :keyword))
                 "admin:users should exist")
    (assert-true (find-route (intern "ADMIN:DELETE" :keyword))
                 "admin:delete should exist")))

(define-test define-routes-registers-correct-rules ()
  (with-fresh-routes
    (eval '(shiso::define-routes admin :root "/admin"
            (:GET "/users" (lambda () "users") "users")))
    (let ((route (find-route (intern "ADMIN:USERS" :keyword))))
      (assert-string= "/admin/users" (route-url route)
                      "Route rule should have root prepended"))))
