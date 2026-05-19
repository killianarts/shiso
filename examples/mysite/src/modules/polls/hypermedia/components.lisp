(defpackage #:polls/hypermedia
  (:use #:cl)
  (:local-nicknames (#:ah #:almighty-html))
  (:export #:page))

(in-package #:polls/hypermedia)

(defparameter *style* "
body { font-family: system-ui, sans-serif; max-width: 640px; margin: 2rem auto; padding: 0 1rem; }
h1 { margin-bottom: 1rem; }
ul.questions { list-style: none; padding: 0; }
ul.questions li { padding: 0.5rem 0; border-bottom: 1px solid #eee; }
form.vote { margin-top: 1rem; }
form.vote label { display: block; padding: 0.25rem 0; }
button { margin-top: 0.75rem; padding: 0.5rem 1rem; }
.results li { padding: 0.25rem 0; }
.error { color: #c00; }
")

(defun page (page-title body)
  "Render PAGE-TITLE and BODY (an almighty-html node) into a full HTML page string."
  (ah:render-to-string
   (ah:</>
    (html :lang "en"
      (head
        (meta :charset "utf-8")
        (meta :name "viewport" :content "width=device-width, initial-scale=1")
        (title page-title)
        (style *style*))
      (body body)))))
