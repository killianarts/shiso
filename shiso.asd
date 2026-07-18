(defsystem "shiso"
  :author "Micah Killian <micah@killianarts.online>"
  :maintainer "Micah Killian <micah@killianarts.online>"
  :description "An Almighty web framework for Almighty Lisp web developers."
  :license "MIT"
  :version "0.2"
  :build-operation "program-op"
  :build-pathname "shiso"
  :entry-point "shiso/cli:main"
  :depends-on (:clack
               :woo
               :myway
               :lack
               :lack-component
               :lack-request
               :lack-response
               :lack-middleware-static
               :lack-middleware-session
               :lack-session-store-dbi
               :lack-middleware-csrf
               :lack-app-file
               ;; Almighty Components
               :almighty-html
               ;; ORM
               :mito
               ;; Validation
               :cl-ppcre
               ;; Pattern Matching
               :trivia
               ;; Auth
               :cl-pass
               ;; CLI
               :clingon
               )
  :components ((:module "src"
                :serial t
                :components
                ((:file "modules")
                 (:file "static")
                 (:file "routing")
                 (:file "requests")
                 (:file "utils")
                 ;; Validators (no dependencies on models)
                 (:file "validators")
                 ;; CLI / scaffolding
                 (:module "cli" :serial t
                  :components ((:file "render")
                               (:file "commands")
                               (:file "main")
                               (:file "package")))
                 ;; Models
                 (:module "models" :serial t
                  :components ((:file "metadata")
                               (:file "registry")
                               (:file "field-types")
                               (:file "define-model")
                               (:file "package")))
                 ;; Forms
                 (:module "forms" :serial t
                  :components ((:file "fields")
                               (:file "form")
                               (:file "context")
                               (:file "model-form")
                               (:file "rendering")
                               (:file "package")))
                 ;; Auth (defined before admin so admin can guard with :staff)
                 (:module "auth" :serial t
                  :components ((:file "password")
                               (:file "user")
                               (:file "session")
                               (:file "guards")
                               (:file "forms")
                               (:file "controllers")
                               (:file "routes")
                               (:file "createsuperuser")
                               (:file "package")))
                 ;; Server — loaded after auth so it can install the
                 ;; session+CSRF middleware stack using shiso/auth/session.
                 (:file "server")
                 ;; Admin
                 (:module "admin" :serial t
                  :components ((:file "registry")
                               (:file "components")
                               (:file "middleware")
                               (:file "controllers")
                               (:file "routes")
                               (:file "package")))
                 ;; Management commands for app binaries (createsuperuser, …).
                 ;; After auth (uses shiso/auth) and clingon.
                 (:file "management")
                 (:file "package"))))
  :in-order-to ((test-op (test-op "shiso/tests"))))

(defsystem "shiso/tests"
  :depends-on (:shiso :lisp-unit2 :alexandria)
  :components ((:module "t"
                :serial t
                :components
                ((:file "routes")
                 (:file "modules")
                 (:file "models")
                 (:file "validators")
                 (:file "forms")
                 (:file "admin")
                 (:file "auth"))))
  :perform (test-op (o s)
                    (uiop:symbol-call :lisp-unit2 :run-tests
                                      :package :shiso/t/routes)
                    (uiop:symbol-call :lisp-unit2 :run-tests
                                      :package :shiso/t/modules)
                    (uiop:symbol-call :lisp-unit2 :run-tests
                                      :package :shiso/t/models)
                    (uiop:symbol-call :lisp-unit2 :run-tests
                                      :package :shiso/t/validators)
                    (uiop:symbol-call :lisp-unit2 :run-tests
                                      :package :shiso/t/forms)
                    (uiop:symbol-call :lisp-unit2 :run-tests
                                      :package :shiso/t/admin)
                    (uiop:symbol-call :lisp-unit2 :run-tests
                                      :package :shiso/t/auth)))

