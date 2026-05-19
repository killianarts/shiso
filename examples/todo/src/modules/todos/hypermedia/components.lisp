(defpackage #:todos/hypermedia
  (:use #:cl)
  (:local-nicknames (#:ah #:almighty-html))
  (:export #:page))

(in-package #:todos/hypermedia)

(defparameter *style* "
body { font-family: system-ui, sans-serif; max-width: 560px; margin: 2rem auto; padding: 0 1rem; }
h1 { margin-bottom: 1rem; }
form.add { display: flex; gap: 0.5rem; margin-bottom: 1.5rem; }
form.add input[type=text] { flex: 1; padding: 0.5rem; }
ul.todos { list-style: none; padding: 0; }
ul.todos li { display: flex; align-items: center; gap: 0.5rem;
              padding: 0.4rem 0; border-bottom: 1px solid #eee; }
ul.todos li.done .title { text-decoration: line-through; color: #888; }
ul.todos form { display: inline; }
ul.todos button.delete { margin-left: auto; }
.session { margin-top: 2rem; color: #555; font-size: 0.9rem; }
.session a, .session form { display: inline; }
")

(defun page (page-title body)
  "Render PAGE-TITLE and BODY into a complete HTML page string."
  (ah:render-to-string
   (ah:</>
    (html :lang "en"
      (head
        (meta :charset "utf-8")
        (meta :name "viewport" :content "width=device-width, initial-scale=1")
        (title page-title)
        (style *style*))
      (body body)))))
