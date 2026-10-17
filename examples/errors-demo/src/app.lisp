(defpackage #:errors-demo
  (:use #:cl)
  (:export #:application
           #:start
           #:stop
           #:restart-server))

(in-package #:errors-demo)

(shiso:define-application application ()
  (:modules ("" demo)))

(defun start (&key (debugp nil debugp-p))
  "Serve the demo on http://localhost:5050. DEBUGP NIL, T or :REPL overrides
:server/debugp (on by default in the REPL's development environment)."
  (if debugp-p
      (shiso:start application :debugp debugp)
      (shiso:start application)))

(defun stop ()
  (shiso:stop))

(defun restart-server (&key (debugp nil debugp-p))
  "Stop the server if it runs, and start it again, with DEBUGP if given."
  (when shiso/server:*server-connection*
    (stop))
  (if debugp-p (start :debugp debugp) (start)))
