(defpackage #:shiso/auth/controllers
  (:use #:cl)
  (:local-nicknames (#:ah #:almighty-html)
                    (#:utils #:shiso/utils)
                    (#:req #:lack/request)
                    (#:form #:shiso/forms/form)
                    (#:fields #:shiso/forms/fields)
                    (#:auth-forms #:shiso/auth/forms)
                    (#:session #:shiso/auth/session)
                    (#:guards #:shiso/auth/guards)
                    (#:csrf #:lack/middleware/csrf))
  (:export
   #:login-view
   #:logout-view
   #:signup-view))

(in-package #:shiso/auth/controllers)

;;; ----------------------------------------------------------------------
;;; Helpers.

(defun current-session-hash ()
  (session:session-from-env (req:request-env shiso/requests:*request*)))

(defun csrf-token-value ()
  "Get (or lazily mint) the CSRF token for the current session."
  (let ((s (current-session-hash)))
    (when s (csrf:csrf-token s))))

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

(defun gethash-or-empty (key data)
  (or (cdr (assoc key data :test #'string-equal)) ""))

(defun field-error (form field-name)
  (gethash field-name (form:form-errors form)))

(defun non-field-errors (form)
  (gethash :__all__ (form:form-errors form)))

;;; ----------------------------------------------------------------------
;;; HTML rendering — auth pages are simple enough to hand-render rather
;;; than route through `shiso/forms/rendering' (which lacks a password
;;; input renderer).

(defun page (title body)
  (let ((html (ah:render-to-string
               (ah:</>
                (html
                  (ah:</>
                   (head
                     (ah:</> (meta :charset "utf-8"))
                     (ah:</> (title title))))
                  (ah:</>
                   (body
                     (ah:</> (main :class "auth-page" body)))))))))
    (utils:http-response html)))

(defun errors-block (errors)
  (when errors
    (ah:</> (ul :class "errors"
              (mapcar (lambda (e) (ah:</> (li e))) errors)))))

(defun csrf-hidden ()
  (let ((token (csrf-token-value)))
    (when token
      (ah:</> (input :type "hidden" :name "_csrf_token" :value token)))))

(defun render-login-page (form &key next)
  (let* ((data (form:form-data form))
         (email (gethash-or-empty "email" data))
         (action (if next
                     (format nil "/login?next=~A" (quri:url-encode next :encoding :utf-8))
                     "/login")))
    (page "Sign in"
          (ah:</>
           (form :method "POST" :action action
             (ah:</> (h1 "Sign in"))
             (errors-block (non-field-errors form))
             (ah:</>
              (div :class "field"
                (ah:</> (label :for "email" "Email"))
                (ah:</> (input :type "email" :name "email" :id "email"
                          :value email :required t :autofocus t))
                (errors-block (field-error form 'email))))
             (ah:</>
              (div :class "field"
                (ah:</> (label :for "password" "Password"))
                (ah:</> (input :type "password" :name "password" :id "password"
                          :required t))
                (errors-block (field-error form 'password))))
             (csrf-hidden)
             (ah:</> (button :type "submit" "Sign in")))))))

(defun render-signup-page (form)
  (let* ((data (form:form-data form))
         (email (gethash-or-empty "email" data)))
    (page "Create account"
          (ah:</>
           (form :method "POST" :action "/signup"
             (ah:</> (h1 "Create account"))
             (errors-block (non-field-errors form))
             (ah:</>
              (div :class "field"
                (ah:</> (label :for "email" "Email"))
                (ah:</> (input :type "email" :name "email" :id "email"
                          :value email :required t :autofocus t))
                (errors-block (field-error form 'email))))
             (ah:</>
              (div :class "field"
                (ah:</> (label :for "password" "Password"))
                (ah:</> (input :type "password" :name "password" :id "password"
                          :required t :minlength "8"))
                (errors-block (field-error form 'password))))
             (ah:</>
              (div :class "field"
                (ah:</> (label :for "password-confirm" "Confirm password"))
                (ah:</> (input :type "password" :name "password-confirm"
                          :id "password-confirm" :required t))
                (errors-block (field-error form 'password-confirm))))
             (csrf-hidden)
             (ah:</> (button :type "submit" "Create account")))))))

;;; ----------------------------------------------------------------------
;;; Controllers.

(defun login-view ()
  (let* ((next (safe-next-url (query-param "next")))
         (is-post (utils:post-request-p)))
    (cond
      ((not is-post)
       (render-login-page (auth-forms:make-login-form) :next next))
      (t
       (let* ((data (utils:parse-body-params))
              ;; parse-body-params returns keyword keys; the form's field
              ;; lookup is by symbol name (string-equal), so re-key as strings.
              (string-data (mapcar (lambda (pair)
                                     (cons (string-downcase (symbol-name (car pair)))
                                           (cdr pair)))
                                   data))
              (form (auth-forms:make-login-form :data string-data)))
         (cond
           ((form:validate-form form)
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
       (let* ((data (utils:parse-body-params))
              (string-data (mapcar (lambda (pair)
                                     (cons (string-downcase (symbol-name (car pair)))
                                           (cdr pair)))
                                   data))
              (form (auth-forms:make-signup-form :data string-data)))
         (cond
           ((form:validate-form form)
            (let* ((cleaned (form:form-cleaned-data form))
                   (email (gethash 'email cleaned))
                   (password (gethash 'password cleaned))
                   (u (shiso/auth/user:make-user email password)))
              (session:login-user u)
              (utils:redirect-response guards:*post-login-redirect*)))
           (t
            (render-signup-page form))))))))
