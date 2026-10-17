(defpackage #:<% @var application-name %>/main
  (:use #:cl)
  (:export #:start-server
           #:stop-server
           #:main)
  (:local-nicknames (#:routes #:<% @var application-name %>/routes)))

(in-package #:<% @var application-name %>/main)

(defun start-server ()
  "Start the server. Shiso loads the settings (src/settings.lisp, the
environment, and .env in development), connects to the database and makes
its tables, and serves on :server/host and :server/port."
  (shiso:load-localisations
   :root (asdf:system-relative-pathname :<% @var application-name %> "locale/"))
  (shiso:start routes:application))

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
a recognized subcommand (e.g. createsuperuser, settings) runs and exits; a
bare invocation starts the server."
  (shiso:run-cli (or argv (uiop:command-line-arguments))
                 :program "<% @var application-name %>"
                 :version "0.1"
                 :serve #'run-server))
