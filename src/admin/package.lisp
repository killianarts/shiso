(defpackage #:shiso/admin
  (:use #:cl)
  (:import-from #:shiso/admin/registry
                #:admin-config
                #:admin-model-name
                #:admin-list-display
                #:admin-list-filter
                #:admin-search-fields
                #:admin-fieldsets
                #:admin-fields
                #:admin-exclude
                #:admin-readonly
                #:admin-per-page
                #:admin-ordering
                #:*admin-registry*
                #:register-admin
                #:get-admin
                #:all-registered-admins
                #:define-admin)
  (:import-from #:shiso/admin/routes)
  (:import-from #:shiso/admin/middleware
                #:post-request-p
                #:parse-body-params
                #:redirect-response
                #:http-response)
  (:export
   ;; Registry
   #:admin-config
   #:admin-model-name
   #:admin-list-display
   #:admin-list-filter
   #:admin-search-fields
   #:admin-fieldsets
   #:admin-fields
   #:admin-exclude
   #:admin-readonly
   #:admin-per-page
   #:admin-ordering
   #:*admin-registry*
   #:register-admin
   #:get-admin
   #:all-registered-admins
   #:define-admin
   ;; Middleware
   #:post-request-p
   #:parse-body-params
   #:redirect-response
   #:http-response))
