(defsystem "todos"
  :description "todos module"
  :version "0.1"
  :depends-on (:shiso)
  :pathname "."
  :serial t
  :components ((:file "todos")
               (:file "models")
               (:file "forms")
               (:module "hypermedia"
                :serial t
                :components ((:file "form-components")
                             (:file "components")))
               (:file "controllers")
               (:file "routes")))
