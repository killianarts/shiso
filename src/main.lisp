(uiop:define-package #:shiso
  (:use #:cl)
  (:nicknames #:shiso/main)
  (:export #:*routes*
           #:route
           #:http-response
           #:*request*
           #:*response
           #:application
<<<<<<< HEAD
<<<<<<< HEAD
=======
>>>>>>> 330b7e6 (Removed :content-length, added exports.)
           #:application-routes
           #:start
           #:stop
           #:routes
           #:routes-mapper))
<<<<<<< HEAD
=======
           #:application-routes))
>>>>>>> 0731194 (Initial commit)
=======
>>>>>>> 330b7e6 (Removed :content-length, added exports.)

(in-package #:shiso/main)

(defclass routes ()
  ((mapper :initarg :mapper :reader routes-mapper :initform nil)))
<<<<<<< HEAD
<<<<<<< HEAD

=======
>>>>>>> 0731194 (Initial commit)
=======

>>>>>>> 330b7e6 (Removed :content-length, added exports.)
(defparameter *routes* (make-instance 'routes :mapper (myway:make-mapper)))

;; An instance of this class will be sent to clack:clackup or first lack:builder
;; and then clack:clackup to start the server.

(defclass application (lack/component::lack-component)
  ((routes :initarg :routes :accessor application-routes)))

(defparameter *app* (make-instance 'application :routes *routes*))

(defparameter *request* nil)
(defparameter *response* nil)

(defmethod lack/component:call ((this application) env)
  (let ((*request* (handler-case (lack/request:make-request env)
                     (error (e)
                       (warn "~A" e)
                       (return-from lack/component:call '(400 () ("Bad Request")))))))
    (multiple-value-bind (response foundp)
        (myway:dispatch (routes-mapper (slot-value this 'routes))
                        (lack/request:request-path-info *request*)
                        :method (lack/request:request-method *request*))
      (if foundp
          (if (functionp response)
              response
              (destructuring-bind (status headers body) response
                (lack/response:finalize-response (lack/response:make-response status headers body))))
          (lack/response:finalize-response (lack/response:make-response 404 '(:content-type "text/html") '("Not found")))))))

(defun http-response (body &key (code 200) (headers nil))
<<<<<<< HEAD
<<<<<<< HEAD
  (let ((headers (append `(:content-type "text/html; charset=utf-8")
=======
  (let ((headers (append `(:content-type "text/html; charset=utf-8"
                           :content-length ,(length body))
>>>>>>> 0731194 (Initial commit)
=======
  (let ((headers (append `(:content-type "text/html; charset=utf-8")
>>>>>>> 330b7e6 (Removed :content-length, added exports.)
                         headers)))
    `(,code ,headers (,body))))


(defun make-endpoint (fn)
  (lambda (params)
<<<<<<< HEAD
<<<<<<< HEAD
    (funcall fn params)))
=======
    (funcall (symbol-function fn) params)))
>>>>>>> 0731194 (Initial commit)
=======
    (funcall fn params)))
>>>>>>> a0f2c65 (Initial commit)

(defun route (method routing-rule endpoint)
  (myway:connect (routes-mapper (application-routes *app*))
                 routing-rule
                 (make-endpoint endpoint)
                 :method method))
<<<<<<< HEAD
<<<<<<< HEAD
=======
>>>>>>> 330b7e6 (Removed :content-length, added exports.)

(defparameter *server-connection* nil)

(defun start (app &optional (port 5000))
  (when *server-connection*
    (restart-case (error "Server is already running.")
      (restart-server ()
        :report "Restart the server"
        (stop))))
  (setf *server-connection*
        (clack:clackup app :server :woo :port port)))

(defun stop ()
  (prog1
      (clack:stop *server-connection*)
    (setf *server-connection* nil)))
<<<<<<< HEAD
=======
>>>>>>> 0731194 (Initial commit)
=======
>>>>>>> 330b7e6 (Removed :content-length, added exports.)
