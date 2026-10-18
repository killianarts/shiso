(defpackage #:shiso/server
  (:use #:cl)
  (:local-nicknames (#:session #:shiso/auth/session)
                    (#:errors #:shiso/errors)
                    (#:timing #:shiso/timing)
                    (#:routing #:shiso/routing)
                    (#:i18n #:shiso/i18n)
                    (#:settei #:almighty-settei)
                    (#:database #:shiso/database))
  (:export
   #:*server-connection*
   #:start
   #:stop
   #:wrap-app
   #:*atomic-requests*))

(in-package #:shiso/server)

(defparameter *server-connection* nil)

(defvar *atomic-requests* t
  "When true, POST, PUT, PATCH and DELETE requests run in one database
transaction: committed when the request returns a response, rolled back when
an error leaves it (including SHISO:ABORT-WITH). Like Django's
ATOMIC_REQUESTS, for unsafe methods only.")

(defun wrap-atomic-requests (app)
  "Run unsafe-method requests in a transaction (*ATOMIC-REQUESTS*).
DBI:WITH-TRANSACTION commits only when its body returns normally; any
non-local exit rolls back. A transaction opened inside a controller becomes
a savepoint. Innermost, inside CSRF, so rejected requests open none."
  (lambda (env)
    (if (and *atomic-requests*
             mito:*connection*
             (member (getf env :request-method) '(:post :put :patch :delete)))
        (dbi:with-transaction mito:*connection*
          (funcall app env))
        (funcall app env))))

(defun render-error-page-in-request (env thunk)
  "Error pages render after the request has unwound, outside WRAP-LOCALE and
the module's binding of SHISO:*REQUEST*: bind both again, so that a page can
use TRANSLATE, SHISO:URL, CURRENT-PATH and the like."
  (let ((i18n:*locale* (or (ignore-errors (i18n:best-locale env))
                           i18n:*default-locale*))
        (shiso/requests:*request* (or shiso/requests:*request*
                                      (and env (ignore-errors
                                                (lack/request:make-request env))))))
    (funcall thunk)))

(setf errors:*render-around* 'render-error-page-in-request)

(defun csrf-failed (env)
  "The CSRF middleware's answer to a bad token: SHISO:BAD-REQUEST, so that
the error-page registry renders it."
  (declare (ignore env))
  (errors:abort-with 400 :message "CSRF token missing or invalid."))

(defun sessionless-path-p (path prefixes)
  "True when PATH is under /static/ or one of PREFIXES, the mounts
DEFINE-APPLICATION gave :sessions nil."
  (flet ((under (prefix)
           (let ((n (length prefix)))
             (and (>= (length path) n)
                  (string= path prefix :end1 n)
                  (or (= (length path) n)
                      (char= (char path n) #\/)
                      (char= (char prefix (1- n)) #\/))))))
    (and path
         (or (under "/static/")
             (some #'under prefixes)))))

(defun wrap-sessions (app sessionless-prefixes)
  "APP with locale, CSRF protection and the request transaction, inside the
session middleware, except under SESSIONLESS-PREFIXES and /static/. There a
request has no session, so no session row is read or written, and no CSRF
check: without a session, a forged request carries no login."
  (let ((with-session
          (funcall lack/middleware/session:*lack-middleware-session*
                   (i18n:wrap-locale
                    (funcall lack/middleware/csrf:*lack-middleware-csrf*
                             (wrap-atomic-requests app)
                             :block-app 'csrf-failed))
                   :store (session:make-store)
                   :keep-empty nil))
        (without-session (i18n:wrap-locale (wrap-atomic-requests app))))
    (lambda (env)
      (if (sessionless-path-p (getf env :path-info) sessionless-prefixes)
          (funcall without-session env)
          (funcall with-session env)))))

(defun wrap-app (inner-app &key (sessionless-prefixes
                                 (routing:application-sessionless-prefixes inner-app)))
  "Wrap INNER-APP with the standard shiso middleware stack, outermost first:
request timing (Server-Timing and the access log), HTTP errors (so it also
catches errors raised inside session/CSRF handling), session (DB-backed via
Mito's connection), locale, CSRF protection, then the request transaction.
The session middleware must precede CSRF so that the CSRF middleware can
find the session in env.

A new session is saved, and its cookie sent, only once something is stored
in it, such as a login or a CSRF token for a form. A page that stores
nothing sends no cookie, so a shared cache such as a CDN can keep it.
Requests under /static/ and SESSIONLESS-PREFIXES get no session at all."
  (timing:wrap-request-timing
   (errors:wrap-http-errors
    (wrap-sessions inner-app sessionless-prefixes))))

(defun ensure-woo-status-lines ()
  "Woo writes status lines from a table that lacks some statuses (428, 429,
431): a response with one fails as Woo writes it, and the client gets an
empty 500. Add a line for each status shiso has a reason phrase for."
  (let ((table (let ((symbol (and (find-package "WOO.RESPONSE")
                                  (find-symbol "*STATUS-LINE*" "WOO.RESPONSE"))))
                 (and symbol (boundp symbol) (symbol-value symbol)))))
    (when (hash-table-p table)
      (loop for status from 400 to 599
            for phrase = (errors:reason-phrase status)
            unless (or (gethash status table)
                       (member phrase '("Client Error" "Server Error") :test #'string=))
              do (setf (gethash status table)
                       (trivial-utf-8:string-to-utf-8-bytes
                        (format nil "HTTP/1.1 ~D ~A~C~C" status phrase #\Return #\Linefeed)))))))

(defmacro start (app &rest args &key host port debugp)
  "Start APP: load the settings unless they are, connect to the database and
make its tables, and serve on :server/host and :server/port. HOST, PORT and
DEBUGP, when given, set :server/host, :server/port and :server/debugp for
this run. DEBUGP :REPL is debug mode with :server/repl-debugger: unexpected
errors open the Lisp debugger in SLY or SLIME, with a RETRY-REQUEST restart."
  (declare (ignore host port debugp))
  (let ((app-sym (shiso/routing:to-symbol-form app)))
    `(%start ,app-sym ,@args)))

(defun %start (app-symbol &key (host nil host-p) (port nil port-p) (debugp nil debugp-p))
  (when *server-connection*
    (restart-case (error "Server is already running.")
      (restart-server ()
        :report "Restart the server"
        (stop))))
  (unless (settei:settings-loaded-p)
    (settei:load-settings))
  (when host-p (setf (settei:setting :server/host) host))
  (when port-p (setf (settei:setting :server/port) port))
  (when debugp-p
    ;; :REPL is debug mode with the Lisp debugger for unexpected errors.
    (setf (settei:setting :server/debugp) (and debugp t))
    (setf (settei:setting :server/repl-debugger) (eq debugp :repl)))
  (when (and (settei:setting :server/debugp)
             (settei:setting :server/repl-debugger)
             (not (errors:editor-connected-p)))
    (warn "shiso: :server/repl-debugger is on, but neither SLY nor SLIME is ~
connected; unexpected errors show the debug page until one is."))
  (database:setup-database)
  (i18n:ensure-localisations)
  (ensure-woo-status-lines)
  (let ((wrapped (wrap-app (symbol-value app-symbol))))
    (setf *server-connection*
          (clack:clackup (lambda (env) (funcall wrapped env))
                         :server (settei:setting :server/backend)
                         :address (settei:setting :server/host)
                         :port (settei:setting :server/port)
                         :debug (settei:setting :server/debugp)
                         ;; Lack's own backtrace printer would log each error
                         ;; a second time, with the whole env (cookies):
                         ;; WRAP-HTTP-ERRORS logs it.
                         :use-default-middlewares nil))))

(defun stop ()
  (prog1
      (clack:stop *server-connection*)
    (setf *server-connection* nil)))
