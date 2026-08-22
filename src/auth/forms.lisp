(defpackage #:shiso/auth/forms
  (:use #:cl)
  (:local-nicknames (#:fields #:shiso/forms/fields)
                    (#:form #:shiso/forms/form)
                    (#:val #:shiso/validators)
                    (#:user #:shiso/auth/user)
                    (#:session #:shiso/auth/session)
                    (#:i18n #:shiso/i18n))
  (:export
   #:login-form
   #:make-login-form
   #:login-form-user
   #:signup-form
   #:make-signup-form
   #:signup-form-user))

(in-package #:shiso/auth/forms)

;;; ----------------------------------------------------------------------
;;; Login form.

(defclass login-form (form:form)
  ((authenticated-user :accessor login-form-user :initform nil)))

(defun make-login-form (&key data)
  (make-instance 'login-form
                 :fields (list
                          (make-instance 'fields:email-field
                                         :name 'email
                                         :label "Email"
                                         :label-id "auth-email"
                                         :max-length 254
                                         :validators (list 'val:valid-email))
                          (make-instance 'fields:char-field
                                         :name 'password
                                         :label "Password"
                                         :label-id "auth-password"
                                         :widget :password
                                         :validators (list (list 'val:min-length 1))))
                 :data data))

(defmethod form:clean ((form login-form) cleaned-data)
  "Authenticate against the DB. On success, stash the user on the form."
  (let ((email (gethash 'email cleaned-data))
        (password (gethash 'password cleaned-data)))
    (when (and email password)
      (let ((u (session:authenticate email password)))
        (cond
          (u (setf (login-form-user form) u) nil)
          (t (list (i18n:translate "auth-invalid-credentials"
                                   :default "Invalid email or password."))))))))

;;; ----------------------------------------------------------------------
;;; Signup form.

(defclass signup-form (form:form)
  ((created-user :accessor signup-form-user :initform nil)))

(defun make-signup-form (&key data)
  (make-instance 'signup-form
                 :fields (list
                          (make-instance 'fields:email-field
                                         :name 'email
                                         :label "Email"
                                         :label-id "auth-email"
                                         :max-length 254
                                         :validators (list 'val:valid-email))
                          (make-instance 'fields:char-field
                                         :name 'password
                                         :label "Password"
                                         :label-id "auth-password"
                                         :widget :password
                                         :validators (list (list 'val:min-length 8)))
                          (make-instance 'fields:char-field
                                         :name 'password-confirm
                                         :label "Confirm password"
                                         :label-id "auth-password-confirm"
                                         :widget :password))
                 :data data))

(defmethod form:clean ((form signup-form) cleaned-data)
  "Cross-field checks: passwords match, email not already in use."
  (let ((errors nil)
        (p1 (gethash 'password cleaned-data))
        (p2 (gethash 'password-confirm cleaned-data))
        (email (gethash 'email cleaned-data)))
    (when (and p1 p2 (not (string= p1 p2)))
      (push (i18n:translate "auth-passwords-mismatch"
                            :default "Passwords do not match.")
            errors))
    (when (and email (user:find-user-by-email email))
      (push (i18n:translate "auth-email-taken"
                            :default "A user with that email already exists.")
            errors))
    (nreverse errors)))
