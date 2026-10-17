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

;;; Error pages. Without any, Shiso's built-in pages are used. Lookup is the
;;; exact status, then :4xx / :5xx, then T. A page returns an HTML string, an
;;; almighty-html node or a Clack response. In development (debug mode) a 404
;;; lists the routes tried instead; set shiso:*debug-404* to NIL to preview
;;; yours. If a page itself fails, static/errors/500.html is served.
;;
;; (s:define-error-page 404 (c)
;;   (almighty-html:</>
;;    (div (h1 "Not found")
;;         (p (or (s:http-error-message c) "There's nothing here.")))))
;;
;; (s:define-error-page :5xx (c)
;;   (declare (ignore c))
;;   "<h1>Something went wrong</h1><p>It has been logged.</p>")
