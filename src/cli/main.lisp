(defpackage #:shiso/cli/main
  (:use #:cl)
  (:local-nicknames (#:cmd     #:shiso/cli/commands)
                    (#:clingon #:clingon))
  (:export #:main))
(in-package #:shiso/cli/main)

(defun require-name (cmd subcommand-name)
  "Pull the first positional argument off CMD, or print an error +
usage to *error-output* and quit 1 if it's missing."
  (let ((args (clingon:command-arguments cmd)))
    (unless args
      (format *error-output* "~A: missing <name> argument~%" subcommand-name)
      (clingon:print-usage cmd *error-output*)
      (uiop:quit 1))
    (first args)))

(defun new-application/handler (cmd)
  (cmd:new-application (require-name cmd "new-application")))

(defun new-application/command ()
  (clingon:make-command
   :name        "new-application"
   :description "Scaffold a new Shiso application in ./<name>/"
   :usage       "<name>"
   :handler     #'new-application/handler))

(defun new-module/handler (cmd)
  (cmd:new-module (require-name cmd "new-module")))

(defun new-module/command ()
  (clingon:make-command
   :name        "new-module"
   :description "Scaffold a new module in ./src/modules/<name>/"
   :usage       "<name>"
   :handler     #'new-module/handler))

(defun top-level/handler (cmd)
  "Bare `shiso` with no subcommand: print usage and exit non-zero."
  (clingon:print-usage cmd *error-output*)
  (uiop:quit 1))

(defun top-level/command ()
  (clingon:make-command
   :name         "shiso"
   :description  "Shiso scaffolder — generates new applications and modules."
   :version      "0.1"
   :handler      #'top-level/handler
   :sub-commands (list (new-application/command)
                       (new-module/command))))

(defun main ()
  (clingon:run (top-level/command)))
