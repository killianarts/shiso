(defpackage #:shiso/utils
  (:use #:cl)
  (:local-nicknames (#:routing #:shiso/routing)
                    (#:modules #:shiso/modules)
                    (#:requests #:shiso/requests)
                    (#:req #:lack/request)
                    (#:csrf #:lack/middleware/csrf))
  (:export
   #:url
   #:current-path
   #:static
   #:absolute-url
   #:http-response
   #:post-request-p
   #:parse-body-params
   #:redirect-response
   #:current-session-hash
   #:csrf-token-value
   #:text-response
   #:json-response
   #:html-fragment-response
   #:ensure-session-table))

(in-package #:shiso/utils)

(defun http-response (body &key (code 200) (headers nil))
  (let ((headers (append `(:content-type "text/html; charset=utf-8") headers)))
    `(,code ,headers (,body)) ))

(defun post-request-p ()
  "Return T if the current request method is POST."
  (eq :POST (req:request-method requests:*request*)))

(defun parse-body-params ()
  "Parse the current request body as URL-encoded form data and return an
alist of (keyword . string)."
  (let* ((body-params (req:request-body-parameters requests:*request*)))
    (mapcar (lambda (pair)
              (cons (intern (string-upcase (car pair)) :keyword)
                    (cdr pair)))
            body-params)))

(defun redirect-response (url &key (code 302))
  "Return a Clack-style redirect response to URL."
  (list code (list :location url) '("")))

(defun current-session-hash ()
  (getf (req:request-env requests:*request*) :lack.session))

(defun csrf-token-value ()
  (let ((s (current-session-hash)))
    (when s (csrf:csrf-token s))))

(defun text-response (body &key (code 200))
  `(,code (:content-type "text/plain; charset=utf-8") (,body)))

(defun json-response (body &key (code 200))
  `(,code (:content-type "application/json; charset=utf-8") (,body)))

(defun html-fragment-response (body &key (code 200))
  `(,code (:content-type "text/html; charset=utf-8") (,body)))

(defun url (name &rest params)
  "Return the URL for a named route, with module prefix prepended.
Searches registered module mappers by namespace for namespaced routes
(e.g., \"articles:index\"), falls back to global `*routes*' for others."
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

(defun params ()
  ())

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

(defun ensure-session-table (&key (table-name "shiso_session")
                               (id-column-name "id")
                               (data-column-name "session_data")
                               (connection nil))
  "Creates the session table (IF NOT EXISTS) used by Lack's DBI session store
(typically configured via shiso/auth/session or directly with
lack.middleware.session).

This must be called during database setup (e.g. in your app's setup-database)
because the lack dbi store does not automatically create its backing table.

Example:
  (shiso:ensure-session-table)  ; uses default \"shiso_session\"
  (shiso:ensure-session-table :table-name \"sessions\")

The table schema matches what lack/session/store/dbi expects:
  id TEXT PRIMARY KEY, session_data TEXT, created_at TEXT, updated_at TEXT
"
  (let ((conn (or connection mito:*connection*)))
    (unless conn
      (error "No active database connection. Call mito:connect-toplevel first, or pass :connection."))
    (dbi:do-sql conn
      (format nil "CREATE TABLE IF NOT EXISTS ~A (~A TEXT PRIMARY KEY, ~A TEXT, created_at TEXT, updated_at TEXT)"
              table-name
              id-column-name
              data-column-name))
    t))

(defun debug! (sym)
  (when (symbolp sym)
    (format *standard-output* "~%~%=== SHISO DEBUG ===~%~%~a: ~a~%~%" (symbol-name sym) sym))
  (unless (symbolp sym)
    (format *standard-output* "~%~%=== SHISO DEBUG ===~%~%~a~%~%" sym)))
