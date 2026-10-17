(defpackage #:errors-demo/settings
  (:use #:cl))

(in-package #:errors-demo/settings)

;;;; The demo's settings: its own SQLite file next to it, and port 5050 so it
;;;; can run beside another app on 5000. Debug mode follows SHISO_ENV, which
;;;; is development in the REPL, so the debug pages are on by default.

(shiso:configure
  (:server :port 5050)
  (:database :name (lambda (configuration)
                     (declare (ignore configuration))
                     (namestring (asdf:system-relative-pathname :errors-demo "db/demo.db")))))
