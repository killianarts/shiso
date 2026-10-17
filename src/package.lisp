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

  (:import-from #:shiso/errors
                #:http-error
                #:http-error-status
                #:http-error-message
                #:http-error-headers
                #:http-error-cause
                #:http-error-type
                #:http-client-error
                #:http-server-error
                #:bad-request
                #:unauthorized
                #:forbidden
                #:not-found
                #:method-not-allowed
                #:allowed-methods
                #:internal-server-error
                #:abort-with
                #:condition-http-status
                #:define-error-page
                #:remove-error-page
                #:find-error-page
                #:*error-pages*
                #:default-error-page
                #:reason-phrase
                #:*fragment-p*
                #:*debug-404*
                #:*log-client-errors*
                #:*static-error-root*
                #:*prefer-static-5xx*
                #:retry-request
                #:show-debug-page
                #:show-error-page)

  (:import-from #:shiso/routing
                #:routes
                #:routes-mapper
                #:*routes*
                #:coerce-route-name
                #:define-route
                #:define-routes
                #:define-module
                #:define-application
                #:define-path-converter
                #:*auto-options*)

  (:import-from #:shiso/server
                #:start
                #:stop
                #:*atomic-requests*)

  (:import-from #:shiso/static
                #:collectstatic
                #:cached-static)

  (:import-from #:shiso/management
                #:run-cli
                #:register-command)

  (:import-from #:shiso/admin
                #:define-admin)

  (:import-from #:shiso/auth
                #:hash-password
                #:verify-password
                #:user
                #:user-email
                #:user-is-active
                #:user-is-staff
                #:make-user
                #:find-user-by-email
                #:find-user-by-id
                #:set-password
                #:check-password
                #:ensure-tables
                #:current-user
                #:authenticatedp
                #:login-user
                #:logout-user
                #:authenticate
                #:check-guard
                #:require-login
                #:require-staff
                #:login-required
                #:staff-required
                #:*login-url*
                #:*post-login-redirect*)

  (:import-from #:shiso/i18n
                #:translate
                #:with-locale
                #:current-locale
                #:load-localisations
                #:ensure-localisations
                #:available-locales
                #:message-id
                #:locale-html-lang
                #:*locale*
                #:*default-locale*
                #:*fallback-locale*)

  ;; Settings. The machinery is almighty-settei's; the API is Shiso's.
  (:import-from #:almighty-settei
                #:define-setting
                #:setting
                #:boolean-setting
                #:integer-setting
                #:string-setting
                #:pathname-setting
                #:choice-setting
                #:list-setting
                #:setting-name
                #:setting-documentation
                #:setting-source
                #:setting-unset
                #:find-setting
                #:list-settings
                #:configure
                #:per-environment
                #:current-environment
                #:development-p
                #:test-p
                #:production-p
                #:load-settings
                #:reload-settings
                #:settings-loaded-p
                #:with-settings
                #:on-setting-change
                #:remove-setting-listener
                #:print-settings
                #:settings-report
                #:redact
                #:coerce-value
                #:check-value
                #:reject
                #:render-value
                #:settings-invalid-problems
                #:problem-name
                #:problem-message
                #:setting-invalid-name
                #:setting-invalid-value
                #:setting-invalid-source
                #:setting-unknown-name)

  (:import-from #:shiso/settings
                #:settings-invalid
                #:setting-invalid
                #:setting-unknown
                #:settings-not-loaded
                #:secret-configured
                #:unknown-setting-warning)

  (:import-from #:shiso/database
                #:setup-database
                #:connect-database)

  (:import-from #:shiso/utils
                #:http-response
                #:url
                #:current-path
                #:static
                #:site-origin
                #:absolute-url
                #:post-request-p
                #:parse-body-params
                #:redirect-response
                #:current-session-hash
                #:csrf-token-value
                #:text-response
                #:json-response
                #:html-fragment-response
                #:ensure-session-table
                #:canonicalize-path
                #:canonicalize-redirect-url)
  ;; Forms — the headless core plus rendering. Field classes and the
  ;; field-* readers stay in shiso/forms (their names collide with the
  ;; model-metadata readers exported below).
  (:import-from #:shiso/forms
                #:form
                #:form-fields
                #:form-data
                #:form-instance
                #:form-errors
                #:form-cleaned-data
                #:form-validp
                #:validate-form
                #:clean
                #:model-form
                #:make-model-form
                #:save-form
                #:field-context
                #:form-field-by-name
                #:cleaned-value
                #:resolve-widget
                #:request-form-data
                #:register-widget-field-class
                #:render-field
                #:render-fields
                #:render-form)

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
                #:define-model
                ;; Shortcuts
                #:get-or-404
                #:found-or-404)

  (:export
   ;; HTTP errors
   #:http-error
   #:http-error-status
   #:http-error-message
   #:http-error-headers
   #:http-error-cause
   #:http-error-type
   #:http-client-error
   #:http-server-error
   #:bad-request
   #:unauthorized
   #:forbidden
   #:not-found
   #:method-not-allowed
   #:allowed-methods
   #:internal-server-error
   #:abort-with
   #:condition-http-status
   #:define-error-page
   #:remove-error-page
   #:find-error-page
   #:*error-pages*
   #:default-error-page
   #:reason-phrase
   #:*fragment-p*
   #:*debug-404*
   #:*log-client-errors*
   #:*static-error-root*
   #:*prefer-static-5xx*
   #:retry-request
   #:show-debug-page
   #:show-error-page
   #:get-or-404
   #:found-or-404
   #:*atomic-requests*
   ;; Typed route parameters
   #:define-path-converter
   #:*auto-options*
   ;; Settings
   #:define-setting
   #:setting
   #:boolean-setting
   #:integer-setting
   #:string-setting
   #:pathname-setting
   #:choice-setting
   #:list-setting
   #:setting-name
   #:setting-documentation
   #:setting-source
   #:setting-unset
   #:find-setting
   #:list-settings
   #:configure
   #:per-environment
   #:current-environment
   #:development-p
   #:test-p
   #:production-p
   #:load-settings
   #:reload-settings
   #:settings-loaded-p
   #:with-settings
   #:on-setting-change
   #:remove-setting-listener
   #:print-settings
   #:settings-report
   #:redact
   #:coerce-value
   #:check-value
   #:reject
   #:render-value
   #:settings-invalid-problems
   #:problem-name
   #:problem-message
   #:setting-invalid-name
   #:setting-invalid-value
   #:setting-invalid-source
   #:setting-unknown-name
   #:settings-invalid
   #:setting-invalid
   #:setting-unknown
   #:settings-not-loaded
   #:secret-configured
   #:unknown-setting-warning
   #:setup-database
   #:connect-database
   #:site-origin

   #:*request*

   #:routes
   #:routes-mapper
   #:module
   #:module-routes
   #:module-prefix
   #:module-static-root
   #:*routes*
   #:coerce-route-name
   #:define-route
   #:define-routes
   #:define-module
   #:define-application
   #:*module-registry*
   #:register-module
   #:get-module

   #:start
   #:stop

   #:translate
   #:with-locale
   #:current-locale
   #:load-localisations
   #:ensure-localisations
   #:available-locales
   #:message-id
   #:locale-html-lang
   #:*locale*
   #:*default-locale*
   #:*fallback-locale*

   #:http-response
   #:url
   #:current-path
   #:static
   #:cached-static
   #:absolute-url
   #:collectstatic

   ;; Management commands (app-binary CLI)
   #:run-cli
   #:register-command

   #:post-request-p
   #:parse-body-params
   #:redirect-response
   #:canonicalize-path
   #:canonicalize-redirect-url

   ;; Admin
   #:define-admin

   ;; Forms
   #:form
   #:form-fields
   #:form-data
   #:form-instance
   #:form-errors
   #:form-cleaned-data
   #:form-validp
   #:validate-form
   #:clean
   #:model-form
   #:make-model-form
   #:save-form
   #:field-context
   #:form-field-by-name
   #:cleaned-value
   #:resolve-widget
   #:request-form-data
   #:register-widget-field-class
   #:render-field
   #:render-fields
   #:render-form

   ;; Auth
   #:hash-password
   #:verify-password
   #:user
   #:user-email
   #:user-is-active
   #:user-is-staff
   #:make-user
   #:find-user-by-email
   #:find-user-by-id
   #:set-password
   #:check-password
   #:ensure-tables
   #:current-user
   #:authenticatedp
   #:login-user
   #:logout-user
   #:authenticate
   #:check-guard
   #:require-login
   #:require-staff
   #:login-required
   #:staff-required
   #:*login-url*
   #:*post-login-redirect*

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
   #:define-model
   ;; Utils
   #:post-request-p
   #:parse-body-params
   #:redirect-response
   #:canonicalize-path
   #:canonicalize-redirect-url
   #:current-session-hash
   #:csrf-token-value
   #:text-response
   #:json-response
   #:html-fragment-response
   #:ensure-session-table
   ))
