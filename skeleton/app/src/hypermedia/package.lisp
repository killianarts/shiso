;;;; Intended use: `:mix-reexport' / `:use-reexport' individual hypermedia
;;;; component packages defined in sibling files.
(uiop:define-package #:<% @var application-name %>/hypermedia
  (:use #:cl)
  (:use-reexport #:<% @var application-name %>/hypermedia/components))

(in-package #:<% @var application-name %>/hypermedia)
