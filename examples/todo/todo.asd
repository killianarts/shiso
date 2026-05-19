(defsystem "todo"
  :description "todo — a minimal Shiso example app showing models, forms, admin, and auth"
  :version "0.1"
  :depends-on (:shiso
               :todos)
  :build-operation "program-op"
  :build-pathname "todo"
  :entry-point "todo:main"
  :components ((:module "src"
                :serial t
                :components ((:file "package")
                             (:file "routes")
                             (:file "main")))))
