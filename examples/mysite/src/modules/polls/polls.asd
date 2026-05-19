(defsystem "polls"
  :description "polls module"
  :version "0.1"
  :depends-on (:shiso)
  :pathname "."
  :serial t
  :components ((:file "polls")
               (:file "models")
               (:file "forms")
               (:module "hypermedia"
                :components ((:file "components")))
               (:file "controllers")
               (:file "routes")))
