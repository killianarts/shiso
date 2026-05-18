(defsystem "<% @var name %>"
  :description "<% @var name %> module"
  :version "0.1"
  :depends-on (:shiso)
  :pathname "."
  :serial t
  :components ((:file "<% @var name %>")
               (:file "models")
               (:file "forms")
               (:module "hypermedia"
                :components ((:file "components")))
               (:file "controllers")
               (:file "routes")))
