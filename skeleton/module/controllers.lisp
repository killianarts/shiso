(defpackage #:<% @var name %>/controllers
            (:use #:cl)
            (:local-nicknames (#:s #:shiso))
            (:export #:index))

(in-package #:<% @var name %>/controllers)

(defun index ()
  (s:http-response "Welcome to <% @var name %>"))
