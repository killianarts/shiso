(defsystem "errors-demo"
  :description "Pages that show how Shiso handles HTTP errors: error pages,
405s, typed route parameters, get-or-404, atomic POSTs, JSON and HTMX
error responses, the debug pages and the REPL debugger."
  :version "0.1"
  :depends-on (:shiso)
  :components ((:module "src"
                :serial t
                :components ((:file "settings")
                             (:file "layout")
                             (:file "demo")
                             (:file "error-pages")
                             (:file "app")))))
