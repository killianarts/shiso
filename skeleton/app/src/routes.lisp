(defpackage #:<% @var name %>/routes
  (:use #:cl)
  (:local-nicknames (#:s #:shiso))
  (:export #:application))
(in-package #:<% @var name %>/routes)

(defun home ()
  (s:http-response "Hello from <% @var name %>!"))

(s:define-module home
  (:urls (:GET "/" #'home "index")))

(s:define-application application ()
  (:modules
   ("" home)))
