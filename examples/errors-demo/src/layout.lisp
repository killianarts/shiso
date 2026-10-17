(defpackage #:errors-demo/layout
  (:use #:cl)
  (:local-nicknames (#:ah #:almighty-html))
  (:export #:page #:render))

(in-package #:errors-demo/layout)

(defparameter *css* "
body { font-family: system-ui, sans-serif; max-width: 52rem; margin: 2rem auto; padding: 0 1rem; color: #222; line-height: 1.45; }
h1 { font-size: 1.6rem; margin-bottom: 0.25rem; }
h2 { font-size: 1.15rem; margin-top: 2rem; border-bottom: 1px solid #ddd; padding-bottom: 0.25rem; }
table { border-collapse: collapse; width: 100%; font-size: 0.92rem; }
td, th { text-align: left; vertical-align: top; padding: 0.35rem 0.5rem; border-bottom: 1px solid #eee; }
td:first-child { white-space: nowrap; }
code { font-size: 0.9em; background: #f3f3f3; padding: 0 0.2em; }
pre { background: #f5f5f5; padding: 0.75rem; overflow-x: auto; font-size: 0.85rem; min-height: 1.5rem; }
form.inline { display: inline; }
button { padding: 0.3rem 0.7rem; margin: 0.15rem 0.25rem 0.15rem 0; }
.mode { background: #eef4ff; border: 1px solid #c9dbff; padding: 0.6rem 0.8rem; font-size: 0.92rem; }
.error-page { border: 2px solid #d33; padding: 0.5rem 1rem 1rem; }
.error-page .which { color: #888; font-size: 0.85rem; }
@media (prefers-color-scheme: dark) {
  body { background: #161616; color: #ddd; }
  code, pre { background: #262626; }
  td, th, h2 { border-color: #333; }
  .mode { background: #1d2635; border-color: #2c3d5c; }
}
")

(defun page (title &rest body)
  "A full page around BODY nodes."
  (ah:render-to-string
   (ah:</>
    (html :lang "en"
      (head
        (meta :charset "utf-8")
        (meta :name "viewport" :content "width=device-width, initial-scale=1")
        (title title)
        (style (raw! *css*)))
      (body body)))))

(defun render (title &rest body)
  "A 200 response holding PAGE."
  (shiso:http-response (apply #'page title body)))
