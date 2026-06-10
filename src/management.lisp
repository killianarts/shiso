(defpackage #:shiso/management
  (:use #:cl)
  (:local-nicknames (#:clingon #:clingon)
                    (#:auth    #:shiso/auth))
  (:export
   #:register-command
   #:run-cli
   #:*commands*))
(in-package #:shiso/management)

;;;; Management commands for application binaries.
;;;;
;;;; The standalone `shiso' scaffolder (shiso/cli) can't host commands like
;;;; `createsuperuser': those need the *application's* database configuration
;;;; and tables, which only exist inside the app's image. So — as with
;;;; Django's `manage.py' vs `django-admin' — the framework owns the commands
;;;; and their logic, but they're dispatched through the app binary, whose
;;;; `main' delegates to `run-cli'.
;;;;
;;;; `run-cli' builds a clingon command tree from the registry: each
;;;; registered command becomes a subcommand, and a bare invocation falls
;;;; through to the app's server entry point.

(defstruct (mcommand (:constructor %make-mcommand))
  "A registered management command. HANDLER is a function of one argument,
the clingon command object, from which positional arguments
(`clingon:command-arguments') and options (`clingon:getopt') are read."
  name description usage handler options (needs-db t))

(defvar *commands* (make-hash-table :test 'equal)
  "Registry of management commands, keyed by name string. Built-ins are
registered at load time; applications add their own via `register-command'.")

(defun register-command (name handler &key description usage options (needs-db t))
  "Register a management command named NAME (a string), dispatched by
`run-cli'. HANDLER receives the clingon command object. OPTIONS is a list of
clingon options for the subcommand. When NEEDS-DB is true (the default), the
`:setup-db' thunk passed to `run-cli' runs before HANDLER — so commands that
touch the database don't each have to connect. Re-registering a name replaces
the previous definition. Returns NAME."
  (check-type name string)
  (setf (gethash name *commands*)
        (%make-mcommand :name name
                        :handler handler
                        :description (or description "")
                        :usage (or usage "")
                        :options options
                        :needs-db needs-db))
  name)

(defun %clingon-subcommand (mcmd setup-db)
  "Build a clingon command from a registered MCOMMAND, wrapping its handler
so the SETUP-DB thunk runs first when the command needs the database."
  (let ((handler (mcommand-handler mcmd))
        (needs-db (mcommand-needs-db mcmd)))
    (clingon:make-command
     :name (mcommand-name mcmd)
     :description (mcommand-description mcmd)
     :usage (mcommand-usage mcmd)
     :options (mcommand-options mcmd)
     :handler (lambda (cmd)
                (when (and needs-db setup-db)
                  (funcall setup-db))
                (funcall handler cmd)))))

(defun %subcommands (setup-db)
  (let (acc)
    (maphash (lambda (name mcmd)
               (declare (ignore name))
               (push (%clingon-subcommand mcmd setup-db) acc))
             *commands*)
    acc))

(defun run-cli (args &key setup-db serve
                          (program "app") (version "0.1")
                          (description "Application server and management commands."))
  "Entry point for an application binary's `main'.

ARGS is the program's argument list, e.g. `(uiop:command-line-arguments)'.
A recognized management subcommand runs — after SETUP-DB if it needs the DB —
and the process exits (clingon handles exit codes, `--help' and `--version').
A bare or unrecognized invocation calls SERVE, the app's server entry point;
SERVE is expected to block, so it never returns.

SETUP-DB and SERVE are thunks supplied by the app, which is what knows its own
database configuration. Built-in commands (e.g. `createsuperuser') and any the
app registered via `register-command' are all available."
  (let ((top (clingon:make-command
              :name program
              :version version
              :description description
              ;; Bare invocation (no subcommand) → run the server.
              :handler (lambda (cmd)
                         (declare (ignore cmd))
                         (funcall serve))
              :sub-commands (%subcommands setup-db))))
    (clingon:run top args)))

;;; Built-in commands ---------------------------------------------------------

(register-command
 "createsuperuser"
 (lambda (cmd)
   (handler-case
       (auth:create-superuser :email (first (clingon:command-arguments cmd)))
     (auth:superuser-error (e)
       (format *error-output* "~&~A~%" e)
       (uiop:quit 1))))
 :description "Create or promote a staff (admin) user."
 :usage "[EMAIL]")
