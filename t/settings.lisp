(defpackage #:shiso/t/settings
  (:use #:cl #:lisp-unit2))

(in-package #:shiso/t/settings)

;;; Settings in Shiso: its environment setting, its conditions, its own
;;; settings, absolute URLs and the database. Each test loads the settings
;;; from an environment of its own, in a configuration of its own.

(defun fake-environment (&rest names-and-values)
  (lambda (name)
    (loop for (variable value) on names-and-values by #'cddr
          when (string= variable name)
            return value)))

(defmacro with-environment ((&rest names-and-values) &body body)
  "Run BODY with the settings loaded from NAMES-AND-VALUES, environment
variables, in development unless SHISO_ENV says otherwise."
  `(let ((almighty-settei:*configuration* nil))
     (almighty-settei:load-settings :getenv (fake-environment ,@names-and-values)
                                    :dotenv nil
                                    :environment :development)
     ,@body))

(defun value (name)
  (shiso:setting name))

(define-test the-environment-is-shisos ()
  (with-environment ()
    (assert-eq :development (shiso:current-environment))
    (assert-true (shiso:find-setting :shiso/environment))
    (assert-false (shiso:find-setting :settei/environment :errorp nil)))
  (with-environment ("SHISO_ENV" "test")
    (assert-true (shiso:test-p))))

(define-test the-conditions-are-shisos ()
  (let ((condition (handler-case (with-environment ("PORT" "port"))
                     (error (condition) condition))))
    (assert-typep 'shiso:settings-invalid condition)
    (assert-equal "SHISO/SETTINGS" (package-name (symbol-package (type-of condition)))))
  (with-environment ()
    (assert-error 'shiso:setting-unknown (value :shiso/nothing))))

(define-test variables-derived-with-shisos-prefix ()
  (assert-equal '("SHISO_STATIC_MANIFEST")
                (almighty-settei:setting-environment-variables
                 (shiso:find-setting :static/manifest)))
  (assert-equal '("SHISO_SITE_ORIGIN")
                (almighty-settei:setting-environment-variables
                 (shiso:find-setting :shiso/site-origin))))

(define-test the-servers-settings ()
  (with-environment ()
    (assert-equal "127.0.0.1" (value :server/host))
    (assert-eql 5000 (value :server/port))
    (assert-eq t (value :server/debugp))
    (assert-eq :woo (value :server/backend)))
  ;; The variables deployments already set still work.
  (with-environment ("HOST" "0.0.0.0" "PORT" "5002" "DEBUGP" "false" "SHISO_ENV" "production"
                     "SHISO_SITE_ORIGIN" "https://example.com" "DATABASE_PATH" "db/app.db")
    (assert-equal "0.0.0.0" (value :server/host))
    (assert-eql 5002 (value :server/port))
    (assert-eq nil (value :server/debugp))))

(define-test the-site-origin ()
  (with-environment ("PORT" "5002")
    (assert-equal "http://localhost:5002" (value :shiso/site-origin)))
  (let ((problems (handler-case (with-environment ("SHISO_ENV" "production"))
                    (shiso:settings-invalid (condition)
                      (mapcar #'shiso:problem-name (shiso:settings-invalid-problems condition))))))
    ;; Production requires both.
    (assert-equal '(:shiso/site-origin :database/name) problems))
  (assert-error 'shiso:settings-invalid
                (with-environment ("SHISO_SITE_ORIGIN" "example.com")))
  (assert-error 'shiso:settings-invalid
                (with-environment ("SHISO_SITE_ORIGIN" "https://example.com/blog"))))

(defun request-for (host &key forwarded-proto (scheme "http"))
  (let ((headers (make-hash-table :test 'equal)))
    (setf (gethash "host" headers) host)
    (when forwarded-proto
      (setf (gethash "x-forwarded-proto" headers) forwarded-proto))
    (lack/request:make-request (list :headers headers :url-scheme scheme
                                     :request-method :get :path-info "/"))))

(define-test absolute-urls ()
  (with-environment ("SHISO_SITE_ORIGIN" "https://example.com")
    ;; Without a request: the site's origin.
    (let ((shiso/requests:*request* nil))
      (assert-equal "https://example.com/a" (shiso:absolute-url "/a")))
    ;; A request for the site: its origin, though the proxy spoke http.
    (let ((shiso/requests:*request* (request-for "example.com")))
      (assert-equal "https://example.com/a" (shiso:absolute-url "/a")))
    ;; A request for this machine: this machine.
    (let ((shiso/requests:*request* (request-for "localhost:5002")))
      (assert-equal "http://localhost:5002/a" (shiso:absolute-url "/a")))
    (let ((shiso/requests:*request* (request-for "staging.example.com" :forwarded-proto "https")))
      (assert-equal "https://staging.example.com/a" (shiso:absolute-url "/a")))))

(define-test the-database ()
  (with-environment ("SHISO_ENV" "test")
    (assert-equal ":memory:" (value :database/name))
    (let ((mito:*connection* nil)
          (shiso/database::*connected-to* nil)
          (after 0))
      (let ((shiso/database:*after-database* (lambda () (incf after))))
        (shiso:setup-database))
      (unwind-protect
           (progn
             (assert-true mito:*connection*)
             (assert-eql 1 after)
             (assert-true (dbi:fetch (dbi:execute (dbi:prepare mito:*connection*
                                                               "SELECT name FROM sqlite_master WHERE name = 'shiso_session'"))))
             ;; Connecting again with the same settings keeps the connection.
             (let ((connection mito:*connection*))
               (shiso:connect-database)
               (assert-eq connection mito:*connection*)))
        (dbi:disconnect mito:*connection*)))))

(define-test the-database-connection-arguments ()
  (with-environment ("SHISO_ENV" "test")
    (shiso:with-settings (:database/driver :postgres :database/name "app" :database/host "db.internal"
                          :database/user "app" :database/password "s3cret-password")
      (assert-equal '(:postgres :database-name "app" :host "db.internal" :username "app"
                      :password "s3cret-password")
                    (shiso/database::connection-arguments)))))

(define-test secrets-are-redacted ()
  (with-environment ("SHISO_ENV" "test" "SHISO_DATABASE_PASSWORD" "s3cret-password")
    (assert-equal "could not connect with ••••"
                  (shiso:redact "could not connect with s3cret-password"))))

(define-test the-settings-command ()
  (assert-true (gethash "settings" shiso/management:*commands*)))
