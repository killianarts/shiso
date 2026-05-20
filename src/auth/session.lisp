(defpackage #:shiso/auth/session
  (:use #:cl)
  (:local-nicknames (#:user #:shiso/auth/user)
                    (#:store #:lack/middleware/session/store/dbi)
                    (#:req #:lack/request))
  (:export
   ;; Session model + table bootstrap
   #:session
   #:session-id
   #:session-data
   #:ensure-tables
   ;; Store factory
   #:make-store
   ;; Env-level accessors (rarely needed by callers)
   #:session-from-env
   #:session-options-from-env
   #:current-user-from-env
   ;; Public API for controllers
   #:current-user
   #:authenticatedp
   #:login-user
   #:logout-user
   #:authenticate))

(in-package #:shiso/auth/session)

;;; ----------------------------------------------------------------------
;;; Mito model — owns the DDL for the sessions table that Lack reads/writes.

(mito:deftable session ()
  ((id :col-type (:varchar 64)
       :primary-key t
       :initarg :id
       :accessor session-id)
   (session-data :col-type :text
                 :initarg :session-data
                 :accessor session-data))
  (:auto-pk nil)
  (:record-timestamps nil)
  (:table-name "shiso_session"))

(defun ensure-tables ()
  "Ensure the user and session tables exist. Call after Mito is connected."
  (mito:ensure-table-exists (shiso/models:model-class 'user))
  (mito:ensure-table-exists 'session))

;;; ----------------------------------------------------------------------
;;; Store factory.

(defun make-store ()
  "Build a Lack DBI session store that reuses Mito's current connection.
Mito must be connected (mito:connect-toplevel) before the store is used."
  (store:make-dbi-store
   :connector (lambda () mito.connection:*connection*)
   :disconnector nil
   :table-name "shiso_session"
   :data-column-name "session_data"
   :id-column-name "id"))

;;; ----------------------------------------------------------------------
;;; Env-level helpers — operate directly on the Clack env plist.
;;; The session middleware writes :lack.session (hash table) and
;;; :lack.session.options (plist) into env. We store our memoized
;;; current-user under :shiso.current-user.

(defun session-from-env (env)
  (getf env :lack.session))

(defun session-options-from-env (env)
  (getf env :lack.session.options))

(defun current-user-from-env (env)
  "Return the authenticated, active user attached to ENV, or NIL."
  (let* ((session (session-from-env env))
         (user-id (and session (gethash :user-id session)))
         (u (and user-id (user:find-user-by-id user-id))))
    (and u (user:user-is-active u) u)))

;;; ----------------------------------------------------------------------
;;; Per-request API.
;;;
;;; These functions operate on `shiso/requests:*request*`, which Lack
;;; binds for each request. Controllers may call them freely.

(defun request-env ()
  (req:request-env shiso/requests:*request*))

(defun current-user ()
  "Return the authenticated user for the current request, or NIL."
  (current-user-from-env (request-env)))

(defun authenticatedp ()
  (not (null (current-user))))

(defun login-user (user)
  "Mark USER as logged in. Rotates the session ID and stamps the user's
last-login-at. Subsequent calls to `current-user' in this request return
USER."
  (let* ((env (request-env))
         (session (session-from-env env)))
    (unless session
      (error "No session in env. Is lack-middleware-session installed?"))
    (setf (gethash :user-id session) (mito:object-id user))
    ;; Rotate session id on login to prevent fixation.
    (let ((opts-cell (cdr (member :lack.session.options env))))
      (when opts-cell
        (setf (getf (car opts-cell) :change-id) t)))
    (user:touch-last-login user)
    user))

(defun logout-user ()
  "Log out the current user: clear session contents and mark it expired
so the cookie is removed and the row deleted on response finalize."
  (let* ((env (request-env))
         (session (session-from-env env)))
    (when session (clrhash session))
    (let ((opts-cell (cdr (member :lack.session.options env))))
      (when opts-cell
        (setf (getf (car opts-cell) :expire) t))))
  (values))

(defun authenticate (email plaintext-password)
  "Return the user matching EMAIL + PLAINTEXT-PASSWORD, or NIL.
Does not log the user in — the caller decides whether to call `login-user'."
  (let ((u (user:find-user-by-email email)))
    (when (and u
               (user:user-is-active u)
               (user:check-password u plaintext-password))
      u)))
