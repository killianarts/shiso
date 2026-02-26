(defpackage #:shiso/server
  (:use #:cl)
  (:export
   #:*server-connection*
   #:start
   #:stop))

(in-package #:shiso/server)

(defparameter *server-connection* nil)

(defun start (app &key (host "127.0.0.1") (port 5000) (debugp t))
  (when *server-connection*
    (restart-case (error "Server is already running.")
      (restart-server ()
        :report "Restart the server"
        (stop))))
  (setf *server-connection*
        (clack:clackup app :server :woo :address host :port port :debug debugp)))

(defun stop ()
  (prog1
      (clack:stop *server-connection*)
    (setf *server-connection* nil)))
