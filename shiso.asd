(defsystem "shiso"
  :author "Micah Killian <micah@killianarts.online>"
  :maintainer "Micah Killian <micah@killianarts.online>"
  :description "An Almighty web framework for Almighty Lisp web developers."
  :license "MIT"
  :version "0.1"
  :depends-on (:clack
               :woo
               :myway
               :lack
               :lack-component
               :lack-request
               :lack-response
               :lack-middleware-static
               :lack-app-file
               ;; Scaffolding
               ;; :cl-project ; Trouble with vend
               ;; Almighty Components
               :almighty-html
               ;; ORM
               :mito
               ;; Validation
               :cl-ppcre
               ;; Pattern Matching
               :trivia
               )
  :components ((:module "src"
                :serial t
                :components
                ((:file "modules")
                 (:file "static")
                 (:file "routing")
                 (:file "requests")
                 (:file "server")
                 (:file "utils")
                 ;; (:file "scaffold")
                 ;; Validators (no dependencies on models)
                 (:file "validators")
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
                               (:file "model-form")
                               (:file "rendering")
                               (:file "package")))
                 ;; Admin
                 (:module "admin" :serial t
                  :components ((:file "registry")
                               (:file "components")
                               (:file "middleware")
                               (:file "controllers")
                               (:file "routes")
                               (:file "package")))
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
                 (:file "admin"))))
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
                                      :package :shiso/t/admin)))

