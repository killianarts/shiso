;;;; Shiso projects are intended to use `vend' for dependency management.
;;;; This build file ensures only the vendored tree is visible to ASDF.

(require :asdf)

(asdf:initialize-source-registry
 `(:source-registry (:tree ,(uiop:getcwd))
   :ignore-inherited-configuration))

(asdf:load-system "<% @var application-name %>")
(asdf:make "<% @var application-name %>")
