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
                ((:file "main")))))

