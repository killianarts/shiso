(defpackage #:shiso/t/admin
  (:use #:cl #:lisp-unit2))

(in-package #:shiso/t/admin)

(defun fresh-registries ()
  (clrhash shiso/models:*model-registry*)
  (clrhash shiso/admin:*admin-registry*))

(defmacro with-fresh-registries (&body body)
  (let ((saved-models (gensym "MODELS"))
        (saved-admin (gensym "ADMIN"))
        (saved-modules (gensym "MODULES")))
    `(let ((,saved-models (alexandria:copy-hash-table shiso/models:*model-registry*))
           (,saved-admin (alexandria:copy-hash-table shiso/admin:*admin-registry*))
           (,saved-modules (alexandria:copy-hash-table shiso:*module-registry*)))
       (fresh-registries)
       (unwind-protect (progn ,@body)
         (setf shiso/models:*model-registry* ,saved-models
               shiso/admin:*admin-registry* ,saved-admin
               shiso:*module-registry* ,saved-modules)))))

(define-test register-admin-stores-config ()
  (with-fresh-registries
    (eval '(shiso/models:define-model admin-reg-test
             ((title :col-type (:varchar 200)))))
    (shiso/admin:register-admin 'admin-reg-test)
    (assert-true (typep (shiso/admin:get-admin 'admin-reg-test)
                        'shiso/admin:admin-config)
                 "get-admin should return an admin-config")))

(define-test register-admin-with-options ()
  (with-fresh-registries
    (eval '(shiso/models:define-model admin-opts-test
             ((title :col-type (:varchar 200))
              (status :col-type (:varchar 20)))))
    (shiso/admin:register-admin 'admin-opts-test
                                :per-page 50
                                :list-display '(title status))
    (let ((config (shiso/admin:get-admin 'admin-opts-test)))
      (assert-eql 50 (shiso/admin:admin-per-page config))
      (assert-equal '(title status) (shiso/admin:admin-list-display config)))))

(define-test get-admin-signals-error-for-missing ()
  (with-fresh-registries
    (assert-error 'error (shiso/admin:get-admin 'nonexistent-admin)
                  "get-admin should error for unregistered model")))

(define-test register-admin-errors-for-unknown-model ()
  (with-fresh-registries
    (assert-error 'error (shiso/admin:register-admin 'no-such-model-here)
                  "register-admin should error when the model does not exist")))

(define-test all-registered-admins-lists-names ()
  (with-fresh-registries
    (eval '(shiso/models:define-model admin-list-a
             ((x :col-type :text))))
    (eval '(shiso/models:define-model admin-list-b
             ((y :col-type :text))))
    (shiso/admin:register-admin 'admin-list-a)
    (shiso/admin:register-admin 'admin-list-b)
    (let ((names (shiso/admin:all-registered-admins)))
      (assert-true (member 'admin-list-a names))
      (assert-true (member 'admin-list-b names)))))

(define-test define-admin-registers-config ()
  (with-fresh-registries
    (eval '(shiso/models:define-model define-admin-test
             ((title :col-type (:varchar 200)))))
    (eval '(shiso/admin:define-admin define-admin-test
             (:per-page 30)))
    (let ((config (shiso/admin:get-admin 'define-admin-test)))
      (assert-eql 30 (shiso/admin:admin-per-page config)))))

(define-test define-admin-with-list-display ()
  (with-fresh-registries
    (eval '(shiso/models:define-model display-admin-test
             ((title :col-type (:varchar 200))
              (status :col-type (:varchar 20)))))
    (eval '(shiso/admin:define-admin display-admin-test
             (:list-display title status)))
    (let ((config (shiso/admin:get-admin 'display-admin-test)))
      (assert-equal '(title status) (shiso/admin:admin-list-display config)))))

(define-test define-admin-with-exclude ()
  (with-fresh-registries
    (eval '(shiso/models:define-model exclude-admin-test
             ((title :col-type (:varchar 200))
              (secret :col-type :text))))
    (eval '(shiso/admin:define-admin exclude-admin-test
             (:exclude secret)))
    (let ((config (shiso/admin:get-admin 'exclude-admin-test)))
      (assert-equal '(secret) (shiso/admin:admin-exclude config)))))

(define-test admin-module-is-registered ()
  (let ((module (shiso:get-module :shiso-admin)))
    (assert-true (typep module 'shiso:module)
                 "shiso-admin should be registered as a module")))

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

(defclass fake-staff-user () ())
(defmethod shiso/auth/user:user-is-staff ((u fake-staff-user)) t)
(defmethod shiso/auth/user:user-is-active ((u fake-staff-user)) t)

(defmacro with-fake-staff (&body body)
  "Stub `shiso/auth/user:find-user-by-id' to return a fake staff user
so module-level guards (which the admin module installs) treat the
request as authenticated."
  (let ((saved (gensym "SAVED")))
    `(let ((,saved (fdefinition 'shiso/auth/user:find-user-by-id)))
       (unwind-protect
            (progn
              (setf (fdefinition 'shiso/auth/user:find-user-by-id)
                    (lambda (id)
                      (declare (ignore id))
                      (make-instance 'fake-staff-user)))
              ,@body)
         (setf (fdefinition 'shiso/auth/user:find-user-by-id) ,saved)))))

(defun make-staff-env (path &key (method :GET))
  "Like `make-test-env' but with a session attached so the admin guard
treats the request as authenticated. Pair with `with-fake-staff'."
  (let ((env (make-test-env path :method method))
        (session (make-hash-table :test 'equal)))
    (setf (gethash :user-id session) 1)
    (append env (list :lack.session session
                      :lack.session.options (list :id "test-sid")))))

(define-test admin-module-dispatches-dashboard ()
  (with-fresh-registries
    (eval '(shiso/models:define-model dispatch-admin-test
             ((title :col-type (:varchar 200)))))
    (shiso/admin:register-admin 'dispatch-admin-test)
    (with-fake-staff
      (let ((module (shiso:get-module :shiso-admin)))
        (let ((response (lack/component:call module (make-staff-env "/"))))
          (assert-true (listp response) "Response should be a list")
          (assert-eql 200 (first response) "Dashboard should return 200"))))))

(define-test admin-dashboard-contains-model-links ()
  (with-fresh-registries
    (eval '(shiso/models:define-model link-test-model
             ((title :col-type (:varchar 200)))))
    (shiso/admin:register-admin 'link-test-model)
    (with-fake-staff
      (let* ((module (shiso:get-module :shiso-admin))
             (response (lack/component:call module (make-staff-env "/")))
             (body (third response)))
        (assert-true (search "link-test-model" (first body))
                     "Dashboard should contain model name in links")))))

(define-test admin-returns-404-for-unknown-route ()
  (with-fake-staff
    (let ((module (shiso:get-module :shiso-admin)))
      (let ((response (lack/component:call module
                                           (make-staff-env "/nonexistent/deeply/nested"))))
        (assert-eql 404 (first response)
                    "Unknown route should return 404")))))

(define-test admin-anonymous-redirects-to-login ()
  (let* ((module (shiso:get-module :shiso-admin))
         (response (lack/component:call module (make-test-env "/"))))
    (assert-eql 302 (first response)
                "Anonymous request to /admin should redirect to /login")
    (assert-true (search "/login"
                         (getf (second response) :location))
                 "Redirect should target /login")))
