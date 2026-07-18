(defpackage #:shiso/auth/controllers
  (:use #:cl)
  (:local-nicknames (#:ah #:almighty-html)
                    (#:utils #:shiso/utils)
                    (#:req #:lack/request)
                    (#:forms #:shiso/forms)
                    (#:auth-forms #:shiso/auth/forms)
                    (#:session #:shiso/auth/session)
                    (#:guards #:shiso/auth/guards))
  (:export
   #:login-view
   #:logout-view
   #:signup-view))

(in-package #:shiso/auth/controllers)

;;; ----------------------------------------------------------------------
;;; Helpers.

(defun query-param (name)
  (let ((qs (req:request-query-parameters shiso/requests:*request*)))
    (cdr (assoc name qs :test #'string=))))

(defun safe-next-url (raw)
  "Only honour 'next' values that are local paths. Prevents open-redirect."
  (cond
    ((null raw) nil)
    ((and (stringp raw)
          (plusp (length raw))
          (char= (char raw 0) #\/)
          (not (and (> (length raw) 1) (char= (char raw 1) #\/))))
     raw)
    (t nil)))

(defun non-field-errors (form)
  (gethash :__all__ (forms:form-errors form)))

;;; ----------------------------------------------------------------------
;;; HTML rendering. Field markup comes from `forms:render-form' — the
;;; auth form definitions declare :widget :password, which the renderer
;;; honours — so these pages only own the shell and non-field errors.

(defun page (title body)
  (let ((html (ah:render-to-string
               (ah:</>
                (html
                  (ah:</>
                   (head
                     (ah:</> (meta :charset "utf-8"))
                     (ah:</> (meta :name "viewport"
                               :content "width=device-width, initial-scale=1"))
                     (ah:</> (title title))))
                  (ah:</>
                   (body
                     (ah:</> (main :class "auth-page" body)))))))))
    (utils:http-response html)))

(defun errors-block (errors)
  (when errors
    (ah:</> (ul :class "errors"
              (mapcar (lambda (e) (ah:</> (li e))) errors)))))

(defun render-login-page (form &key next)
  (let ((action (if next
                    (format nil "/login?next=~A" (quri:url-encode next :encoding :utf-8))
                    "/login"))
        (top-errors (errors-block (non-field-errors form)))
        (heading (ah:</> (h1 "Sign in"))))
    (page "Sign in"
          (ah:</>
           (div :class "auth-form"
             heading
             top-errors
             (forms:render-form form :action action :submit-label "Sign in"))))))

(defun render-signup-page (form)
  (let ((top-errors (errors-block (non-field-errors form)))
        (heading (ah:</> (h1 "Create account"))))
    (page "Create account"
          (ah:</>
           (div :class "auth-form"
             heading
             top-errors
             (forms:render-form form :action "/signup"
                                     :submit-label "Create account"))))))

;;; ----------------------------------------------------------------------
;;; Controllers.

(defun login-view ()
  (let* ((next (safe-next-url (query-param "next")))
         (is-post (utils:post-request-p)))
    (cond
      ((not is-post)
       (render-login-page (auth-forms:make-login-form) :next next))
      (t
       (let ((form (auth-forms:make-login-form :data (forms:request-form-data))))
         (cond
           ((forms:validate-form form)
            (session:login-user (auth-forms:login-form-user form))
            (utils:redirect-response (or next guards:*post-login-redirect*)))
           (t
            (render-login-page form :next next))))))))

(defun logout-view ()
  (when (utils:post-request-p)
    (session:logout-user))
  (utils:redirect-response guards:*post-login-redirect*))

(defun signup-view ()
  (let ((is-post (utils:post-request-p)))
    (cond
      ((not is-post)
       (render-signup-page (auth-forms:make-signup-form)))
      (t
       (let ((form (auth-forms:make-signup-form :data (forms:request-form-data))))
         (cond
           ((forms:validate-form form)
            (let* ((email (forms:cleaned-value form "email"))
                   (password (forms:cleaned-value form "password"))
                   (u (shiso/auth/user:make-user email password)))
              (session:login-user u)
              (utils:redirect-response guards:*post-login-redirect*)))
           (t
            (render-signup-page form))))))))
