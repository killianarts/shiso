(defpackage #:shiso/utils
  (:use #:cl)
  (:local-nicknames (#:routing #:shiso/routing)
                    (#:modules #:shiso/modules)
                    (#:requests #:shiso/requests))
  (:export
   #:url
   #:current-path
   #:static
   #:absolute-url
   #:http-response))

(in-package #:shiso/utils)

(defun http-response (body &key (code 200) (headers nil))
  (let ((headers (append `(:content-type "text/html; charset=utf-8") headers)))
    `(,code ,headers (,body)) ))

(defun url (name &rest params)
  "Return the URL for a named route, with module prefix prepended.
Searches registered module mappers by namespace for namespaced routes
(e.g., \"articles:index\"), falls back to global *routes* for others."
  (if (and (stringp name) (position #\: name))
      ;; Namespaced route — search the module's mapper
      (let* ((pos (position #\: name))
             (ns-str (subseq name 0 pos))
             (ns-kw (intern (string-upcase ns-str) :keyword))
             (mod (modules:get-module ns-kw))
             (mapper (routing:routes-mapper (modules:module-routes mod)))
             (route (myway:find-route-by-name mapper name)))
        (when route
          (let ((base-url (myway:url-for route params))
                (prefix (modules:module-prefix mod)))
            (concatenate 'string prefix base-url))))
      ;; Non-namespaced route — fall back to global *routes*
      (let* ((name-kw (intern (string-upcase name) :keyword))
             (route (myway:find-route-by-name
                     (routing:routes-mapper routing:*routes*) name-kw)))
        (when route
          (myway:url-for route params)))))

(defun current-path ()
  "Get the path to the current page."
  (lack/request:request-path-info requests:*request*))

(defun static (path)
  "Return the URL path for a static file. Like Django's {% static %} tag.
   (shiso:static \"css/style.css\") → \"/static/css/style.css\""
  (concatenate 'string "/static/" path))

(defun absolute-url (path)
  "Prepend the current request's scheme and host to PATH.
   (shiso:absolute-url \"/static/img/preview.png\")
   → \"https://example.com/static/img/preview.png\""
  (let ((scheme (lack.request:request-uri-scheme requests:*request*))
        (server-name (lack.request:request-server-name requests:*request*)))
    (format nil "~a://~a~a" scheme server-name path)))

(defun debug! (sym)
  (when (symbolp sym)
    (format *standard-output* "~%~%=== SHISO DEBUG ===~%~%~a: ~a~%~%" (symbol-name sym) sym))
  (unless (symbolp sym)
    (format *standard-output* "~%~%=== SHISO DEBUG ===~%~%~a~%~%" sym)))
