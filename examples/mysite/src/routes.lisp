(defpackage #:mysite/routes
  (:use #:cl)
  (:local-nicknames (#:s #:shiso))
  (:export #:application))

(in-package #:mysite/routes)

(s:define-application application ()
  (:modules
   ("/admin" shiso-admin)
   ("/i18n"  shiso-i18n)
   (""       shiso-auth)
   ("/polls" polls)))
