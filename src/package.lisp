(defpackage #:shiso
  (:use #:cl)

  (:import-from #:shiso/requests
                #:*request*)

  (:import-from #:shiso/modules
                #:module
                #:module-routes
                #:module-prefix
                #:module-static-root
                #:*module-registry*
                #:register-module
                #:get-module)

  (:import-from #:shiso/routing
                #:routes
                #:routes-mapper
                #:*routes*
                #:*global-routes-namespace*
                #:define-route
                #:define-routes
                #:define-module
                #:define-application)

  (:import-from #:shiso/scaffold
                #:make-module)

  (:import-from #:shiso/server
                #:start
                #:stop)

  (:import-from #:shiso/static
                #:collectstatic)

  (:import-from #:shiso/utils
                #:http-response
                #:url
                #:current-path
                #:static
                #:absolute-url)

  (:export

   #:*request*

   #:routes
   #:routes-mapper
   #:module
   #:module-routes
   #:module-prefix
   #:module-static-root
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
   #:static
   #:absolute-url
   #:collectstatic))
