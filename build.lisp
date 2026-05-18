(require :asdf)

(asdf:initialize-source-registry
 `(:source-registry (:tree ,(uiop:getcwd))
   :ignore-inherited-configuration))

(asdf:load-system :shiso)
(asdf:make :shiso)
