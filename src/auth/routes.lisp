(defpackage #:shiso/auth/routes
  (:use #:cl)
  (:local-nicknames (#:routing #:shiso/routing)
                    (#:controllers #:shiso/auth/controllers)))

(in-package #:shiso/auth/routes)

(routing:define-module shiso-auth
  (:urls
   ((:GET :POST) "/login"  'controllers:login-view  "login")
   (:POST        "/logout" 'controllers:logout-view "logout")
   ((:GET :POST) "/signup" 'controllers:signup-view "signup")))
