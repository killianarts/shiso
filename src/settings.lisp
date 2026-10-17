(defpackage #:shiso/settings
  (:use #:cl)
  (:local-nicknames (#:settei #:almighty-settei))
  ;; Shiso's own conditions, signalled in the place of the library's of the
  ;; same names, so that users and the debugger see Shiso's.
  (:shadow #:settings-invalid #:setting-invalid #:setting-unknown
           #:settings-not-loaded #:secret-configured #:unknown-setting-warning)
  (:export #:settings-invalid #:setting-invalid #:setting-unknown
           #:settings-not-loaded #:secret-configured #:unknown-setting-warning
           #:site-origin-host))

(in-package #:shiso/settings)

;;;; Settings: Shiso's, and every application's and module's, declared where
;;;; they are used, set in one place (CONFIGURE in the application's
;;;; settings file), read from the environment when the server starts. The
;;;; machinery is almighty-settei's; what a Shiso user sees is Shiso's: the
;;;; names in the SHISO package, SHISO_ENV, SHISO_ variables, and these
;;;; conditions.

;;; Conditions

(define-condition settings-invalid (settei:settings-invalid) ())
(define-condition setting-invalid (settei:setting-invalid) ())
(define-condition setting-unknown (settei:setting-unknown) ())
(define-condition settings-not-loaded (settei:settings-not-loaded) ())
(define-condition secret-configured (settei:secret-configured) ())
(define-condition unknown-setting-warning (settei:unknown-setting-warning) ())

(loop for (library ours) in '((settei:settings-invalid settings-invalid)
                              (settei:setting-invalid setting-invalid)
                              (settei:setting-unknown setting-unknown)
                              (settei:settings-not-loaded settings-not-loaded)
                              (settei:secret-configured secret-configured)
                              (settei:unknown-setting-warning unknown-setting-warning))
      do (settei:use-condition-class library ours))

;;; The environment, and variables' names

(settei:define-environment-setting :shiso/environment
  "What kind of machine this is: development, test or production. Other
settings' defaults depend on it. In the REPL it is development, and in a
built program production, unless SHISO_ENV says otherwise, in the
environment or in the project's .env file."
  :environment "SHISO_ENV")

;; A setting without :environment is set by SHISO_<MODULE>_<NAME>.
(setf settei:*environment-variable-prefix* "SHISO_")

;;; The site

(defun site-origin-host (origin)
  "ORIGIN's host and port, without its scheme: \"almightylisp.com\" for
\"https://almightylisp.com\"."
  (let* ((start (let ((scheme (search "://" origin)))
                  (if scheme (+ scheme 3) 0)))
         (end (position #\/ origin :start start)))
    (subseq origin start end)))

(settei:define-setting :shiso/site-origin settei:string-setting
  "The scheme and host of the public site, like https://example.com, for
absolute URLs: links the social sites and emails carry, and pages written
without a request. In development, http://localhost and the server's port."
  :required-in :production
  :validator (lambda (origin configuration)
               (declare (ignore configuration))
               (cond ((not (or (eql 0 (search "http://" origin))
                               (eql 0 (search "https://" origin))))
                      "is not an origin starting with http:// or https://")
                     ((find #\/ origin :start (+ 3 (search "://" origin)))
                      "has a path; an origin is only a scheme and host")))
  :default (lambda (configuration)
             (when (settei:development-p configuration)
               (format nil "http://localhost:~d" (settei:setting :server/port configuration)))))

;;; The server

(settei:define-setting :server/host settei:string-setting
  "The address the server listens on: 127.0.0.1 for this machine only,
0.0.0.0 for every interface."
  :environment '("SHISO_SERVER_HOST" "HOST")
  :default "127.0.0.1")

(settei:define-setting :server/port settei:integer-setting
  "The port the server listens on."
  :environment '("SHISO_SERVER_PORT" "PORT")
  :minimum 1 :maximum 65535
  :default 5000)

(settei:define-setting :server/debugp settei:boolean-setting
  "Whether the server runs in debug mode."
  :environment '("SHISO_SERVER_DEBUGP" "DEBUGP")
  :default (settei:per-environment :development t :otherwise nil))

(settei:define-setting :server/backend settei:choice-setting
  "The HTTP server Clack runs."
  :options '(:woo :hunchentoot)
  :default :woo)

;;; The database

(settei:define-setting :database/driver settei:choice-setting
  "The database: SQLite, PostgreSQL or MySQL."
  :options '(:sqlite3 :postgres :mysql)
  :default :sqlite3)

(settei:define-setting :database/name settei:string-setting
  "The database's name: for SQLite, its file, relative to the directory the
server runs in unless absolute. In development, db/development.db; in tests,
an SQLite database in memory."
  :environment '("SHISO_DATABASE_NAME" "DATABASE_PATH")
  :required-in :production
  :default (settei:per-environment :development "db/development.db" :test ":memory:"))

(settei:define-setting :database/host settei:string-setting
  "The database server's host, for PostgreSQL and MySQL.")

(settei:define-setting :database/port settei:integer-setting
  "The database server's port, for PostgreSQL and MySQL."
  :minimum 1 :maximum 65535)

(settei:define-setting :database/user settei:string-setting
  "The user to connect to the database server as.")

(settei:define-setting :database/password settei:string-setting
  "The password to connect to the database server with."
  :secret t)

;;; Static files

(settei:define-setting :static/manifest settei:pathname-setting
  "The staticfiles.json manifest COLLECTSTATIC writes and CACHED-STATIC
reads. Without one, static/staticfiles.json in the directory the server runs
in.")
