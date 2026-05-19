(defpackage #:shiso/auth/user
  (:use #:cl)
  (:local-nicknames (#:pw #:shiso/auth/password))
  (:export
   #:user
   #:user-email
   #:user-password-hash
   #:user-is-active
   #:user-is-staff
   #:user-last-login-at
   #:make-user
   #:find-user-by-email
   #:find-user-by-id
   #:set-password
   #:check-password
   #:touch-last-login))

(in-package #:shiso/auth/user)

(mito:deftable user ()
  ((email :col-type (:varchar 254)
          :initarg :email
          :accessor user-email)
   (password-hash :col-type :text
                  :initarg :password-hash
                  :accessor user-password-hash)
   (is-active :col-type :boolean
              :initarg :is-active
              :accessor user-is-active
              :initform t)
   (is-staff :col-type :boolean
             :initarg :is-staff
             :accessor user-is-staff
             :initform nil)
   (last-login-at :col-type (or :timestamp :null)
                  :initarg :last-login-at
                  :accessor user-last-login-at
                  :initform nil))
  (:table-name "shiso_user")
  (:unique-keys email))

(defun make-user (email plaintext-password &key (is-active t) (is-staff nil))
  "Create and persist a new user. Hashes PLAINTEXT-PASSWORD before storing."
  (mito:create-dao 'user
                   :email email
                   :password-hash (pw:hash-password plaintext-password)
                   :is-active is-active
                   :is-staff is-staff))

(defun find-user-by-email (email)
  "Return the user with EMAIL, or NIL."
  (when (and email (stringp email) (plusp (length email)))
    (mito:find-dao 'user :email email)))

(defun find-user-by-id (id)
  "Return the user with primary key ID, or NIL."
  (when id
    (mito:find-dao 'user :id id)))

(defun set-password (user plaintext-password)
  "Update USER's password to PLAINTEXT-PASSWORD (hashing it) and persist."
  (setf (user-password-hash user) (pw:hash-password plaintext-password))
  (mito:save-dao user))

(defun check-password (user plaintext-password)
  "Return T if PLAINTEXT-PASSWORD matches USER's stored hash."
  (pw:verify-password plaintext-password (user-password-hash user)))

(defun touch-last-login (user)
  "Stamp USER's last-login-at to now and persist."
  (setf (user-last-login-at user) (local-time:now))
  (mito:save-dao user))
