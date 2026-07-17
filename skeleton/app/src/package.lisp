(uiop:define-package #:<% @var application-name %>
  (:use #:cl)
  (:use-reexport #:<% @var application-name %>/main))

(in-package #:<% @var application-name %>)
