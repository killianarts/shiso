(defpackage #:todo/routes
  (:use #:cl)
  (:local-nicknames (#:s #:shiso))
  (:export #:application))

(in-package #:todo/routes)

(s:define-application application ()
  (:modules
   ("/admin" shiso-admin)
   (""       shiso-auth)
   (""       todos)))
