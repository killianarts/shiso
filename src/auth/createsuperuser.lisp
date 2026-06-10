(defpackage #:shiso/auth/createsuperuser
  (:use #:cl)
  (:local-nicknames (#:user #:shiso/auth/user))
  (:export
   #:create-superuser
   #:superuser-error))
(in-package #:shiso/auth/createsuperuser)

;;;; Interactive creation/promotion of a staff (admin) user.
;;;;
;;;; This is the framework-level analog of Django's `createsuperuser'
;;;; management command. It only knows the user model — it assumes Mito is
;;;; already connected and the auth tables exist. Wiring it to a binary's
;;;; argv is the job of `shiso/management:run-cli'.

(define-condition superuser-error (error)
  ((message :initarg :message :reader superuser-error-message))
  (:report (lambda (c stream) (write-string (superuser-error-message c) stream)))
  (:documentation "A user-facing validation failure while creating a
superuser — bad/empty email, mismatched or too-short password. Callers
should report the message and exit non-zero rather than dump a backtrace."))

(defun fail (format-control &rest format-args)
  (error 'superuser-error
         :message (apply #'format nil format-control format-args)))

(defun prompt-line (prompt)
  "Print PROMPT and read one trimmed line from stdin. NIL on EOF."
  (format t "~A" prompt)
  (force-output)
  (let ((line (read-line *standard-input* nil nil)))
    (when line
      (string-trim '(#\Space #\Tab #\Return) line))))

(defun prompt-password (prompt)
  "Read a line from stdin with terminal echo disabled (best-effort via
`stty'; falls back to echoed input where stty is unavailable)."
  (format t "~A" prompt)
  (force-output)
  (let ((echo-off (ignore-errors
                    (uiop:run-program '("stty" "-echo")
                                      :input :interactive
                                      :ignore-error-status t)
                    t)))
    (unwind-protect
         (or (read-line *standard-input* nil nil) "")
      (when echo-off
        (ignore-errors
          (uiop:run-program '("stty" "echo")
                            :input :interactive
                            :ignore-error-status t)))
      (terpri))))

(defun prompt-for-password (min-length)
  "Prompt for a password twice (echo off) and confirm they match."
  (let ((p1 (prompt-password "Password: "))
        (p2 (prompt-password "Password (again): ")))
    (unless (string= p1 p2)
      (fail "Passwords do not match."))
    (when (< (length p1) min-length)
      (fail "Password must be at least ~D characters." min-length))
    p1))

(defun create-superuser (&key email password (min-password-length 8))
  "Create — or promote — a staff (admin) user, returning the user dao.

Mito must already be connected and the auth tables ensured (e.g. via the
app's database-setup thunk). EMAIL and PASSWORD are prompted for
interactively when not supplied; the password is read twice with terminal
echo disabled. An existing user with EMAIL is promoted to staff + active and
has its password reset. Signals `superuser-error' for validation failures so
the CLI layer can print a clean message and exit non-zero."
  (let ((email (or email (prompt-line "Email: "))))
    (when (or (null email) (zerop (length email)))
      (fail "Email is required."))
    (let ((password (or password (prompt-for-password min-password-length))))
      (when (< (length password) min-password-length)
        (fail "Password must be at least ~D characters." min-password-length))
      (let ((existing (user:find-user-by-email email)))
        (cond
          (existing
           (user:set-password existing password)
           (setf (user:user-is-staff existing) t
                 (user:user-is-active existing) t)
           (mito:save-dao existing)
           (format t "Updated existing user ~A (staff, active, password reset).~%" email)
           existing)
          (t
           (let ((u (user:make-user email password :is-staff t)))
             (format t "Created superuser ~A.~%" email)
             u)))))))
