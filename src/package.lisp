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

  ;; (:import-from #:shiso/scaffold
  ;;               #:make-module)

  (:import-from #:shiso/server
                #:start
                #:stop)

  (:import-from #:shiso/static
                #:collectstatic)

  (:import-from #:shiso/admin
                #:define-admin)

  (:import-from #:shiso/utils
                #:http-response
                #:url
                #:current-path
                #:static
                #:absolute-url)
  (:import-from #:shiso/models
                ;; Structs
                #:slot-metadata
                #:make-slot-metadata
                #:slot-metadata-name
                #:slot-metadata-col-type
                #:slot-metadata-verbose-name
                #:slot-metadata-help-text
                #:slot-metadata-validators
                #:slot-metadata-choices
                #:slot-metadata-blankp
                #:slot-metadata-editablep
                #:slot-metadata-widget
                #:model-metadata
                #:make-model-metadata
                #:model-metadata-class
                #:model-metadata-fields
                ;; Registry
                #:*model-registry*
                #:register-model
                ;; Introspection
                #:model-fields
                #:model-field
                #:model-class
                #:all-models
                ;; Field readers
                #:field-name
                #:field-col-type
                #:field-verbose-name
                #:field-help-text
                #:field-validators
                #:field-choices
                #:field-blankp
                #:field-editablep
                #:field-widget
                ;; Field types
                #:*field-types*
                #:define-field-type
                #:expand-field-type
                ;; Macro
                #:define-model)

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
   #:collectstatic

   ;; Admin
   #:define-admin

   ;; Models
   ;; Structs
   #:slot-metadata
   #:make-slot-metadata
   #:slot-metadata-name
   #:slot-metadata-col-type
   #:slot-metadata-verbose-name
   #:slot-metadata-help-text
   #:slot-metadata-validators
   #:slot-metadata-choices
   #:slot-metadata-blankp
   #:slot-metadata-editablep
   #:slot-metadata-widget
   #:model-metadata
   #:make-model-metadata
   #:model-metadata-class
   #:model-metadata-fields
   ;; Registry
   #:*model-registry*
   #:register-model
   ;; Introspection
   #:model-fields
   #:model-field
   #:model-class
   #:all-models
   ;; Field readers
   #:field-name
   #:field-col-type
   #:field-verbose-name
   #:field-help-text
   #:field-validators
   #:field-choices
   #:field-blankp
   #:field-editablep
   #:field-widget
   ;; Field types
   #:*field-types*
   #:define-field-type
   #:expand-field-type
   ;; Macro
   #:define-model))
