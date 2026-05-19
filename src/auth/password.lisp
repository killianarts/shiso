(defpackage #:shiso/auth/password
  (:use #:cl)
  (:export
   #:hash-password
   #:verify-password))

(in-package #:shiso/auth/password)

(defun hash-password (plaintext)
  "Hash a plaintext password. Returns a self-describing hash string
that encodes algorithm, salt, and parameters."
  (check-type plaintext string)
  (cl-pass:hash plaintext))

(defun verify-password (plaintext hash)
  "Return T if PLAINTEXT matches HASH (a string from `hash-password'),
NIL otherwise. Safe against timing attacks (cl-pass uses a constant-time
comparison internally)."
  (and (stringp plaintext)
       (stringp hash)
       (cl-pass:check-password plaintext hash)))
