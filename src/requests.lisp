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
  "Dispatch ENV through THIS module's mapper. Returns two values:
the Lack response, and a boolean indicating whether the module
handled the request. On a mapper miss the response is still a 404
(so direct callers get a usable response), but the second value is
NIL so the mount wrapper in `define-application' can fall through
to the next mounted module instead of returning this 404."
  (let ((*request* (handler-case (req:make-request env)
                     (error (e)
                       (warn "~A" e)
                       (return-from lack/component:call
                         (values '(400 () ("Bad Request")) t))))))
    (multiple-value-bind (response foundp)
        (myway:dispatch (routing:routes-mapper (modules:module-routes this))
                        (req:request-path-info *request*)
                        :method (req:request-method *request*))
      (if foundp
          (values
           (if (functionp response)
               response
               (destructuring-bind (status headers body) response
                 (res:finalize-response
                  (res:make-response status headers body))))
           t)
          (values
           (res:finalize-response
            (res:make-response 404 '(:content-type "text/html") '("Not found")))
           nil)))))
