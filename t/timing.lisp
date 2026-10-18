(defpackage #:shiso/t/timing
  (:use #:cl #:lisp-unit2)
  (:local-nicknames (#:errors #:shiso/errors)
                    (#:timing #:shiso/timing)
                    (#:routing #:shiso/routing)
                    (#:server #:shiso/server)
                    (#:database #:shiso/database)))

(in-package #:shiso/t/timing)

;;; Helpers -------------------------------------------------------------------

(defun make-env (method path &key (remote-addr "127.0.0.1") headers)
  "A Lack env for PATH, which may carry a query string."
  (let ((h (make-hash-table :test 'equal)))
    (setf (gethash "accept" h) "text/html"
          (gethash "host" h) "localhost:5000")
    (loop for (name value) on headers by #'cddr
          do (setf (gethash name h) value))
    (list :request-method method
          :request-uri path
          :path-info (subseq path 0 (position #\? path))
          :script-name ""
          :query-string nil
          :server-name "localhost"
          :server-port 5000
          :server-protocol :http/1.1
          :url-scheme "http"
          :remote-addr remote-addr
          :remote-port 12345
          :headers h
          :raw-body (flex:make-in-memory-input-stream #()))))

(defun header (response name) (getf (second response) name))

(defvar *log* nil)

(defmacro with-timing-state ((&rest settings) &body body)
  "Fresh routes and modules, debug off, the access log captured, and
SETTINGS (name value ...) on top of quiet defaults."
  (let ((saved-routes (gensym)) (saved-modules (gensym)))
    `(let ((,saved-routes shiso:*routes*)
           (,saved-modules (alexandria:copy-hash-table shiso:*module-registry*))
           (errors:*debug* nil)
           (errors:*log-client-errors* nil)
           (*log* (make-string-output-stream)))
       (clrhash shiso:*module-registry*)
       (setf shiso:*routes* (make-instance 'shiso:routes :mapper (myway:make-mapper)))
       (unwind-protect
            (let ((timing:*access-log-stream* *log*)
                  (*error-output* (make-broadcast-stream)))
              (shiso:with-settings (:server/timing-header :total
                                    :server/access-log :logfmt
                                    :server/slow-request-ms 0
                                    ,@settings)
                ,@body))
         (setf shiso:*module-registry* ,saved-modules
               shiso:*routes* ,saved-routes)))))

(defun log-text () (get-output-stream-string *log*))

(defun timed (handler)
  "HANDLER, a function of ENV, inside the timing and error middleware."
  (timing:wrap-request-timing (errors:wrap-http-errors handler)))

(defmacro with-memory-db (&body body)
  `(let ((saved mito:*connection*))
     (unwind-protect
          (progn
            (setf mito:*connection* (dbi:connect :sqlite3 :database-name ":memory:"))
            (let ((mito:*mito-logger-stream* nil))
              ,@body))
       (ignore-errors (dbi:disconnect mito:*connection*))
       (setf mito:*connection* saved))))

(defun query-one (sql)
  (second (first (mito:retrieve-by-sql sql))))

(defparameter +page+ '(200 (:content-type "text/html") ("<p>page</p>")))

;;; Server-Timing -------------------------------------------------------------------------------------

(define-test total-only-by-default ()
  (with-timing-state ()
    (let ((value (header (funcall (timed (lambda (env) (declare (ignore env)) +page+))
                                  (make-env :get "/"))
                         :server-timing)))
      (assert-true (eql 0 (search "total;dur=" value)))
      (assert-false (search "db;" value)))))

(define-test full-shows-database-gc-and-phases ()
  (with-timing-state (:server/timing-header :full)
    (with-memory-db
      (let ((value (header (funcall (timed (lambda (env)
                                             (declare (ignore env))
                                             (shiso:with-timing (:render)
                                               (query-one "SELECT 1 AS n")
                                               (query-one "SELECT 2 AS n"))
                                             +page+))
                                    (make-env :get "/"))
                           :server-timing)))
        (assert-true (search "db;dur=" value))
        (assert-true (search "desc=\"2 queries\"" value))
        (assert-true (search "gc;dur=" value))
        (assert-true (search "render;dur=" value))))))

(define-test off-sends-no-header ()
  (with-timing-state (:server/timing-header :off)
    (assert-false (header (funcall (timed (lambda (env) (declare (ignore env)) +page+))
                                   (make-env :get "/"))
                          :server-timing))))

(define-test debug-mode-shows-full-timing-to-this-machine-only ()
  (with-timing-state ()
    (let ((errors:*debug* t)
          (app (timed (lambda (env) (declare (ignore env)) +page+))))
      (assert-true (search "db;" (header (funcall app (make-env :get "/")) :server-timing)))
      (assert-false (search "db;" (header (funcall app (make-env :get "/" :headers '("x-forwarded-for" "203.0.113.9")))
                                          :server-timing)))
      (assert-false (search "db;" (header (funcall app (make-env :get "/" :remote-addr "203.0.113.9"))
                                          :server-timing))))))

(define-test an-existing-server-timing-header-is-kept ()
  (with-timing-state ()
    (let* ((literal '(200 (:server-timing "app;dur=3" :content-type "text/plain") ("x")))
           (response (funcall (timed (lambda (env) (declare (ignore env)) literal))
                              (make-env :get "/"))))
      (assert-true (eql 0 (search "app;dur=3, total;dur=" (header response :server-timing))))
      (assert-equal "text/plain" (header response :content-type))
      ;; The controller's literal is untouched.
      (assert-equal '(:server-timing "app;dur=3" :content-type "text/plain") (second literal)))))

(define-test delayed-responses-are-timed ()
  (with-timing-state ()
    (let* ((app (timed (lambda (env)
                         (declare (ignore env))
                         (lambda (responder) (funcall responder +page+)))))
           (delayed (funcall app (make-env :get "/")))
           (got nil))
      (assert-true (functionp delayed))
      (funcall delayed (lambda (response) (setf got response)))
      (assert-true (search "total;dur=" (header got :server-timing)))
      (assert-true (search "status=200" (log-text))))))

(define-test with-timing-outside-a-request-runs-its-body ()
  (assert-eql 3 (shiso:with-timing (:anything) (+ 1 2))))

(define-test phase-names-are-tokens ()
  (assert-equal "render-page" (timing::phase-name "Render page"))
  (assert-equal "db_cache" (timing::phase-name :db_cache)))

;;; The access log ------------------------------------------------------------------------------------

(define-test access-log-line-has-route-status-and-time ()
  (with-timing-state ()
    (eval '(shiso:define-module timing-demo
            (:urls (:GET "/hello" (lambda () '(200 (:content-type "text/plain") ("hi"))) "hello"))))
    (let* ((app (timed (symbol-value (eval '(shiso:define-application timing-test-app ()
                                              (:modules ("" timing-demo)))))))
           (response (funcall app (make-env :get "/hello?token=secret")))
           (line (log-text)))
      (assert-eql 200 (first response))
      (assert-true (search "method=GET path=/hello status=200 ms=" line))
      (assert-true (search "route=timing-demo:hello" line))
      (assert-true (search "bytes=2" line))
      (assert-false (search "secret" line)))))

(define-test access-log-quotes-odd-values ()
  (assert-equal "\"/a b\"" (timing::logfmt-value "/a b"))
  (assert-equal "\"say \\\"hi\\\"\"" (timing::logfmt-value "say \"hi\""))
  (assert-equal "/plain" (timing::logfmt-value "/plain")))

(define-test access-log-as-json ()
  (with-timing-state (:server/access-log :json)
    (funcall (timed (lambda (env) (declare (ignore env)) +page+)) (make-env :get "/x"))
    (let ((line (log-text)))
      (assert-true (eql 0 (search "{\"time\":" line)))
      (assert-true (search "\"status\":200" line))
      (assert-true (search "\"path\":\"/x\"" line)))))

(define-test access-log-off ()
  (with-timing-state (:server/access-log :off)
    (funcall (timed (lambda (env) (declare (ignore env)) +page+)) (make-env :get "/x"))
    (assert-equal "" (log-text))))

(define-test error-responses-are-logged-with-their-status ()
  (with-timing-state ()
    (funcall (timed (lambda (env) (declare (ignore env)) (shiso:abort-with 403)))
             (make-env :get "/private"))
    (assert-true (search "path=/private status=403" (log-text)))))

(define-test slow-requests-log-their-sql ()
  (with-timing-state (:server/slow-request-ms 5)
    (with-memory-db
      (funcall (timed (lambda (env)
                        (declare (ignore env))
                        (query-one "SELECT 42 AS answer")
                        (sleep 0.02)
                        +page+))
               (make-env :get "/slow"))
      (let ((text (log-text)))
        (assert-true (search "slow request: GET /slow took" text))
        (assert-true (search "SELECT 42 AS answer" text))))))

(define-test repeated-queries-warn-in-debug-mode ()
  (with-timing-state ()
    (with-memory-db
      (let ((handler (lambda (env)
                       (declare (ignore env))
                       (dotimes (i 12) (mito:retrieve-by-sql "SELECT ? AS n" :binds (list i)))
                       +page+)))
        (funcall (timed handler) (make-env :get "/list"))
        (assert-false (search "repeated query" (log-text)))
        (let ((errors:*debug* t))
          (funcall (timed handler) (make-env :get "/list"))
          (assert-true (search "repeated query: 12 times in GET /list: SELECT ? AS n" (log-text))))))))

;;; Sessionless mounts ---------------------------------------------------------------------------------

(defvar *seen* nil)

(defun session-count ()
  (getf (first (mito:retrieve-by-sql "SELECT COUNT(*) AS n FROM shiso_session")) :n))

(define-test sessionless-mounts-get-no-session ()
  (with-timing-state ()
    (with-memory-db
      (shiso:ensure-session-table)
      (eval '(shiso:define-module timing-files
              (:urls (:GET "/:name" (lambda (name)
                                      (declare (ignore name))
                                      (push (list :session (shiso:current-session-hash)
                                                  :token (shiso:csrf-token-value))
                                            *seen*)
                                      '(200 (:content-type "image/jpeg") ("jpeg")))
                      "file"))))
      (eval '(shiso:define-module timing-pages
              (:urls (:GET "/form" (lambda ()
                                     (push (list :token (shiso:csrf-token-value)) *seen*)
                                     '(200 (:content-type "text/html") ("form")))
                      "form"))))
      (let* ((*seen* nil)
             (app (server::wrap-app
                   (symbol-value (eval '(shiso:define-application timing-mount-app ()
                                         (:modules ("/media" timing-files :sessions nil)
                                                   ("" timing-pages)))))))
             (file (funcall app (make-env :get "/media/a.jpg"))))
        (assert-eql 200 (first file))
        (assert-false (header file :set-cookie))
        (assert-false (getf (first *seen*) :session))
        (assert-false (getf (first *seen*) :token))
        (assert-eql 0 (session-count))
        ;; Other mounts keep their sessions.
        (let ((form (funcall app (make-env :get "/form"))))
          (assert-true (getf (first *seen*) :token))
          (assert-true (search "lack.session=" (header form :set-cookie)))
          (assert-eql 1 (session-count)))))))

(define-test static-files-get-no-session ()
  (assert-true (server::sessionless-path-p "/static/home/base.css" nil))
  (assert-true (server::sessionless-path-p "/media" '("/media")))
  (assert-true (server::sessionless-path-p "/media/1/a.jpg" '("/media")))
  (assert-false (server::sessionless-path-p "/mediakit" '("/media")))
  (assert-false (server::sessionless-path-p "/" '("/media")))
  (assert-false (server::sessionless-path-p "/statics" nil)))

(define-test a-root-mount-cannot-be-sessionless ()
  (assert-error 'error (routing::parse-mount '("" pages :sessions nil)))
  (assert-equal '("/media" files nil) (routing::parse-mount '("/media" files :sessions nil)))
  (assert-equal '("" pages t) (routing::parse-mount '("" pages))))

;;; SQLite pragmas -------------------------------------------------------------------------------------

(define-test sqlite-connections-get-the-pragmas ()
  (with-memory-db
    (shiso:with-settings ()
      (database::apply-sqlite-pragmas))
    (assert-eql 5000 (query-one "PRAGMA busy_timeout"))
    (assert-eql 1 (query-one "PRAGMA synchronous"))   ; NORMAL
    (assert-eql 2 (query-one "PRAGMA temp_store"))))  ; MEMORY

(define-test sqlite-pragmas-must-be-name-value ()
  (assert-error 'shiso:setting-invalid
                (shiso:with-settings (:database/sqlite-pragmas '("busy_timeout=1; DROP TABLE x"))
                  nil)))
