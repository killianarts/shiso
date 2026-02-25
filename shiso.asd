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
               ;; Almighty Components
               :almighty-html
               )
  :components ((:module "src"
                :serial t
                :components
                ((:file "main"))))
  :in-order-to ((test-op (test-op "shiso/tests"))))

(defsystem "shiso/tests"
  :depends-on (:shiso :lisp-unit2)
  :components ((:module "t"
                :serial t
                :components
                ((:file "routes")
                 (:file "modules"))))
  :perform (test-op (o s)
             (uiop:symbol-call :lisp-unit2 :run-tests
                               :package :shiso/t/routes)
             (uiop:symbol-call :lisp-unit2 :run-tests
                               :package :shiso/t/modules)))

