(defpackage #:shiso
  (:use #:cl)

  (:import-from #:shiso/requests
                #:*request*)

  (:import-from #:shiso/routing
                #:routes
                #:routes-mapper
                #:module
                #:module-routes
                #:module-prefix
                #:*routes*
                #:*global-routes-namespace*
                #:define-route
                #:define-routes
                #:define-module
                #:define-application
                #:*module-registry*
                #:register-module
                #:get-module
)

  (:import-from #:shiso/scaffold
                #:make-module)

  (:import-from #:shiso/server
                #:start
                #:stop)

  (:import-from #:shiso/utils
                #:http-response
                #:url
                #:current-path
                #:static)

  (:export

   #:*request*

   #:routes
   #:routes-mapper
   #:module
   #:module-routes
   #:module-prefix
   #:*routes*
   #:*global-routes-namespace*
   #:define-route
   #:define-routes
   #:define-module
   #:define-application
   #:*module-registry*
   #:register-module
   #:get-module
   #:make-module

   #:start
   #:stop

   #:http-response
   #:url
   #:current-path
   #:static))
