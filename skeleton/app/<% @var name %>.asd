(defsystem "<% @var name %>"
  :description "<% @var name %> application"
  :version "0.1"
  :depends-on (:shiso)
  :build-operation "program-op"
  :build-pathname "<% @var name %>"
  :entry-point "<% @var name %>:main"
  :components ((:module "src"
                :serial t
                :components ((:file "package")
                             (:file "routes")
                             (:file "main")))))
