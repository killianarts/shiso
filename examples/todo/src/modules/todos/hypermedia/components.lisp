(uiop:define-package #:todos/hypermedia
  (:use #:cl)
  (:use-reexport #:todos/hypermedia/form-components)
  (:local-nicknames (#:ah #:almighty-html))
  (:export #:page))

(in-package #:todos/hypermedia)

(defparameter *style* "
body { font-family: system-ui, sans-serif; max-width: 560px; margin: 2rem auto; padding: 0 1rem; }
h1 { margin-bottom: 1rem; }
form.add { display: flex; flex-wrap: wrap; gap: 0.5rem; margin-bottom: 1.5rem; align-items: center; }
form.add input[type=text] { flex: 1; padding: 0.5rem; }
form.add .field-errors { flex: 1 0 100%; color: #b00020; margin: 0; padding-left: 1.2rem; }
form.edit .field { margin-bottom: 1rem; }
form.edit .field label { display: block; margin-bottom: 0.25rem; }
form.edit .field input[type=text] { width: 100%; padding: 0.5rem; box-sizing: border-box; }
.field.has-errors input, .field.has-errors textarea { border-color: #b00020; }
.field-errors { color: #b00020; margin: 0.25rem 0 0; padding-left: 1.2rem; }
.help-text { color: #666; font-size: 0.85rem; margin: 0.25rem 0 0; }
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
