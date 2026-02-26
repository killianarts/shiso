(defpackage #:<% @var name %>/routes
  (:use #:cl)
  (:local-nicknames (#:s #:shiso)
                    (#:controllers #:<% @var name %>/controllers)))

(in-package #:<% @var name %>/routes)

(s:define-module <% @var name %>
  (:urls (:GET "/" #'controllers:index "index")))
