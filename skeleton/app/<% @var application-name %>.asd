(defsystem "<% @var application-name %>"
  :description "<% @var application-name %> application"
  :version "0.1"
  :depends-on (:shiso
               "<% @var application-name %>/hypermedia")
  :build-operation "program-op"
  :build-pathname "<% @var application-name %>"
  :entry-point "<% @var application-name %>:main"
  :components ((:module "src"
                :serial t
                :components ((:file "config")
                             (:file "routes")
                             (:file "main")
                             (:file "package")))))

(defsystem "<% @var application-name %>/hypermedia"
  :description "Project-wide hypermedia components shared by every module (page skeleton, form components)."
  :depends-on (:shiso)
  :pathname "src/hypermedia"
  :serial t
  :components ((:file "components")
               (:file "form-components")
               (:file "package")))
