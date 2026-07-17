(defpackage #:<% @var application-name %>/hypermedia/components
  (:use #:cl)
  (:local-nicknames (#:ah #:almighty-html)
                    (#:s  #:shiso))
  (:export #:ac-page-skeleton))

(in-package #:<% @var application-name %>/hypermedia/components)

(ah:define-component ac-page-skeleton (&key title (lang "en") css-urls script-urls
                                            head-extra children)
  "Boilerplate HTML page. <head> always carries, in order: <meta charset>,
<meta viewport>, <meta csrf-token> (when a session is bound), <title>; then
one <link> per CSS-URL and one deferred <script> per SCRIPT-URL. HEAD-EXTRA
(a pre-built element or fragment) is spliced last into <head> — use it for
inline <style>, http-equiv metas, or non-deferred module scripts. CHILDREN
are placed inside <body>."
  (let ((token (s:csrf-token-value)))
    (ah:</>
     (html :lang lang
       (head
         (meta :charset "utf-8")
         (meta :name "viewport" :content "width=device-width, initial-scale=1")
         (when token (ah:</> (meta :name "csrf-token" :content token)))
         (title title)
         (<>
           (loop :for url :in css-urls
                 :collect (ah:</> (link :rel "stylesheet" :href url))))
         (<>
           (loop :for url :in script-urls
                 :collect (ah:</> (script :src url :defer t))))
         head-extra)
       (body children)))))
