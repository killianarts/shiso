(defpackage #:shiso/errors
  (:use #:cl)
  (:local-nicknames (#:ah #:almighty-html)
                    (#:settei #:almighty-settei)
                    (#:static #:shiso/static))
  (:export
   ;; Conditions
   #:http-error
   #:http-error-status
   #:http-error-message
   #:http-error-headers
   #:http-error-cause
   #:http-error-type
   #:http-client-error
   #:http-server-error
   #:bad-request
   #:unauthorized
   #:forbidden
   #:not-found
   #:not-found-mounts
   #:method-not-allowed
   #:allowed-methods
   #:internal-server-error
   #:abort-with
   #:condition-http-status
   ;; Error pages
   #:define-error-page
   #:remove-error-page
   #:find-error-page
   #:*error-pages*
   #:default-error-page
   #:reason-phrase
   #:render-error-response
   #:signal-or-render
   #:*fragment-p*
   ;; Middleware and its tunables
   #:wrap-http-errors
   #:*debug*
   #:debug-mode
   #:*debug-404*
   #:*allowed-methods*
   #:*route-describer*
   #:*render-around*
   #:*log-client-errors*
   #:*static-error-root*
   #:*prefer-static-5xx*
   #:local-request-p
   #:editor-connected-p
   #:log-error
   ;; Restarts offered by the :repl debugger mode
   #:retry-request
   #:show-debug-page
   #:show-error-page))

(in-package #:shiso/errors)

;;;; HTTP errors: a condition per status that code anywhere in a request can
;;;; signal, one middleware that turns conditions into responses, and a
;;;; registry of error pages the application defines, one form per status.
;;;; See shiso-error-handling-plan.org for the design and what it borrows from
;;;; Django, Rails and Phoenix.

;;; Settings

(settei:define-setting :server/repl-debugger settei:boolean-setting
  "In debug mode, whether an unexpected error opens the Lisp debugger in the
connected editor (SLY or SLIME), with RETRY-REQUEST and SHOW-DEBUG-PAGE
restarts, instead of showing the debug page. Only for requests from this
machine, and only while an editor is connected."
  :environment '("SHISO_SERVER_REPL_DEBUGGER")
  :default nil)

;;; Tunables

(defvar *debug* :settings
  "NIL, T or :REPL. :SETTINGS (the default) reads :server/debugp and
:server/repl-debugger for each request. Global, not let-bound around the
server: Woo serves requests on its own thread, which doesn't see bindings
made in the thread that started it.")

(defvar *debug-404* t
  "In debug mode, show the routes tried on a 404 instead of the app's 404
page. Set to NIL to preview your own 404 page.")

(defvar *log-client-errors* :internal-referer
  "Which 4xx responses are logged, one line each, no backtrace:
NIL for none, :INTERNAL-REFERER for 404s linked from this site (a broken
link of your own), T for every 4xx. 5xx are always logged.")

(defvar *static-error-root* nil
  "Directory with <status>.html, 4xx.html and 5xx.html, served when an error
page itself fails. NIL means errors/ under the project's static/ directory.")

(defvar *prefer-static-5xx* nil
  "When true, 5xx HTML responses use the static files directly, without
calling the dynamic error page.")

(defvar *allowed-methods* nil
  "Methods some route accepts for the current path, collected by modules on a
miss so that the application's fallback can answer 405 instead of 404.
Bound per request by DEFINE-APPLICATION's app.")

(defvar *route-describer* nil
  "Function of a mount list ((prefix . module-keyword) ...) returning rows
(:pattern :methods :name) for the debug 404 page. Set by shiso/routing, which
loads after this file.")

(defvar *render-around* (lambda (env thunk) (declare (ignore env)) (funcall thunk))
  "Function of ENV and THUNK that error pages render inside. shiso/server sets
it to bind the request's locale, which isn't bound out here.")

(defvar *fragment-p* nil
  "True while an error page renders for an HTMX request: the page function
may return just the inner content.")

(defvar *request-failure* nil
  "(condition backtrace) of the error the :repl debugger is showing.")

;;; Conditions

(define-condition http-error (error)
  ((status :initarg :status :reader http-error-status)
   (message :initarg :message :initform nil :reader http-error-message)
   (headers :initarg :headers :initform nil :reader http-error-headers)
   ;; The original condition, when a foreign condition was mapped to a status.
   (cause :initarg :cause :initform nil :reader http-error-cause)
   ;; RFC 9457 problem type URI; NIL renders as about:blank.
   (problem-type :initarg :type :initform nil :reader http-error-type))
  (:report (lambda (c s)
             (format s "HTTP ~D~@[: ~A~]" (http-error-status c) (http-error-message c)))))

(define-condition http-client-error (http-error) ())
(define-condition http-server-error (http-error) ())

(define-condition bad-request (http-client-error) () (:default-initargs :status 400))
(define-condition unauthorized (http-client-error) () (:default-initargs :status 401))
(define-condition forbidden (http-client-error) () (:default-initargs :status 403))

(define-condition not-found (http-client-error)
  ;; Set only by DEFINE-APPLICATION's fallback: ((prefix . module-keyword) ...)
  ;; in mount order, for the debug 404 page's list of routes tried.
  ((mounts :initarg :mounts :initform nil :reader not-found-mounts))
  (:default-initargs :status 404))

(define-condition method-not-allowed (http-client-error)
  ((allowed :initarg :allowed :initform nil :reader allowed-methods))
  (:default-initargs :status 405))

(define-condition internal-server-error (http-server-error) ()
  (:default-initargs :status 500))

(defun status-condition-class (status)
  (case status
    (400 'bad-request)
    (401 'unauthorized)
    (403 'forbidden)
    (404 'not-found)
    (405 'method-not-allowed)
    (500 'internal-server-error)
    (t (if (< status 500) 'http-client-error 'http-server-error))))

(defun abort-with (status &rest initargs &key message headers allowed type)
  "Signal the HTTP error for STATUS (400-599). MESSAGE is shown on the default
page and as the JSON detail; HEADERS are added to the response; ALLOWED is the
methods for a 405's Allow header; TYPE is an RFC 9457 problem type URI."
  (declare (ignore message headers type))
  (check-type status (integer 400 599))
  (let ((class (status-condition-class status)))
    (unless (eq class 'method-not-allowed)
      (setf initargs (copy-list initargs))
      (remf initargs :allowed))
    (when (and allowed (not (eq class 'method-not-allowed)))
      (warn "ABORT-WITH ~D ignores :ALLOWED; only 405 has an Allow header." status))
    (apply #'error class :status status initargs)))

;;; Mapping other conditions to statuses (Rails' rescue_responses, Phoenix's
;;; Plug.Exception): methods on a generic function. Shiso ships none beyond
;;; HTTP-ERROR's own.

(defgeneric condition-http-status (condition)
  (:documentation "The HTTP status (400-599) CONDITION should produce, or NIL
when it is unexpected: logged with its backtrace, then a 500 page, the debug
page or the debugger. Add methods for conditions your application expects:
  (defmethod s:condition-http-status ((c billing:quota-exceeded)) 429)")
  (:method ((c condition)) nil)
  (:method ((c http-error)) (http-error-status c)))

(defun http-error-for (c status)
  "Wrap foreign condition C. No :message: its report text may leak internals."
  (make-condition (status-condition-class status) :status status :cause c))

;;; The registry

(defvar *error-pages* (make-hash-table :test 'eql)
  "Keys: an integer status, :4XX, :5XX or T. Values: functions of the
condition returning an HTML string, an almighty-html node, or a full Clack
response list.")

(defmacro define-error-page (key (condition-var) &body body)
  "Define the page for KEY: a status like 404, :4XX or :5XX for a class, or T
for every error. BODY sees the HTTP-ERROR as CONDITION-VAR and returns an HTML
string, an almighty-html node or a Clack response list. Looked up per request,
so re-evaluating the form takes effect at once."
  (unless (or (typep key '(integer 400 599)) (member key '(:4xx :5xx t)))
    (error "DEFINE-ERROR-PAGE key must be a status 400-599, :4XX, :5XX or T, not ~S." key))
  `(progn
     (setf (gethash ',key *error-pages*)
           (lambda (,condition-var)
             (declare (ignorable ,condition-var))
             ,@body))
     ',key))

(defun remove-error-page (key)
  (remhash key *error-pages*))

(defun find-error-page (status)
  "Exact status, then its class (:4XX or :5XX), then T, then the default."
  (or (gethash status *error-pages*)
      (gethash (if (< status 500) :4xx :5xx) *error-pages*)
      (gethash t *error-pages*)
      #'default-error-page))

;;; The request

(defun request-header (env name)
  "Header NAME (lowercase) of ENV, or NIL. ENV may be NIL."
  (let ((headers (and env (getf env :headers))))
    (and (hash-table-p headers) (gethash name headers))))

(defun request-path (env)
  (let* ((uri (or (getf env :request-uri) (getf env :path-info) "/"))
         (end (position #\? uri)))
    (subseq uri 0 end)))

(defun response-kind (env)
  ":JSON, :FRAGMENT (HTMX) or :HTML. A substring check, not full Accept
negotiation: browsers send text/html, API clients application/json."
  (let ((accept (or (request-header env "accept") "")))
    (cond ((request-header env "hx-request") :fragment)
          ;; "application/problem+json" doesn't contain "application/json".
          ((and (or (search "application/json" accept)
                    (search "application/problem+json" accept))
                (not (search "text/html" accept)))
           :json)
          (t :html))))

(defun local-request-p (env)
  "True only for a request made directly from this machine. One that came
through a proxy (X-Forwarded-For or Forwarded) is not local even though its
address is loopback, as with nginx on the same host. A client can only make
a request less local by adding headers, so debug output can't be forced."
  (and env
       (member (getf env :remote-addr) '("127.0.0.1" "::1" "0:0:0:0:0:0:0:1")
               :test #'equal)
       (not (request-header env "x-forwarded-for"))
       (not (request-header env "forwarded"))
       t))

(defun debug-mode ()
  "NIL, T or :REPL for the current request."
  (if (eq *debug* :settings)
      (and (ignore-errors (settei:setting :server/debugp))
           (if (ignore-errors (settei:setting :server/repl-debugger)) :repl t))
      *debug*))

(defun editor-connected-p ()
  "True when SLY (Slynk) or SLIME (Swank) has a connection, so that the
debugger reaches the editor. Without one, INVOKE-DEBUGGER on Woo's thread
would wait on the terminal."
  (flet ((connected (package)
           (let ((fn (and (find-package package)
                          (find-symbol "DEFAULT-CONNECTION" package))))
             (and fn (fboundp fn) (ignore-errors (funcall fn))))))
    (or (connected "SLYNK") (connected "SWANK"))))

;;; Logging

(defun log-timestamp ()
  "ISO-8601-ish UTC timestamp for log lines."
  (multiple-value-bind (s m h d mo y)
      (decode-universal-time (get-universal-time) 0)
    (format nil "~4,'0D-~2,'0D-~2,'0D ~2,'0D:~2,'0D:~2,'0DZ" y mo d h m s)))

(defun write-log (text)
  "Write TEXT to *ERROR-OUTPUT* (journald under systemd), with secret
settings' values masked."
  (ignore-errors
   (write-string (or (ignore-errors (settei:redact text)) text) *error-output*)
   (force-output *error-output*)))

(defun trim-backtrace (text)
  "TEXT without the frames above the signal: printing the backtrace and this
middleware's handler. Keeps the header line; unchanged if no signal frame."
  (let* ((lines (uiop:split-string text :separator '(#\Newline)))
         (signal (position-if (lambda (line) (search "::%SIGNAL " line)) lines)))
    (if signal
        (format nil "~A~%~{~A~^~%~}" (first lines) (nthcdr (1+ signal) lines))
        text)))

(defun backtrace-string (c)
  (or (ignore-errors
       (trim-backtrace
        (with-output-to-string (s)
          (uiop:print-condition-backtrace c :stream s))))
      ""))

(defun log-error (c env &optional backtrace note)
  "Log an unexpected error C: timestamp, method, URI, the condition and its
BACKTRACE. Never the env: it holds the session cookie and CSRF token."
  (write-log (format nil "~&[~A] ERROR ~A ~A~@[ (~A)~]~%  ~A~%~@[~A~%~]"
                     (log-timestamp)
                     (getf env :request-method) (getf env :request-uri)
                     note c backtrace)))

(defun same-site-referer-p (env)
  (let ((referer (request-header env "referer"))
        (host (request-header env "host")))
    (when (and referer host)
      (let* ((start (let ((p (search "://" referer))) (if p (+ p 3) 0)))
             (end (position #\/ referer :start start)))
        (string-equal host (subseq referer start end))))))

(defun log-client-error (c env)
  "One line for an expected error, by *LOG-CLIENT-ERRORS*; mapped 5xx always."
  (let ((status (http-error-status c)))
    (when (or (>= status 500)
              (eq *log-client-errors* t)
              (and (eq *log-client-errors* :internal-referer)
                   (= status 404)
                   (same-site-referer-p env)))
      (write-log (format nil "~&[~A] ~:[~;ERROR ~]~D ~A ~A~@[ referer=~A~]~@[ (~A)~]~%"
                         (log-timestamp) (>= status 500) status
                         (getf env :request-method) (getf env :request-uri)
                         (request-header env "referer")
                         (http-error-cause c))))))

;;; Rendering

(defparameter +reason-phrases+
  '((400 . "Bad Request") (401 . "Unauthorized") (402 . "Payment Required")
    (403 . "Forbidden") (404 . "Not Found") (405 . "Method Not Allowed")
    (406 . "Not Acceptable") (408 . "Request Timeout") (409 . "Conflict")
    (410 . "Gone") (411 . "Length Required") (412 . "Precondition Failed")
    (413 . "Content Too Large") (414 . "URI Too Long")
    (415 . "Unsupported Media Type") (418 . "I'm a teapot")
    (422 . "Unprocessable Content") (425 . "Too Early") (428 . "Precondition Required")
    (429 . "Too Many Requests") (431 . "Request Header Fields Too Large")
    (451 . "Unavailable For Legal Reasons")
    (500 . "Internal Server Error") (501 . "Not Implemented") (502 . "Bad Gateway")
    (503 . "Service Unavailable") (504 . "Gateway Timeout")))

(defun reason-phrase (status)
  "The standard reason phrase for STATUS: \"Not Found\" for 404."
  (or (cdr (assoc status +reason-phrases+))
      (if (< status 500) "Client Error" "Server Error")))

(defparameter *page-css* "
body { font-family: system-ui, sans-serif; max-width: 48rem; margin: 3rem auto; padding: 0 1rem; color: #222; }
h1 { font-size: 1.6rem; }
.status { color: #888; font-weight: normal; }
pre { background: #f5f5f5; padding: 0.75rem; overflow-x: auto; font-size: 0.85rem; }
table { border-collapse: collapse; width: 100%; font-size: 0.9rem; }
td, th { text-align: left; padding: 0.3rem 0.5rem; border-bottom: 1px solid #ddd; }
code { font-size: 0.9em; }
.note { color: #666; font-size: 0.9rem; border-top: 1px solid #ddd; padding-top: 0.75rem; margin-top: 2rem; }
@media (prefers-color-scheme: dark) {
  body { background: #161616; color: #ddd; }
  pre { background: #222; }
  td, th { border-color: #333; }
}
")

(defun page (title &rest body)
  "A full HTML page around BODY nodes. Strings in BODY are escaped."
  (ah:render-to-string
   (ah:</>
    (html :lang "en"
      (head
        (meta :charset "utf-8")
        (meta :name "viewport" :content "width=device-width, initial-scale=1")
        (title title)
        (style (raw! *page-css*)))
      (body body)))))

(defun default-error-page (c)
  "The built-in page: status, reason and the message for 4xx."
  (let* ((status (http-error-status c))
         (heading (format nil "~D ~A" status (reason-phrase status)))
         (message (and (< status 500) (http-error-message c))))
    (if *fragment-p*
        (ah:render-to-string
         (ah:</> (div :class "error"
                   (h1 heading)
                   (when message (ah:</> (p message))))))
        (page heading
              (ah:</> (h1 heading))
              (when message (ah:</> (p message)))))))

(defun json-escape (string)
  (with-output-to-string (out)
    (loop for ch across string
          do (case ch
               (#\" (write-string "\\\"" out))
               (#\\ (write-string "\\\\" out))
               (#\Newline (write-string "\\n" out))
               (#\Return (write-string "\\r" out))
               (#\Tab (write-string "\\t" out))
               (t (if (< (char-code ch) 32)
                      (format out "\\u~4,'0X" (char-code ch))
                      (write-char ch out)))))))

(defun extra-headers (c)
  (append (http-error-headers c)
          (when (and (typep c 'method-not-allowed) (allowed-methods c))
            (list :allow (format nil "~{~A~^, ~}" (allowed-methods c))))))

(defun problem-json-response (c &optional detail)
  "RFC 9457 problem details. Title is always the reason phrase (as the RFC
asks for type about:blank); app text goes in detail, never for 5xx."
  (let* ((status (http-error-status c))
         (detail (or detail (and (< status 500) (http-error-message c)))))
    (list status
          (append (list :content-type "application/problem+json; charset=utf-8")
                  (extra-headers c))
          (list (format nil "{\"type\":\"~A\",\"title\":\"~A\",\"status\":~D~@[,\"detail\":\"~A\"~]}"
                        (json-escape (or (http-error-type c) "about:blank"))
                        (json-escape (reason-phrase status))
                        status
                        (and detail (json-escape (princ-to-string detail))))))))

(defun coerce-page-result (status result c)
  "A page function's RESULT as a Clack response: a response list as it is, a
string as the body, an almighty-html node rendered; NIL means the default page."
  (cond ((and (consp result) (integerp (first result))) result)
        (t (list status
                 (append (list :content-type "text/html; charset=utf-8") (extra-headers c))
                 (list (cond ((null result) (default-error-page c))
                             ((stringp result) result)
                             (t (ah:render-to-string result))))))))

(defun plain-fallback (status &optional c)
  (list status
        (append (list :content-type "text/plain; charset=utf-8")
                (and c (ignore-errors (extra-headers c))))
        (list (format nil "~D ~A" status (reason-phrase status)))))

(defun static-error-root ()
  (or *static-error-root*
      (merge-pathnames "errors/" (static:project-static-root))))

(defun static-error-response (status &optional c)
  "A response serving <status>.html, else 4xx.html or 5xx.html, from the
static error directory, or NIL when there is none. Read per request, so
editing the file takes effect at once."
  (let* ((root (static-error-root))
         (file (find-if #'uiop:file-exists-p
                        (list (merge-pathnames (format nil "~D.html" status) root)
                              (merge-pathnames (if (< status 500) "4xx.html" "5xx.html")
                                               root)))))
    (when file
      (list status
            (append (list :content-type "text/html; charset=utf-8")
                    (and c (extra-headers c)))
            file))))

(defun debug-404-p (c env)
  (and (debug-mode) *debug-404* (local-request-p env)
       (typep c 'not-found) (eq (response-kind env) :html)))

(defun debug-note (text)
  (ah:</> (p :class "note" text)))

(defun debug-404-response (c env)
  "Django's technical 404: what the router tried, in order."
  (let* ((mounts (not-found-mounts c))
         (rows (and mounts *route-describer*
                    (ignore-errors (funcall *route-describer* mounts))))
         (path (request-path env)))
    (list 404 '(:content-type "text/html; charset=utf-8")
          (list
           (page "404 Not Found"
                 (ah:</> (h1 "404 Not Found " (span :class "status" "(debug)")))
                 (ah:</> (p "Request: " (code (format nil "~A ~A" (getf env :request-method) path))))
                 (if mounts
                     (ah:</>
                      (div
                        (p "Shiso tried these URL patterns, in this order:")
                        (table
                          (thead (tr (th "Pattern") (th "Methods") (th "Name")))
                          (tbody
                            (loop for row in rows
                                  collect (ah:</>
                                           (tr (td (code (getf row :pattern)))
                                               (td (format nil "~{~A~^, ~}" (getf row :methods)))
                                               (td (or (getf row :name) "")))))))
                        (p "The path " (code path) " didn't match any of these.")))
                     (ah:</>
                      (p "Raised by the application"
                         (if (http-error-message c)
                             (format nil ": ~A" (http-error-message c))
                             "."))))
                 (debug-note "You're seeing this because debug mode is on and the request came from this machine. Set shiso:*debug-404* to NIL to preview your own 404 page."))))))

(defun debug-page-response (c backtrace env)
  "The debug 500 page: the condition, its backtrace and the request line.
Never the env: it holds the session cookie and CSRF token."
  (if (eq (response-kind env) :json)
      (problem-json-response (make-condition 'internal-server-error)
                             (format nil "~A: ~A" (type-of c) c))
      (list 500 '(:content-type "text/html; charset=utf-8")
            (list
             (page "500 Internal Server Error"
                   (ah:</> (h1 "500 Internal Server Error " (span :class "status" "(debug)")))
                   (ah:</> (p (code (format nil "~A ~A"
                                            (getf env :request-method) (getf env :request-uri)))))
                   (ah:</> (h2 (princ-to-string (type-of c))))
                   (ah:</> (pre (or (ignore-errors (princ-to-string c)) "(unprintable condition)")))
                   (ah:</> (h2 "Backtrace"))
                   (ah:</> (pre (or backtrace "")))
                   (debug-note "You're seeing this because debug mode is on and the request came from this machine. With :server/repl-debugger on and SLY or SLIME connected, this error would open the debugger instead, with a RETRY-REQUEST restart."))))))

(defun html-error-response (c env)
  (let ((status (http-error-status c)))
    (cond ((and (>= status 500) *prefer-static-5xx* (static-error-response status c)))
          ((debug-404-p c env) (debug-404-response c env))
          (t (let ((*fragment-p* (eq (response-kind env) :fragment)))
               (coerce-page-result status (funcall (find-error-page status) c) c))))))

(defun finish-response (response env)
  "HEAD gets the headers without a body."
  (if (and (eq (getf env :request-method) :head) (consp response))
      (list (first response) (second response) '())
      response))

(defun render-error-response (c env)
  "Turn HTTP-ERROR C into a Clack response for ENV (which may be NIL).
Never signals: if the error page fails, the static file, then plain text."
  (let ((status (http-error-status c)))
    (finish-response
     (block render
       (handler-bind
           ((error (lambda (e)
                     (log-error e env (backtrace-string e) "error page itself failed")
                     (return-from render
                       (or (ignore-errors (static-error-response status c))
                           (plain-fallback status c))))))
         (funcall *render-around* env
                  (lambda ()
                    (ecase (response-kind env)
                      (:json (problem-json-response c))
                      ((:html :fragment) (html-error-response c env)))))))
     env)))

(defvar *in-error-middleware* nil
  "True inside WRAP-HTTP-ERRORS.")

(defun signal-or-render (c env)
  "Signal C for WRAP-HTTP-ERRORS to answer, or, outside it (a test calling the
app directly, say), render C's page here. A flag rather than SIGNAL's return:
any outer handler on ERROR, like a test framework's, would take the signal."
  (if *in-error-middleware*
      (error c)
      (render-error-response c env)))

;;; The middleware

(defun call-with-error-pages (app env mode)
  "Call APP; turn whatever error escapes it into a response. Handlers run
before unwinding (backtrace intact, debugger possible); the response is
rendered after, so a request transaction has rolled back and the page may
use the database."
  (destructuring-bind (kind c &optional backtrace)
      (block request
        (handler-bind
            ((error
               (lambda (c)
                 (let ((status (ignore-errors (condition-http-status c))))
                   (if (typep status '(integer 400 599))
                       ;; Expected: an http-error, or a condition mapped to a status.
                       (return-from request
                         (list :http (if (typep c 'http-error) c (http-error-for c status))))
                       ;; Unexpected.
                       (let ((bt (backtrace-string c)))
                         (log-error c env bt)
                         (when (eq mode :repl)
                           ;; Never returns: the developer picks a restart.
                           (setf *request-failure* (list c bt))
                           (invoke-debugger c))
                         (return-from request (list :unexpected c bt))))))))
          (return-from call-with-error-pages (funcall app env))))
    (ecase kind
      (:http
       (ignore-errors (log-client-error c env))
       (render-error-response c env))
      (:unexpected
       (if (and mode (local-request-p env))
           (finish-response
            (handler-case (debug-page-response c backtrace env)
              (error () (plain-fallback 500)))
            env)
           (render-error-response (make-condition 'internal-server-error :cause c) env))))))

(defun snapshot-raw-body (env)
  "The request body as octets, read once, so that each retry can read it."
  (let ((stream (getf env :raw-body))
        (length (getf env :content-length)))
    (when stream
      (if (and (integerp length) (plusp length))
          (let* ((buffer (make-array length :element-type '(unsigned-byte 8)))
                 (end (read-sequence buffer stream)))
            (subseq buffer 0 end))
          (let ((out (make-array 0 :element-type '(unsigned-byte 8)
                                   :adjustable t :fill-pointer 0)))
            (loop for byte = (read-byte stream nil nil)
                  while byte do (vector-push-extend byte out))
            (coerce out '(simple-array (unsigned-byte 8) (*))))))))

(defun fresh-env (env body)
  "A copy of ENV with a new stream over BODY. A copy, because lack/request
changes the env it's given (it wraps :raw-body and appends :body-parameters),
and a retry must start from the request as it came."
  (let ((copy (loop for (key value) on env by #'cddr
                    unless (eq key :raw-body) append (list key value))))
    (if body
        (list* :raw-body (flex:make-in-memory-input-stream body) copy)
        copy)))

(defun call-with-retry (app env mode)
  "The :repl mode: restarts around the whole request. After fixing and
recompiling the code, RETRY-REQUEST runs the request again; its database
writes from the failed attempt were rolled back on the way out."
  (let ((body (snapshot-raw-body env))
        (*request-failure* nil))
    (loop
      (restart-case
          (let ((*allowed-methods* nil))
            (return (call-with-error-pages app (fresh-env env body) mode)))
        (retry-request ()
          :report (lambda (s)
                    (format s "Retry ~A ~A" (getf env :request-method) (getf env :request-uri)))
          nil)
        (show-debug-page ()
          :report "Send the debug page to the browser"
          (return (destructuring-bind (c bt) *request-failure*
                    (finish-response
                     (handler-case (debug-page-response c bt env)
                       (error () (plain-fallback 500)))
                     env))))
        (show-error-page ()
          :report "Send the normal 500 page to the browser"
          (return (render-error-response (make-condition 'internal-server-error) env)))))))

(defun wrap-http-errors (app)
  "Outermost middleware: every error in a request becomes a response.
HTTP errors and mapped conditions get their error page; anything else is
logged with its backtrace, then gets the 500 page, or, in debug mode for a
request from this machine, the debug page or (:server/repl-debugger) the
Lisp debugger. Errors inside a streaming body happen after this returns and
aren't caught here."
  (lambda (env)
    (block last-resort
      (handler-bind
          ((error (lambda (c)
                    ;; Only reached if the error machinery itself failed.
                    (ignore-errors
                     (log-error c env (backtrace-string c) "error handler itself failed"))
                    (return-from last-resort (plain-fallback 500)))))
        (let ((mode (debug-mode))
              (*allowed-methods* nil)
              (*in-error-middleware* t))
          (when (and (eq mode :repl)
                     (not (and (local-request-p env) (editor-connected-p))))
            (setf mode t))
          (if (eq mode :repl)
              (call-with-retry app env mode)
              (call-with-error-pages app env mode)))))))
