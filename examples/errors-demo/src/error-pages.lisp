(defpackage #:errors-demo/error-pages
  (:use #:cl)
  (:local-nicknames (#:s #:shiso)
                    (#:ah #:almighty-html)
                    (#:layout #:errors-demo/layout)
                    (#:demo #:errors-demo/demo)))

(in-package #:errors-demo/error-pages)

;;;; The app's error pages: one form per status or class. Lookup is the exact
;;;; status, then :4xx / :5xx, then T, then Shiso's built-in page. Each page
;;;; returns a string (or an almighty-html node, or a whole Clack response).

(defun error-box (c which &rest body)
  "The error, framed, saying which DEFINE-ERROR-PAGE form rendered it."
  (let* ((status (s:http-error-status c))
         (heading (format nil "~D ~A" status (s:reason-phrase status)))
         (box (ah:</>
               (div :class "error-page"
                 (p :class "which" (format nil "Rendered by ~A in error-pages.lisp" which))
                 (h1 heading)
                 body
                 (p (a :href "/" "← Back to the tour"))))))
    ;; An HTMX request swaps the fragment into the page it came from.
    (if s:*fragment-p*
        (ah:render-to-string box)
        (layout:page heading box))))

(s:define-error-page 404 (c)
  (error-box c "(s:define-error-page 404 …)"
             (ah:</> (p "There's nothing at this address."))
             (when (s:http-error-message c)
               (ah:</> (p (s:http-error-message c))))))

(s:define-error-page :4xx (c)
  (error-box c "(s:define-error-page :4xx …)"
             (ah:</> (p (or (s:http-error-message c) "The request can't be served.")))))

(s:define-error-page :5xx (c)
  (when (typep (s:http-error-cause c) 'demo:page-bug)
    ;; On purpose, for /broken-error-page: Shiso logs this and serves
    ;; static/errors/500.html.
    (error "The :5xx error page has a bug of its own."))
  (error-box c "(s:define-error-page :5xx …)"
             (ah:</> (p "Something went wrong on our side. It has been logged."))))
