(defpackage #:shiso/server
  (:use #:cl)
  (:local-nicknames (#:session #:shiso/auth/session))
  (:export
   #:*server-connection*
   #:start
   #:stop
   #:wrap-app))

(in-package #:shiso/server)

(defparameter *server-connection* nil)

(defun wrap-app (inner-app)
  "Wrap INNER-APP with the standard shiso middleware stack: session
(DB-backed via Mito's connection) and CSRF protection. The session
middleware must precede CSRF so that the CSRF middleware can find the
session in env."
  (funcall lack/middleware/session:*lack-middleware-session*
           (funcall lack/middleware/csrf:*lack-middleware-csrf*
                    inner-app)
           :store (session:make-store)))

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
  (let ((wrapped (wrap-app (symbol-value app-symbol))))
    (setf *server-connection*
          (clack:clackup (lambda (env) (funcall wrapped env))
                         :server :woo :address host :port port :debug debugp))))

(defun stop ()
  (prog1
      (clack:stop *server-connection*)
    (setf *server-connection* nil)))
