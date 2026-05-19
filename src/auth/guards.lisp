(defpackage #:shiso/auth/guards
  (:use #:cl)
  (:local-nicknames (#:modules #:shiso/modules)
                    (#:user #:shiso/auth/user)
                    (#:session #:shiso/auth/session)
                    (#:req #:lack/request)
                    (#:res #:lack/response))
  (:export
   ;; Spec evaluation
   #:check-guard
   #:check-guard-from-env
   #:evaluate-guard
   ;; Per-controller / functional guards
   #:require-login
   #:require-staff
   #:login-required
   #:staff-required
   ;; Tunables
   #:*login-url*
   #:*post-login-redirect*))

(in-package #:shiso/auth/guards)

(defparameter *login-url* "/login"
  "URL the guard redirects anonymous visitors to.")

(defparameter *post-login-redirect* "/"
  "URL the guard redirects already-logged-in visitors away from when they
hit an :anonymous-only page.")

;;; ----------------------------------------------------------------------
;;; Response builders.

(defun finalize (status headers body)
  (res:finalize-response (res:make-response status headers (list body))))

(defun url-encode (s)
  (quri:url-encode (or s "") :encoding :utf-8))

(defun redirect-to-login (env)
  (let* ((path (and env (or (getf env :path-info) "/")))
         (qs (and env (getf env :query-string)))
         (full (cond ((null path) nil)
                     ((and qs (plusp (length qs)))
                      (concatenate 'string path "?" qs))
                     (t path)))
         (location (if full
                       (format nil "~A?next=~A" *login-url* (url-encode full))
                       *login-url*)))
    (finalize 302 (list :location location) "")))

(defun forbidden-response ()
  (finalize 403
            (list :content-type "text/html; charset=utf-8")
            "<h1>403 Forbidden</h1>"))

(defun redirect-post-login ()
  (finalize 302 (list :location *post-login-redirect*) ""))

;;; ----------------------------------------------------------------------
;;; Spec evaluation.
;;;
;;; A guard SPEC is one of:
;;;   NIL                          — no guard (always allows)
;;;   (:require :login)            — must be authenticated
;;;   (:require :staff)            — authenticated + is-staff
;;;   (:require :anonymous)        — must NOT be authenticated
;;;   (:require (:predicate FN))   — FN is a function symbol; called
;;;                                  on the user (or NIL). Must return
;;;                                  truthy for the request to proceed.

(defun evaluate-guard (spec user &optional env)
  "Decide what a guard SPEC permits given USER (or NIL). Returns either
:ALLOW or a finalized Clack response. ENV is used only for building the
login redirect's `next' parameter; pass NIL if you don't have one."
  (let ((require (and spec (getf spec :require))))
    (cond
      ((null require)
       :allow)
      ((eq require :login)
       (if user :allow (redirect-to-login env)))
      ((eq require :staff)
       (cond ((null user) (redirect-to-login env))
             ((user:user-is-staff user) :allow)
             (t (forbidden-response))))
      ((eq require :anonymous)
       (if user (redirect-post-login) :allow))
      ((and (listp require) (eq (first require) :predicate))
       (if (funcall (second require) user) :allow (forbidden-response)))
      (t
       (error "Unknown guard spec :require ~S" require)))))

(defun check-guard-from-env (spec env)
  "Evaluate SPEC against the user implied by ENV."
  (evaluate-guard spec (session:current-user-from-env env) env))

(defun check-guard (spec)
  "Like `check-guard-from-env' but reads ENV from `shiso/requests:*request*'.
Use inside controllers."
  (check-guard-from-env spec (req:request-env shiso/requests:*request*)))

;;; ----------------------------------------------------------------------
;;; Module-level guard: an :around method on the module's call gates the
;;; dispatcher in `shiso/requests'.

(defmethod lack/component:call :around ((this modules:module) env)
  (let ((guard (modules:module-guard this)))
    (if guard
        (let ((result (check-guard-from-env guard env)))
          (if (eq result :allow)
              (call-next-method)
              ;; Guard rejection is a real response (e.g. redirect to
              ;; /login); flag it as handled so the mount wrapper does
              ;; not fall through to the next mounted module.
              (values result t)))
        (call-next-method))))

;;; ----------------------------------------------------------------------
;;; Per-controller decorators.

(defun require-login (controller)
  "Wrap CONTROLLER so it short-circuits with a login redirect when the
request is anonymous."
  (lambda (&rest args)
    (let ((r (check-guard '(:require :login))))
      (if (eq r :allow) (apply controller args) r))))

(defun require-staff (controller)
  "Like `require-login' but also requires is-staff."
  (lambda (&rest args)
    (let ((r (check-guard '(:require :staff))))
      (if (eq r :allow) (apply controller args) r))))

(defmacro login-required (&body body)
  "Evaluate BODY only if the request is authenticated. Otherwise the form
returns a login redirect. Use as the controller's tail expression."
  (let ((g (gensym "GUARD")))
    `(let ((,g (check-guard '(:require :login))))
       (if (eq ,g :allow) (progn ,@body) ,g))))

(defmacro staff-required (&body body)
  "Evaluate BODY only if the request is an authenticated staff user.
Use as the controller's tail expression."
  (let ((g (gensym "GUARD")))
    `(let ((,g (check-guard '(:require :staff))))
       (if (eq ,g :allow) (progn ,@body) ,g))))
