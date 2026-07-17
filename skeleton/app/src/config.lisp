(defpackage #:<% @var application-name %>/config
  (:use #:cl)
  (:export #:*application-name*
           #:host
           #:port
           #:debugp
           #:database-path))

(in-package #:<% @var application-name %>/config)

(defparameter *application-name* "<% @var application-name %>")

(defun host (&optional (default "127.0.0.1"))
  (or (uiop:getenv "HOST") default))

(defun port (&optional (default 5000))
  (let ((raw (uiop:getenv "PORT")))
    (if raw
        (parse-integer raw :junk-allowed t)
        default)))

(defun debugp (&optional (default t))
  "True when DEBUGP is a truthy string (true/t/1/yes), false for
false/nil/0/no, otherwise DEFAULT."
  (let ((env (uiop:getenv "DEBUGP")))
    (cond ((null env) default)
          ((member env '("true" "t" "1" "yes") :test #'string-equal) t)
          ((member env '("false" "nil" "0" "no") :test #'string-equal) nil)
          (t default))))

(defun database-path ()
  "Path to the SQLite database file. Override with DATABASE_PATH;
otherwise an absolute, cwd-independent default under XDG data home:
$XDG_DATA_HOME/<% @var application-name %>/<% @var application-name %>.db, or
~/.local/share/<% @var application-name %>/<% @var application-name %>.db when XDG_DATA_HOME
is unset."
  (or (uiop:getenv "DATABASE_PATH")
      (let* ((xdg (uiop:getenv "XDG_DATA_HOME"))
             (base (if (and xdg (plusp (length xdg)))
                       (uiop:ensure-directory-pathname xdg)
                       (merge-pathnames ".local/share/"
                                        (user-homedir-pathname)))))
        (namestring
         (merge-pathnames (format nil "~a/~a.db"
                                  *application-name*
                                  *application-name*)
                          base)))))
