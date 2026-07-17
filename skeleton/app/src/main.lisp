(defpackage #:<% @var application-name %>/main
  (:use #:cl)
  (:export #:start-server
           #:stop-server
           #:main)
  (:local-nicknames (#:config #:<% @var application-name %>/config)
                    (#:routes #:<% @var application-name %>/routes)))

(in-package #:<% @var application-name %>/main)

(defun setup-database ()
  (let ((db (config:database-path)))
    (ensure-directories-exist (uiop:pathname-directory-pathname db))
    (mito:connect-toplevel :sqlite3 :database-name db)
    (shiso:ensure-session-table :table-name "shiso_session")
    (dolist (model-name (shiso/models:all-models))
      (mito:ensure-table-exists (shiso/models:model-class model-name)))))

(defun start-server (&key (host (config:host))
                          (port (config:port))
                          (debugp (config:debugp)))
  (setup-database)
  (shiso:start routes:application :host host :port port :debugp debugp))

(defun stop-server ()
  (shiso:stop))

(defun run-server ()
  (handler-case
      (progn
        (start-server)
        (loop (sleep 60)))
    (error (c)
      (format *error-output* "Aborting. ~a ~&" c)
      (force-output *error-output*)
      (uiop:quit 1))))

(defun main (&rest argv)
  "Binary entry point. Delegates to Shiso's management-command dispatcher:
a recognized subcommand (e.g. createsuperuser) runs and exits; a bare
invocation starts the server. Management commands that need the DB get
`setup-database' first."
  (shiso:run-cli (or argv (uiop:command-line-arguments))
                 :program "<% @var application-name %>"
                 :version "0.1"
                 :setup-db #'setup-database
                 :serve #'run-server))
