(defpackage #:<% @var application-name %>/routes
  (:use #:cl)
  (:local-nicknames (#:s #:shiso))
  (:export #:application))

(in-package #:<% @var application-name %>/routes)

(defun home ()
  (s:http-response "Hello from <% @var application-name %>!"))

(s:define-module home
  (:urls (:GET "/" #'home "index")))

(s:define-application application ()
  (:modules
   ("/i18n" shiso-i18n)
   ("" home)))
