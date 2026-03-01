(defpackage #:shiso/server
  (:use #:cl)
  (:export
   #:*server-connection*
   #:start
   #:stop))

(in-package #:shiso/server)

(defparameter *server-connection* nil)

(defmacro start (app &rest args &key (host "127.0.0.1") (port 5000) (debugp t))
  (declare (ignore host port debugp))
  (let ((app-sym (shiso/routing:to-symbol-form app)))
    `(%start ,app-sym ,@args)))

(defun %start (app-symbol &key (host "127.0.0.1") (port 5000) (debugp t))
  (when *server-connection*
    (restart-case (error "Server is already running.")
      (restart-server ()
        :report "Restart the server"
        (stop))))
  (setf *server-connection*
        (clack:clackup (lambda (env) (funcall (symbol-value app-symbol) env))
                       :server :woo :address host :port port :debug debugp)))

(defun stop ()
  (prog1
      (clack:stop *server-connection*)
    (setf *server-connection* nil)))
