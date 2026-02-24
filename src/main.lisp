(uiop:define-package #:shiso
  (:use #:cl)
  (:nicknames #:shiso/main)
  (:export #:http-response
           #:*request*
           #:*response
           #:application
           #:application-routes
           #:start
           #:stop
           #:*routes*
           #:routes
           #:routes-mapper
           #:define-route
           #:current-path
           #:static))

(in-package #:shiso/main)


;; * Request/Response
;; 
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
  (let ((headers (append `(:content-type "text/html; charset=utf-8") headers)))
    `(,code ,headers (,body))))

;; * Routes

(defparameter *global-routes-namespace* :global)

(defclass routes ()
  ((mapper :initarg :mapper :reader routes-mapper :initform nil)))

(defparameter *routes* (make-instance 'routes :mapper (myway:make-mapper)))

(defun make-endpoint (fn param-keys)
  (if param-keys
      (lambda (params)
        (apply fn (mapcar (lambda (key) (getf params key)) param-keys)))
      (lambda (params)
        (declare (ignore params))
        (funcall fn))))

(defun get-name-and-namespace (name)
  (let ((pos (position #\: name)))
    (if pos
        (values (intern (string-upcase (subseq name (1+ pos))) :keyword)
                (intern (string-upcase (subseq name 0 pos)) :keyword))
        (values (intern (string-upcase name) :keyword)
                *global-routes-namespace*))))

(defun define-route (method routing-rule &key controller name (regexp nil))
  (let ((param-keys (myway.rule::rule-param-keys
                     (myway.rule::make-rule routing-rule))))
    (multiple-value-bind (name namespace)
        (get-name-and-namespace name)
      (myway:connect (routes-mapper (application-routes *app*))
                     routing-rule
                     (make-endpoint controller param-keys)
                     :method method
                     :name name
                     :namespace namespace
                     :regexp regexp))))

(defmacro define-routes (module &rest args)
  (let ((root (getf args :root ""))
        (routes (member-if #'listp args))
        (module-name (string-downcase (symbol-name module))))
    `(progn
       ,@(loop for (method path controller name) in routes
               for full-path = (concatenate 'string root path)
               for full-name = (concatenate 'string module-name ":" name)
               append (let ((methods (if (listp method) method (list method))))
                        (loop for m in methods
                              collect `(define-route ,m ,full-path
                                         :controller ,controller
                                         :name ,full-name)))))))

(defun url (name &rest params)
  "Return the url for a named route given the parameters. For use in templates."
  (myway:url-for (myway:find-route-by-name (routes-mapper *routes*) name) params))

;; * Server
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

;; * Template Utils
(defun current-path ()
  "Get the path to the current page."
  (lack/request:request-path-info *request*))

(defun static (path)
  (let ((scheme (lack.request:request-uri-scheme *request*))
        (server-name (lack.request:request-server-name *request*)))
    (format nil "~a://~a/~a" scheme server-name path)))

