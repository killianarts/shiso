(defsystem "<% @var module-name %>"
  :description "<% @var module-name %> module"
  :version "0.1"
  :depends-on (:shiso)
  :pathname "."
  :serial t
  :components ((:file "<% @var module-name %>")
               (:file "models")
               (:file "forms")
               (:module "hypermedia"
                :serial t
                :components ((:file "components")
                             (:file "package")))
               (:file "controllers")
               (:file "routes")))
