(defpackage #:shiso/t/errors
  (:use #:cl #:lisp-unit2)
  (:local-nicknames (#:errors #:shiso/errors)
                    (#:routing #:shiso/routing)
                    (#:server #:shiso/server)))

(in-package #:shiso/t/errors)

;;; Helpers -------------------------------------------------------------------

(defun make-env (method path &key (accept "text/html") hx headers
                                  (remote-addr "127.0.0.1") body)
  "A Lack env for PATH. HEADERS is a plist of lowercase header names and values."
  (let ((h (make-hash-table :test 'equal))
        (octets (and body (flex:string-to-octets body :external-format :utf-8))))
    (setf (gethash "accept" h) accept
          (gethash "host" h) "localhost:5000")
    (when hx (setf (gethash "hx-request" h) "true"))
    (loop for (name value) on headers by #'cddr
          do (setf (gethash name h) value))
    (list :request-method method
          :request-uri path
          :path-info path
          :script-name ""
          :query-string nil
          :server-name "localhost"
          :server-port 5000
          :server-protocol :http/1.1
          :url-scheme "http"
          :remote-addr remote-addr
          :remote-port 12345
          :headers h
          :content-type (and body "application/x-www-form-urlencoded")
          :content-length (and body (length octets))
          :raw-body (flex:make-in-memory-input-stream (or octets #())))))

(defun status (response) (first response))
(defun header (response name) (getf (second response) name))

(defun body (response)
  (let ((b (third response)))
    (if (listp b) (format nil "~{~A~}" b) b)))

(defvar *log* nil "What the error middleware logged during the test.")

(defmacro with-error-state (&body body)
  "Fresh module registry, routes and error pages; debug off; logs captured."
  (let ((saved-routes (gensym)) (saved-modules (gensym)))
    `(let ((,saved-routes shiso:*routes*)
           (,saved-modules (alexandria:copy-hash-table shiso:*module-registry*))
           (errors:*error-pages* (make-hash-table :test 'eql))
           (errors:*debug* nil)
           (errors:*debug-404* t)
           (errors:*log-client-errors* nil)
           (errors:*prefer-static-5xx* nil)
           (errors:*static-error-root* #p"/nonexistent/shiso-errors/")
           (*log* (make-string-output-stream)))
       (clrhash shiso:*module-registry*)
       (setf shiso:*routes* (make-instance 'shiso:routes :mapper (myway:make-mapper)))
       (unwind-protect
            (let ((*error-output* *log*))
              ,@body)
         (setf shiso:*module-registry* ,saved-modules
               shiso:*routes* ,saved-routes)))))

(defun log-text () (get-output-stream-string *log*))

(defvar *things* nil "Test controllers' side channel.")

(defun make-app (module-form &rest more-module-forms)
  "Evaluate MODULE-FORMs, mount each module at its own prefix (the first at
\"\"), and wrap the application in the error middleware."
  (let* ((forms (cons module-form more-module-forms))
         (names (mapcar (lambda (form) (eval form)) forms))
         (mounts (loop for name in names
                       for i from 0
                       collect (list (if (zerop i) "" (format nil "/~(~A~)" name)) name)))
         (app-symbol (eval `(shiso:define-application errors-test-app ()
                              (:modules ,@mounts)))))
    (errors:wrap-http-errors (symbol-value app-symbol))))

(defun request (app method path &rest env-args)
  (funcall app (apply #'make-env method path env-args)))

(defparameter +basic-module+
  '(shiso:define-module err-basic
    (:urls (:GET "/" (lambda () (shiso:http-response "home")) "index")
           (:GET "/thing" (lambda () (shiso:http-response "thing")) "thing")
           ((:GET :POST) "/both" (lambda () (shiso:http-response "both")) "both")
           (:GET "/forbidden" (lambda () (shiso:abort-with 403 :message "Members only")) "forbidden")
           (:GET "/teapot" (lambda () (shiso:abort-with 418)) "teapot")
           (:GET "/unavailable" (lambda () (shiso:abort-with 503 :message "secret detail")) "unavailable")
           (:GET "/boom" (lambda () (error "kaboom in controller")) "boom")
           (:GET "/caught" (lambda ()
                             (handler-case (shiso:abort-with 404)
                               (shiso:not-found () (shiso:http-response "handled locally"))))
            "caught")
           (:GET "/things/<int:id>" (lambda (id) (shiso:http-response (format nil "int ~S" id))) "thing-by-id")
           ((:GET :POST) "/strict/<int:id>" (lambda (id) (shiso:http-response (format nil "strict ~S" id))) "strict"))))

;;; Status pages and the registry -----------------------------------------------

(define-test unknown-path-is-404-with-default-page ()
  (with-error-state
    (let ((r (request (make-app +basic-module+) :get "/nope")))
      (assert-eql 404 (status r))
      (assert-true (search "404 Not Found" (body r))))))

(define-test app-404-page-replaces-default ()
  (with-error-state
    (shiso:define-error-page 404 (c) (declare (ignore c)) "<p>custom missing</p>")
    (let ((r (request (make-app +basic-module+) :get "/nope")))
      (assert-eql 404 (status r))
      (assert-equal "<p>custom missing</p>" (body r)))))

(define-test class-page-and-catch-all-and-exact-precedence ()
  (with-error-state
    (let ((app (make-app +basic-module+)))
      (shiso:define-error-page t (c) (format nil "any ~D" (shiso:http-error-status c)))
      (assert-equal "any 403" (body (request app :get "/forbidden")))
      (shiso:define-error-page :4xx (c) (format nil "client ~D" (shiso:http-error-status c)))
      (assert-equal "client 403" (body (request app :get "/forbidden")))
      (shiso:define-error-page 403 (c) (format nil "exact ~A" (shiso:http-error-message c)))
      (assert-equal "exact Members only" (body (request app :get "/forbidden")))
      (assert-equal "client 418" (body (request app :get "/teapot"))))))

(define-test abort-with-message-shows-on-default-4xx-page-not-5xx ()
  (with-error-state
    (let ((app (make-app +basic-module+)))
      (let ((r (request app :get "/forbidden")))
        (assert-eql 403 (status r))
        (assert-true (search "Members only" (body r))))
      (let ((r (request app :get "/unavailable")))
        (assert-eql 503 (status r))
        (assert-false (search "secret detail" (body r)))))))

(define-test page-fn-may-return-a-clack-response ()
  (with-error-state
    (shiso:define-error-page 404 (c) (declare (ignore c)) '(302 (:location "/") ("")))
    (let ((r (request (make-app +basic-module+) :get "/nope")))
      (assert-eql 302 (status r))
      (assert-equal "/" (header r :location)))))

(define-test failing-page-falls-back-to-plain-text ()
  (with-error-state
    (shiso:define-error-page 404 (c) (declare (ignore c)) (error "page bug"))
    (let ((r (request (make-app +basic-module+) :get "/nope")))
      (assert-eql 404 (status r))
      (assert-equal "404 Not Found" (body r))
      (assert-true (search "error page itself failed" (log-text))))))

(define-test controller-handler-case-wins ()
  (with-error-state
    (let ((r (request (make-app +basic-module+) :get "/caught")))
      (assert-eql 200 (status r))
      (assert-equal "handled locally" (body r)))))

;;; 405, HEAD and OPTIONS ----------------------------------------------------------

(define-test wrong-method-is-405-with-allow ()
  (with-error-state
    (let ((r (request (make-app +basic-module+) :post "/thing")))
      (assert-eql 405 (status r))
      (assert-equal "GET, HEAD" (header r :allow)))))

(define-test allowed-methods-union-across-modules ()
  (with-error-state
    (let* ((app (make-app '(shiso:define-module err-one
                             (:urls (:GET "/x" (lambda () (shiso:http-response "one")) "x")))
                          '(shiso:define-module err-two
                             (:urls (:PUT "/x" (lambda () (shiso:http-response "two")) "x")))))
           ;; Both modules see "/x" only at their own mount; err-two is at /err-two.
           (r (request app :delete "/x")))
      (assert-eql 405 (status r))
      (assert-equal "GET, HEAD" (header r :allow))
      (let ((r2 (request app :post "/err-two/x")))
        (assert-eql 405 (status r2))
        (assert-equal "PUT" (header r2 :allow))))))

(define-test options-gets-204-with-allow ()
  (with-error-state
    (let ((r (request (make-app +basic-module+) :options "/both")))
      (assert-eql 204 (status r))
      (assert-true (search "POST" (header r :allow)))
      (assert-true (search "OPTIONS" (header r :allow))))))

(define-test head-serves-get-routes-and-empty-error-bodies ()
  (with-error-state
    (let ((app (make-app +basic-module+)))
      (assert-eql 200 (status (request app :head "/thing")))
      (let ((r (request app :head "/nope")))
        (assert-eql 404 (status r))
        (assert-equal '() (third r))))))

;;; Unexpected errors, logging and debug output ---------------------------------------

(define-test unexpected-error-is-logged-500-without-backtrace-in-body ()
  (with-error-state
    (let ((r (request (make-app +basic-module+) :get "/boom")))
      (assert-eql 500 (status r))
      (assert-false (search "kaboom" (body r)))
      (assert-false (search "Backtrace" (body r)))
      (let ((log (log-text)))
        (assert-true (search "ERROR GET /boom" log))
        (assert-true (search "kaboom in controller" log))))))

(define-test debug-page-only-for-local-requests ()
  (with-error-state
    (let ((errors:*debug* t)
          (app (make-app +basic-module+)))
      (let ((r (request app :get "/boom")))
        (assert-eql 500 (status r))
        (assert-true (search "Backtrace" (body r)))
        (assert-true (search "kaboom in controller" (body r))))
      (let ((r (request app :get "/boom" :remote-addr "10.0.0.5")))
        (assert-false (search "Backtrace" (body r))))
      (let ((r (request app :get "/boom" :headers '("x-forwarded-for" "203.0.113.9"))))
        (assert-false (search "Backtrace" (body r)))))))

(define-test client-error-logging-policy ()
  (with-error-state
    (let ((app (make-app +basic-module+))
          (same-site '("referer" "http://localhost:5000/elsewhere")))
      (let ((errors:*log-client-errors* :internal-referer))
        (request app :get "/nope")
        (assert-equal "" (log-text) "404 without a referer isn't logged")
        (request app :get "/nope" :headers same-site)
        (assert-true (search "404 GET /nope" (log-text)) "broken internal link is logged")
        (request app :get "/forbidden" :headers same-site)
        (assert-equal "" (log-text) "only 404s, under :internal-referer"))
      (let ((errors:*log-client-errors* t))
        (request app :get "/forbidden")
        (assert-true (search "403 GET /forbidden" (log-text))))
      (let ((errors:*log-client-errors* nil))
        (request app :get "/nope" :headers same-site)
        (assert-equal "" (log-text)))
      (request app :get "/unavailable")
      (assert-true (search "ERROR 503" (log-text)) "5xx always logged"))))

(define-test debug-404-lists-routes-tried ()
  (with-error-state
    (let ((app (make-app +basic-module+)))
      (shiso:define-error-page 404 (c) (declare (ignore c)) "app 404")
      (let ((errors:*debug* t))
        (let ((page (body (request app :get "/nope"))))
          (assert-true (search "tried these URL patterns" page))
          (assert-true (search "things&#x2F;&lt;int:id&gt;" page) "typed pattern shown")
          (assert-true (search "trailing slash" page)))
        (assert-equal "app 404" (body (request app :get "/nope" :remote-addr "10.0.0.5")))
        (let ((errors:*debug-404* nil))
          (assert-equal "app 404" (body (request app :get "/nope")))))
      (assert-equal "app 404" (body (request app :get "/nope"))))))

;;; Negotiation -------------------------------------------------------------------------

(define-test json-clients-get-problem-details ()
  (with-error-state
    (let ((app (make-app +basic-module+)))
      (let ((r (request app :get "/nope" :accept "application/json")))
        (assert-eql 404 (status r))
        (assert-equal "application/problem+json; charset=utf-8" (header r :content-type))
        (assert-equal "{\"type\":\"about:blank\",\"title\":\"Not Found\",\"status\":404}" (body r)))
      (let ((r (request app :get "/forbidden" :accept "application/problem+json")))
        (assert-true (search "\"detail\":\"Members only\"" (body r))))
      (let ((r (request app :get "/boom" :accept "application/json")))
        (assert-eql 500 (status r))
        (assert-false (search "detail" (body r)))))))

(define-test htmx-requests-render-fragments ()
  (with-error-state
    (shiso:define-error-page 404 (c) (declare (ignore c))
      (if shiso:*fragment-p* "fragment" "full page"))
    (let ((app (make-app +basic-module+)))
      (assert-equal "fragment" (body (request app :get "/nope" :hx t)))
      (assert-equal "full page" (body (request app :get "/nope"))))))

;;; Mapping conditions --------------------------------------------------------------------

(define-condition quota-exceeded (error) ())

(define-test mapped-condition-gets-its-status-and-cause ()
  (with-error-state
    (let ((method (defmethod shiso:condition-http-status ((c quota-exceeded)) 429))
          (seen nil))
      (unwind-protect
           (let ((app (make-app '(shiso:define-module err-quota
                                   (:urls (:GET "/q" (lambda () (error 'quota-exceeded)) "q"))))))
             (shiso:define-error-page 429 (c) (setf seen (shiso:http-error-cause c)) "slow down")
             (let ((r (request app :get "/q")))
               (assert-eql 429 (status r))
               (assert-equal "slow down" (body r))
               (assert-typep 'quota-exceeded seen)
               (assert-false (search "Backtrace" (log-text)))))
        (remove-method #'shiso:condition-http-status method)))))

(define-test mapping-method-that-fails-means-500 ()
  (with-error-state
    (let ((method (defmethod shiso:condition-http-status ((c quota-exceeded)) (error "bad method"))))
      (unwind-protect
           (let ((app (make-app '(shiso:define-module err-quota2
                                   (:urls (:GET "/q" (lambda () (error 'quota-exceeded)) "q"))))))
             (assert-eql 500 (status (request app :get "/q"))))
        (remove-method #'shiso:condition-http-status method)))))

;;; Static error files ------------------------------------------------------------------------

(defmacro with-static-errors ((&rest files) &body body)
  "Bind *STATIC-ERROR-ROOT* to a temp directory holding FILES (name content ...)."
  (let ((dir (gensym)))
    `(let ((,dir (uiop:ensure-directory-pathname
                  (format nil "~Ashiso-errors-~D/" (uiop:temporary-directory) (random 1000000)))))
       (ensure-directories-exist ,dir)
       (unwind-protect
            (let ((errors:*static-error-root* ,dir))
              (loop for (name content) on (list ,@files) by #'cddr
                    do (with-open-file (s (merge-pathnames name ,dir) :direction :output
                                                                      :if-exists :supersede)
                         (write-string content s)))
              ,@body)
         (uiop:delete-directory-tree ,dir :validate t)))))

(define-test static-file-when-the-page-fails ()
  (with-error-state
    (with-static-errors ("500.html" "static 500" "5xx.html" "static 5xx")
      (shiso:define-error-page :5xx (c) (declare (ignore c)) (error "template bug"))
      (let ((app (make-app +basic-module+)))
        (let ((r (request app :get "/boom")))
          (assert-eql 500 (status r))
          (assert-typep 'pathname (third r))
          (assert-equal "500.html" (file-namestring (third r))))
        (let ((r (request app :get "/unavailable")))
          (assert-eql 503 (status r))
          (assert-equal "5xx.html" (file-namestring (third r))))))))

(define-test prefer-static-5xx-skips-the-page ()
  (with-error-state
    (with-static-errors ("5xx.html" "static 5xx")
      (let ((called nil)
            (errors:*prefer-static-5xx* t))
        (shiso:define-error-page :5xx (c) (declare (ignore c)) (setf called t) "dynamic")
        (let ((r (request (make-app +basic-module+) :get "/unavailable")))
          (assert-eql 503 (status r))
          (assert-typep 'pathname (third r))
          (assert-false called))))))

(define-test last-resort-when-the-machinery-fails ()
  (with-error-state
    (let ((original (fdefinition 'errors:render-error-response))
          (app (make-app +basic-module+)))
      (unwind-protect
           (progn
             (setf (fdefinition 'errors:render-error-response)
                   (lambda (c env) (declare (ignore c env)) (error "renderer broke")))
             (let ((r (request app :get "/nope")))
               (assert-eql 500 (status r))
               (assert-equal "500 Internal Server Error" (body r))
               (assert-true (search "error handler itself failed" (log-text)))))
        (setf (fdefinition 'errors:render-error-response) original)))))

;;; Typed route parameters --------------------------------------------------------------------

(define-test int-parameter-is-converted ()
  (with-error-state
    (let ((r (request (make-app +basic-module+) :get "/things/42")))
      (assert-eql 200 (status r))
      (assert-equal "int 42" (body r)))))

(define-test rejected-parameter-is-404-not-500 ()
  (with-error-state
    (let ((app (make-app +basic-module+)))
      (assert-eql 404 (status (request app :get "/things/abc")))
      (assert-eql 404 (status (request app :post "/strict/abc"))
                  "the 405 probe runs converters too"))))

(define-test later-untyped-route-gets-rejected-values ()
  (with-error-state
    (let ((r (request (make-app '(shiso:define-module err-fall
                                   (:urls (:GET "/p/<int:id>" (lambda (id) (shiso:http-response (format nil "int ~D" id))) "by-id")
                                          (:GET "/p/:slug" (lambda (slug) (shiso:http-response (format nil "slug ~A" slug))) "by-slug"))))
                      :get "/p/hello")))
      (assert-eql 200 (status r))
      (assert-equal "slug hello" (body r)))))

(define-test url-accepts-typed-values ()
  (with-error-state
    (make-app +basic-module+)
    (assert-equal "/things/7" (shiso:url "err-basic:thing-by-id" :id 7))
    (assert-equal "/things/7" (shiso:url "err-basic:thing-by-id" :id "7"))))

(define-test custom-converter-can-be-defined-and-redefined ()
  (with-error-state
    (unwind-protect
         (progn
           (eval '(shiso:define-path-converter err-year (string)
                   (if (= 4 (length string)) (values (parse-integer string) t) (values nil nil))))
           (let ((app (make-app '(shiso:define-module err-years
                                   (:urls (:GET "/y/<err-year:y>" (lambda (y) (shiso:http-response (format nil "~D" (1+ y)))) "y"))))))
             (assert-equal "2027" (body (request app :get "/y/2026")))
             (assert-eql 404 (status (request app :get "/y/26")))
             (eval '(shiso:define-path-converter err-year (string)
                     (values (parse-integer string) t)))
             (assert-equal "27" (body (request app :get "/y/26")))))
      (remhash "err-year" routing:*path-converters*))))

(define-test unknown-converter-is-an-error-when-defining ()
  (with-error-state
    (assert-error 'error
                  (eval '(shiso:define-module err-badconv
                          (:urls (:GET "/z/<nope:z>" (lambda (z) z) "z")))))))

(define-test builtin-converters ()
  (flet ((conv (name string)
           (funcall (routing::path-converter-parse (routing:find-path-converter name)) string)))
    (assert-eql 42 (conv "int" "42"))
    (assert-false (nth-value 1 (conv "int" "-1")))
    (assert-false (nth-value 1 (conv "int" "4x")))
    (assert-equal "a-b_c9" (conv "slug" "a-b_c9"))
    (assert-false (nth-value 1 (conv "slug" "a b")))
    (assert-equal "123e4567-e89b-12d3-a456-426614174000"
                  (conv "uuid" "123E4567-E89B-12D3-A456-426614174000"))
    (assert-false (nth-value 1 (conv "uuid" "123e4567e89b12d3a456426614174000")))))

(define-test regexp-route-passes-captures ()
  (with-error-state
    (eval '(shiso:define-module err-regex (:urls)))
    (shiso:define-route :get "/r/(\\d+)/(\\w+)"
                        :controller (lambda (n w) (shiso:http-response (format nil "~A-~A" n w)))
                        :regexp t
                        :routes (shiso:module-routes (shiso:get-module :err-regex)))
    (let ((app (errors:wrap-http-errors
                (symbol-value (eval '(shiso:define-application err-regex-app ()
                                      (:modules ("" err-regex))))))))
      (assert-equal "12-ab" (body (request app :get "/r/12/ab"))))))

;;; get-or-404 ---------------------------------------------------------------------------

(define-test found-or-404-signals-not-found ()
  (assert-eql 5 (shiso:found-or-404 5))
  (assert-error 'shiso:not-found (shiso:found-or-404 nil)))

;;; Database: get-or-404 and atomic requests -----------------------------------------------

(mito:deftable err-row ()
  ((label :col-type :text)))

(defmacro with-memory-db (&body body)
  `(let ((saved mito:*connection*))
     (unwind-protect
          (progn
            (setf mito:*connection* (dbi:connect :sqlite3 :database-name ":memory:"))
            (let ((mito:*mito-logger-stream* nil))
              (mito:ensure-table-exists 'err-row)
              ,@body))
       (ignore-errors (dbi:disconnect mito:*connection*))
       (setf mito:*connection* saved))))

(defun row-count () (mito:count-dao 'err-row))

(define-test get-or-404-finds-or-signals ()
  (with-memory-db
    (let ((row (mito:create-dao 'err-row :label "a")))
      (assert-equal "a" (err-row-label (shiso:get-or-404 'err-row :id (mito:object-id row))))
      (assert-error 'shiso:not-found (shiso:get-or-404 'err-row :id 999)))))

(defun atomic-app (handler)
  (errors:wrap-http-errors (server::wrap-atomic-requests handler)))

(define-test post-that-fails-rolls-back ()
  (with-error-state
    (with-memory-db
      (let ((app (atomic-app (lambda (env) (declare (ignore env))
                               (mito:create-dao 'err-row :label "doomed")
                               (error "after the insert")))))
        (assert-eql 500 (status (request app :post "/")))
        (assert-eql 0 (row-count))))))

(define-test post-that-aborts-rolls-back ()
  (with-error-state
    (with-memory-db
      (let ((app (atomic-app (lambda (env) (declare (ignore env))
                               (mito:create-dao 'err-row :label "doomed")
                               (shiso:abort-with 403)))))
        (assert-eql 403 (status (request app :post "/")))
        (assert-eql 0 (row-count))))))

(define-test post-that-returns-commits-and-nested-transactions-work ()
  (with-error-state
    (with-memory-db
      (let ((app (atomic-app (lambda (env) (declare (ignore env))
                               (dbi:with-transaction mito:*connection*
                                 (mito:create-dao 'err-row :label "inner"))
                               (mito:create-dao 'err-row :label "outer")
                               '(200 () ("ok"))))))
        (assert-eql 200 (status (request app :post "/")))
        (assert-eql 2 (row-count))))))

(define-test get-runs-without-a-transaction ()
  (with-error-state
    (with-memory-db
      (let* ((inside nil)
             (app (atomic-app (lambda (env) (declare (ignore env))
                                (setf inside (dbi:in-transaction mito:*connection*))
                                '(200 () ("ok"))))))
        (request app :get "/")
        (assert-false inside)
        (request app :post "/")
        (assert-true inside)))))

;;; The :repl debugger mode --------------------------------------------------------------------

(defun repl-wrapped (app)
  "APP under the :repl mode's restarts, without the editor check."
  (lambda (env) (errors::call-with-retry app env :repl)))

(defun read-body (env)
  (let ((stream (getf env :raw-body))
        (octets (make-array 0 :element-type '(unsigned-byte 8) :adjustable t :fill-pointer 0)))
    (loop for byte = (read-byte stream nil nil)
          while byte do (vector-push-extend byte octets))
    (flex:octets-to-string octets :external-format :utf-8)))

(defmacro with-debugger-choosing ((restart &optional before) &body body)
  "Run BODY with the debugger replaced by a function that runs BEFORE (a form)
and then invokes RESTART, as a developer in SLY would."
  `(let* ((hook (lambda (condition hook)
                  (declare (ignore condition hook))
                  ,before
                  (invoke-restart ',restart)))
          (*debugger-hook* hook)
          #+sbcl (sb-ext:*invoke-debugger-hook* hook))
     ,@body))

(define-test repl-retry-runs-the-request-again-after-the-fix ()
  (with-error-state
    (with-memory-db
      (let* ((fixed nil)
             (seen-bodies '())
             (app (lambda (env)
                    (push (read-body env) seen-bodies)
                    (mito:create-dao 'err-row :label "attempt")
                    (unless fixed (error "bug, not fixed yet"))
                    '(200 () ("fixed"))))
             (wrapped (repl-wrapped (server::wrap-atomic-requests app))))
        (with-debugger-choosing (shiso:retry-request (setf fixed t))
          (let ((r (funcall wrapped (make-env :post "/" :body "a=1&b=2"))))
            (assert-eql 200 (status r))
            (assert-equal "fixed" (body r))
            (assert-equal '("a=1&b=2" "a=1&b=2") seen-bodies "body readable on both attempts")
            (assert-eql 1 (row-count) "the failed attempt's insert was rolled back")))))))

(define-test repl-show-debug-page-sends-it ()
  (with-error-state
    (let ((wrapped (repl-wrapped
                    (lambda (env) (declare (ignore env)) (error "still broken")))))
      (with-debugger-choosing (shiso:show-debug-page)
        (let ((r (funcall wrapped (make-env :get "/"))))
          (assert-eql 500 (status r))
          (assert-true (search "still broken" (body r))))))))

(define-test repl-mode-needs-an-editor-and-a-local-request ()
  (with-error-state
    ;; No SLY/SLIME connection in the test image: :REPL falls back to the
    ;; debug page instead of waiting in a debugger nobody sees.
    (let ((errors:*debug* :repl))
      (unless (errors:editor-connected-p)
        (let ((r (request (make-app +basic-module+) :get "/boom")))
          (assert-eql 500 (status r))
          (assert-true (search "Backtrace" (body r))))))))

;;; CSRF -----------------------------------------------------------------------------------------

(define-test csrf-failure-is-a-bad-request ()
  (assert-error 'shiso:bad-request (server::csrf-failed nil)))

;;; Logging details ---------------------------------------------------------------------------------

(define-test backtraces-start-at-the-signal ()
  (let ((text (format nil "Backtrace for: thread~%0: (PRINT-BACKTRACE)~%1: (HANDLER)~%2: (SB-KERNEL::%SIGNAL #<C>)~%3: (ERROR C)~%4: (MY-CONTROLLER)")))
    (assert-equal (format nil "Backtrace for: thread~%3: (ERROR C)~%4: (MY-CONTROLLER)")
                  (errors::trim-backtrace text))
    (assert-equal "no frames" (errors::trim-backtrace "no frames"))))
