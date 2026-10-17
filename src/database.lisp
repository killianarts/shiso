(defpackage #:shiso/database
  (:use #:cl)
  (:local-nicknames (#:settei #:almighty-settei)
                    (#:utils #:shiso/utils)
                    (#:models #:shiso/models))
  (:export #:setup-database #:connect-database #:*after-database*))

(in-package #:shiso/database)

;;;; The database: Shiso connects to it from the :database/ settings and
;;;; makes the tables Shiso and the application's models need, when the server
;;;; starts. An application has nothing to do, unless it gives a function of
;;;; its own to run after (DEFINE-APPLICATION's :after-database).

(defvar *after-database* nil
  "A function the application gives, called with no arguments once the
database is connected and its tables made: to seed data, say.")

(defvar *connected-to* nil
  "The settings the current connection was made with, so that connecting
again with the same ones does nothing.")

(defun connection-arguments ()
  "MITO:CONNECT-TOPLEVEL's arguments, from the :database/ settings."
  (let ((driver (settei:setting :database/driver)))
    (append (list driver :database-name (settei:setting :database/name))
            (unless (eq driver :sqlite3)
              (loop for (key name) in '((:host :database/host) (:port :database/port)
                                        (:username :database/user)
                                        (:password :database/password))
                    for value = (settei:setting name)
                    when value
                      append (list key value))))))

(defun connect-database ()
  "Connect to the database the settings name, unless already connected to
it. For SQLite, the file's directory is made first."
  (let ((arguments (connection-arguments)))
    (unless (and mito:*connection* (equal arguments *connected-to*))
      (when (eq (first arguments) :sqlite3)
        (ensure-directories-exist (getf (rest arguments) :database-name)))
      (apply #'mito:connect-toplevel arguments)
      (setf *connected-to* arguments))
    mito:*connection*))

(defun setup-database ()
  "Connect to the database, and make the tables that aren't there: the
session table, and each model's. A table that is there isn't changed, so a
changed model needs a migration. Then call the application's
*AFTER-DATABASE*."
  (connect-database)
  (utils:ensure-session-table :table-name "shiso_session")
  (dolist (name (models:all-models))
    (mito:ensure-table-exists (models:model-class name)))
  (when *after-database*
    (funcall *after-database*))
  mito:*connection*)
