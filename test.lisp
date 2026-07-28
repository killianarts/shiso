(require :asdf)

(asdf:initialize-source-registry
 `(:source-registry (:tree ,(uiop:getcwd))
   :ignore-inherited-configuration))

(asdf:load-system :shiso)

(progn
  (format t "--- COMPILING EXECUTABLE ---~%")
  (asdf:test-system :shiso)
  (format t "--- DONE ---~%")
  (exit))
