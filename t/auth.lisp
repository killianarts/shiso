(defpackage #:shiso/t/auth
  (:use #:cl #:lisp-unit2)
  (:local-nicknames (#:pw #:shiso/auth/password)
                    (#:user #:shiso/auth/user)
                    (#:guards #:shiso/auth/guards)
                    (#:auth-forms #:shiso/auth/forms)
                    (#:form #:shiso/forms/form)))

(in-package #:shiso/t/auth)

;;; ----------------------------------------------------------------------
;;; Password hashing.

(define-test password-hash-roundtrip ()
  (let ((hash (pw:hash-password "correct horse battery staple")))
    (assert-true (stringp hash))
    (assert-true (pw:verify-password "correct horse battery staple" hash)
                 "verify-password should accept the right password")
    (assert-false (pw:verify-password "wrong" hash)
                  "verify-password should reject a wrong password")))

(define-test password-hash-is-not-plaintext ()
  (let ((plaintext "hunter2")
        (hash (pw:hash-password "hunter2")))
    (assert-false (search plaintext hash)
                  "Hashed password should not contain the plaintext")))

(define-test password-hashes-are-salted ()
  (let ((h1 (pw:hash-password "same-password"))
        (h2 (pw:hash-password "same-password")))
    (assert-false (string= h1 h2)
                  "Two hashes of the same password should differ (salt)")))

;;; ----------------------------------------------------------------------
;;; Guards — purely functional via `evaluate-guard'.

(defclass mock-user ()
  ((staffp :initarg :staffp :initform nil :accessor mock-user-staffp)
   (activep :initarg :activep :initform t :accessor mock-user-activep)))

(defmethod user:user-is-staff ((u mock-user)) (mock-user-staffp u))
(defmethod user:user-is-active ((u mock-user)) (mock-user-activep u))

(defun make-mock-user (&key staffp)
  (make-instance 'mock-user :staffp staffp))

(define-test guard-nil-allows-anyone ()
  (assert-eq :allow (guards:evaluate-guard nil nil))
  (assert-eq :allow (guards:evaluate-guard nil (make-mock-user))))

(define-test guard-login-allows-authenticated ()
  (assert-eq :allow
             (guards:evaluate-guard '(:require :login) (make-mock-user))))

(define-test guard-login-redirects-anonymous ()
  (let ((response (guards:evaluate-guard '(:require :login) nil)))
    (assert-eql 302 (first response)
                "Anonymous user should get a 302")
    (assert-true (search "/login"
                         (getf (second response) :location))
                 "Redirect should target /login")))

(define-test guard-staff-allows-staff ()
  (assert-eq :allow
             (guards:evaluate-guard '(:require :staff)
                                    (make-mock-user :staffp t))))

(define-test guard-staff-forbids-non-staff ()
  (let ((response (guards:evaluate-guard '(:require :staff)
                                         (make-mock-user :staffp nil))))
    (assert-eql 403 (first response)
                "Authenticated non-staff user should get 403")))

(define-test guard-staff-redirects-anonymous-to-login ()
  (let ((response (guards:evaluate-guard '(:require :staff) nil)))
    (assert-eql 302 (first response))
    (assert-true (search "/login"
                         (getf (second response) :location)))))

(define-test guard-anonymous-allows-when-no-user ()
  (assert-eq :allow
             (guards:evaluate-guard '(:require :anonymous) nil)))

(define-test guard-anonymous-redirects-logged-in ()
  (let ((response (guards:evaluate-guard '(:require :anonymous)
                                         (make-mock-user))))
    (assert-eql 302 (first response))))

(define-test guard-redirect-encodes-next-from-env ()
  (let* ((env '(:path-info "/admin/article/3" :query-string "page=2"))
         (response (guards:evaluate-guard '(:require :login) nil env))
         (location (getf (second response) :location)))
    (assert-true (search "next=" location)
                 "Redirect should carry a next= query parameter")
    (assert-true (search "%2Fadmin%2Farticle%2F3" location)
                 "next= should contain the URL-encoded request path")
    (assert-true (search "page%3D2" location)
                 "next= should URL-encode the query string")))

(define-test guard-predicate-runs-on-user ()
  (let ((predicate-symbol (gensym "PRED")))
    (setf (fdefinition predicate-symbol)
          (lambda (u) (and u (eq (slot-value u 'staffp) t))))
    (assert-eq :allow
               (guards:evaluate-guard `(:require (:predicate ,predicate-symbol))
                                      (make-mock-user :staffp t)))
    (let ((response (guards:evaluate-guard
                     `(:require (:predicate ,predicate-symbol))
                     (make-mock-user :staffp nil))))
      (assert-eql 403 (first response)))))

;;; ----------------------------------------------------------------------
;;; Forms — non-DB validation paths.

(defmacro with-stubbed-user-lookup (&body body)
  "Stub `user:find-user-by-email' to always return NIL for the duration
of BODY. Lets us exercise signup-form's `clean' method without a DB."
  (let ((saved (gensym "SAVED")))
    `(let ((,saved (fdefinition 'user:find-user-by-email)))
       (unwind-protect
            (progn
              (setf (fdefinition 'user:find-user-by-email)
                    (lambda (email) (declare (ignore email)) nil))
              ,@body)
         (setf (fdefinition 'user:find-user-by-email) ,saved)))))

(define-test signup-form-rejects-mismatched-passwords ()
  (with-stubbed-user-lookup
    (let ((form (auth-forms:make-signup-form
                 :data '(("email" . "alice@example.com")
                         ("password" . "longenough1")
                         ("password-confirm" . "different1")))))
      (assert-false (form:validate-form form)
                    "Mismatched passwords should fail validation")
      (assert-true (gethash :__all__ (form:form-errors form))
                   "Mismatched passwords should produce a non-field error"))))

(defun form-field-error (form field-name-string)
  "Look up errors for a field by its name string. Forms store errors
keyed by the field's :name symbol, which lives in the form-defining
package (here: shiso/auth/forms); test code is in a different package,
so we resolve the symbol explicitly."
  (let ((sym (find-symbol (string-upcase field-name-string)
                          :shiso/auth/forms)))
    (and sym (gethash sym (form:form-errors form)))))

(define-test signup-form-rejects-short-password ()
  (with-stubbed-user-lookup
    (let ((form (auth-forms:make-signup-form
                 :data '(("email" . "alice@example.com")
                         ("password" . "short")
                         ("password-confirm" . "short")))))
      (assert-false (form:validate-form form)
                    "Short password should fail validation")
      (assert-true (form-field-error form "password")
                   "Short password should produce a 'password' error"))))

(define-test signup-form-rejects-invalid-email ()
  (with-stubbed-user-lookup
    (let ((form (auth-forms:make-signup-form
                 :data '(("email" . "not-an-email")
                         ("password" . "longenough1")
                         ("password-confirm" . "longenough1")))))
      (assert-false (form:validate-form form))
      (assert-true (form-field-error form "email")))))

;;; ----------------------------------------------------------------------
;;; Routing — auth module is registered and admin module carries the
;;; staff guard.

(define-test auth-module-is-registered ()
  (let ((module (shiso:get-module :shiso-auth)))
    (assert-true (typep module 'shiso:module)
                 "shiso-auth should be registered as a module")))

(define-test admin-module-has-staff-guard ()
  (let* ((module (shiso:get-module :shiso-admin))
         (guard (shiso/modules:module-guard module)))
    (assert-true guard "shiso-admin should carry a guard spec")
    (assert-equal :staff (getf guard :require)
                  "admin guard should require :staff")))
