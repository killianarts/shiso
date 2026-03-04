(defpackage #:shiso/requests
  (:use #:cl)
  (:local-nicknames (#:routing #:shiso/routing)
                    (#:modules #:shiso/modules)
                    (#:req #:lack/request)
                    (#:res #:lack/response))
  (:export
   #:*request*))

(in-package #:shiso/requests)

(defparameter *request* nil)

(defmethod lack/component:call ((this modules:module) env)
  (let ((*request* (handler-case (req:make-request env)
                     (error (e)
                       (warn "~A" e)
                       (return-from lack/component:call '(400 () ("Bad Request")))))))
    (multiple-value-bind (response foundp)
        (myway:dispatch (routing:routes-mapper (modules:module-routes this))
                        (req:request-path-info *request*)
                        :method (req:request-method *request*))
      (if foundp
          (if (functionp response)
              response
              (destructuring-bind (status headers body) response
                (res:finalize-response
                 (res:make-response status headers body))))
          (res:finalize-response
           (res:make-response 404 '(:content-type "text/html") '("Not found")))))))
