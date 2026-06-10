(defpackage #:shiso/auth
  (:use #:cl)
  (:import-from #:shiso/auth/password
                #:hash-password
                #:verify-password)
  (:import-from #:shiso/auth/user
                #:user
                #:user-email
                #:user-password-hash
                #:user-is-active
                #:user-is-staff
                #:user-last-login-at
                #:make-user
                #:find-user-by-email
                #:find-user-by-id
                #:set-password
                #:check-password)
  (:import-from #:shiso/auth/session
                #:ensure-tables
                #:make-store
                #:current-user
                #:authenticatedp
                #:login-user
                #:logout-user
                #:authenticate)
  (:import-from #:shiso/auth/guards
                #:check-guard
                #:require-login
                #:require-staff
                #:login-required
                #:staff-required
                #:*login-url*
                #:*post-login-redirect*)
  (:import-from #:shiso/auth/createsuperuser
                #:create-superuser
                #:superuser-error)
  (:import-from #:shiso/auth/routes)
  (:export
   ;; Password
   #:hash-password
   #:verify-password
   ;; User
   #:user
   #:user-email
   #:user-password-hash
   #:user-is-active
   #:user-is-staff
   #:user-last-login-at
   #:make-user
   #:find-user-by-email
   #:find-user-by-id
   #:set-password
   #:check-password
   ;; Session
   #:ensure-tables
   #:make-store
   #:current-user
   #:authenticatedp
   #:login-user
   #:logout-user
   #:authenticate
   ;; Guards
   #:check-guard
   #:require-login
   #:require-staff
   #:login-required
   #:staff-required
   #:*login-url*
   #:*post-login-redirect*
   ;; Management
   #:create-superuser
   #:superuser-error))
