(defpackage #:<% @var module-name %>/controllers
            (:use #:cl)
            (:local-nicknames (#:s #:shiso))
            (:export #:index))

(in-package #:<% @var module-name %>/controllers)

(defun index ()
  (s:http-response "Welcome to <% @var module-name %>"))
