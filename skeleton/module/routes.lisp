(defpackage #:<% @var module-name %>/routes
  (:use #:cl)
  (:local-nicknames (#:s #:shiso)
                    (#:controllers #:<% @var module-name %>/controllers)))

(in-package #:<% @var module-name %>/routes)

(s:define-module <% @var module-name %>
  (:urls (:GET "/" #'controllers:index "index")))
