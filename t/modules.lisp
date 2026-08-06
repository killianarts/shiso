(defpackage #:shiso/t/modules
  (:use #:cl #:lisp-unit2))

(in-package #:shiso/t/modules)

(defun fresh-registry ()
  "Clear the module registry for a clean test."
  (clrhash shiso:*module-registry*))

(defun fresh-routes ()
  "Reset *routes* to a fresh mapper."
  (setf shiso:*routes* (make-instance 'shiso:routes :mapper (myway:make-mapper))))

(defmacro with-fresh-routes (&body body)
  "Execute BODY with a fresh module registry and fresh global routes."
  (let ((saved-routes (gensym "SAVED-ROUTES"))
        (saved-modules (gensym "SAVED-MODULES")))
    `(let ((,saved-routes shiso:*routes*)
           (,saved-modules (alexandria:copy-hash-table shiso:*module-registry*)))
       (fresh-registry)
       (fresh-routes)
       (unwind-protect (progn ,@body)
         (setf shiso:*module-registry* ,saved-modules
               shiso:*routes* ,saved-routes)))))

(defun module-routes-list (mod)
  "Get all routes from a module's mapper as a list."
  (let ((raw (myway.mapper:mapper-routes
              (shiso:routes-mapper (shiso:module-routes mod)))))
    (if (listp raw)
        raw
        (let ((routes nil))
          (map-set:ms-for-each
           (lambda (route) (push route routes))
           raw)
          routes))))

(defun find-module-route (mod name)
  "Find a route by short MyWay name keyword on a module's mapper."
  (find-if (lambda (route)
             (eq (myway.route:route-name route) name))
           (module-routes-list mod)))

(defun route-url (route)
  "Get the URL string from a route's rule."
  (myway.rule::rule-url (myway.route:route-rule route)))

(defun route-methods (route)
  "Get the HTTP methods from a route's rule as a list."
  (let ((raw (slot-value (myway.route:route-rule route) 'myway.rule::methods)))
    (if (listp raw)
        raw
        (let ((methods nil))
          (map-set:ms-for-each
           (lambda (m) (push m methods))
           raw)
          methods))))

(define-test register-module-stores-module ()
  (with-fresh-routes
    (let ((mod (make-instance 'shiso:module
                              :routes (make-instance 'shiso:routes
                                                     :mapper (myway:make-mapper)))))
      (shiso:register-module :test mod)
      (assert-true (eq mod (shiso:get-module :test))
                   "get-module should return the registered module"))))

(define-test get-module-signals-error-for-missing ()
  (with-fresh-routes
    (assert-error 'error (shiso:get-module :nonexistent)
                  "get-module should signal an error for unregistered modules")))

(define-test register-module-overwrites-existing ()
  (with-fresh-routes
    (let ((mod1 (make-instance 'shiso:module
                               :routes (make-instance 'shiso:routes
                                                      :mapper (myway:make-mapper))))
          (mod2 (make-instance 'shiso:module
                               :routes (make-instance 'shiso:routes
                                                      :mapper (myway:make-mapper)))))
      (shiso:register-module :overwrite-test mod1)
      (shiso:register-module :overwrite-test mod2)
      (assert-true (eq mod2 (shiso:get-module :overwrite-test))
                   "Re-registering should silently overwrite the module"))))

(define-test define-module-expands-to-progn ()
  (let ((expansion (macroexpand-1
                    '(shiso:define-module test-mod
                       (:urls (:GET "/" #'identity "index"))))))
    (assert-true (eq 'progn (first expansion))
                 "define-module should expand to a progn")))

(define-test define-module-expansion-ends-with-quoted-name ()
  (let ((expansion (macroexpand-1
                    '(shiso:define-module my-mod
                       (:urls (:GET "/" #'identity "index"))))))
    (let ((last-form (car (last expansion))))
      (assert-true (and (listp last-form)
                        (eq 'quote (first last-form))
                        (eq 'my-mod (second last-form)))
                   "Last form should be the quoted module name"))))

(define-test define-module-expands-multiple-methods ()
  (let ((expansion (macroexpand-1
                    '(shiso:define-module test-mod
                       (:urls ((:GET :POST) "/create" #'identity "create"))))))
    ;; expansion = (PROGN (LET (#:MODULE-ROUTES...) (define-route :GET ...) (define-route :POST ...) (register-module ...)) 'test-mod)
    (let* ((let-form (second expansion))        ; the LET form
           (let-body (cddr let-form))            ; body of the LET
           (route-forms (remove-if-not
                         (lambda (f) (and (listp f)
                                          (eq (car f) 'shiso/routing:define-route)))
                         let-body)))
      (assert-eql 2 (length route-forms)
                  "Two methods should produce two define-route forms"))))

(define-test define-module-registers-in-registry ()
  (with-fresh-routes
    (eval '(shiso:define-module registry-test
             (:urls (:GET "/" (lambda () (shiso:http-response "hi")) "index"))))
    (let ((mod (shiso:get-module :registry-test)))
      (assert-true (typep mod 'shiso:module)
                   "Module should be registered as a module instance"))))

(define-test define-module-creates-routes-on-module ()
  (with-fresh-routes
    (eval '(shiso:define-module routes-test
             (:urls (:GET "/" (lambda () (shiso:http-response "index")) "index")
                    (:GET "/list" (lambda () (shiso:http-response "list")) "list"))))
    (let* ((mod (shiso:get-module :routes-test))
           (routes (module-routes-list mod)))
      (assert-eql 2 (length routes)
                  "Module mapper should have two routes"))))

(define-test define-module-routes-are-unprefixed ()
  (with-fresh-routes
    (eval '(shiso:define-module prefix-test
             (:urls (:GET "/" (lambda () (shiso:http-response "index")) "index"))))
    (let* ((mod (shiso:get-module :prefix-test))
           (route (find-module-route mod :INDEX)))
      (assert-true route "Route should exist on module mapper")
      (assert-string= "/" (route-url route)
                      "Route path should be un-prefixed on module mapper"))))

(define-test define-module-stores-short-route-names ()
  (with-fresh-routes
    (eval '(shiso:define-module articles
             (:urls (:GET "/" (lambda () (shiso:http-response "index")) "index"))))
    (let ((mod (shiso:get-module :articles)))
      (assert-true (find-module-route mod :INDEX)
                   "Route should be stored under short name :INDEX on the module mapper"))))

(define-test define-module-handles-multiple-methods ()
  (with-fresh-routes
    (eval '(shiso:define-module multi-method
             (:urls ((:GET :POST) "/form" (lambda () (shiso:http-response "form")) "form"))))
    (let* ((mod (shiso:get-module :multi-method))
           (routes (module-routes-list mod)))
      (assert-eql 2 (length routes)
                  "Two methods should create two routes")
      (let ((all-methods (loop for r in routes append (route-methods r))))
        (assert-true (member :GET all-methods) "Should have a GET route")
        (assert-true (member :POST all-methods) "Should have a POST route")))))

(define-test define-module-creates-correct-route-urls ()
  (with-fresh-routes
    (eval '(shiso:define-module url-test
             (:urls (:GET "/users/:id" (lambda (id) (shiso:http-response id)) "show"))))
    (let* ((mod (shiso:get-module :url-test))
           (route (find-module-route mod :SHOW)))
      (assert-true route "Route should exist")
      (assert-string= "/users/:id" (route-url route)
                      "Route URL should be un-prefixed on module mapper"))))

(define-test define-application-expands-to-defparameter ()
  (let ((expansion (macroexpand-1
                    '(shiso:define-application my-app ()
                       (:modules ("/blog" blog) ("/shop" shop))))))
    ;; expansion is (DEFPARAMETER MY-APP (LACK:BUILDER ...))
    (assert-true (and (listp expansion) (eq 'defparameter (first expansion)))
                 "Should expand to a defparameter form")))

(define-test define-application-contains-module-mounts ()
  (let ((expansion (macroexpand-1
                    '(shiso:define-application my-app ()
                       (:modules ("/blog" blog) ("/shop" shop))))))
    ;; expansion = (DEFPARAMETER MY-APP (LACK:BUILDER <middleware…> … 404))
    ;; Mounts are hand-rolled lambdas (not lack :mount) so a miss falls through.
    (let* ((printed (prin1-to-string expansion)))
      (assert-true (search "/blog" printed)
                   "Expansion should mention the /blog prefix")
      (assert-true (search "/shop" printed)
                   "Expansion should mention the /shop prefix")
      (assert-true (or (search ":BLOG" printed) (search ":blog" printed)
                       (search "BLOG" printed))
                   "Expansion should reference the blog module keyword"))))

(define-test define-application-creates-lack-app ()
  (with-fresh-routes
    (eval '(shiso:define-module app-mod
             (:urls (:GET "/" (lambda () (shiso:http-response "hi")) "index"))))
    (eval '(shiso:define-application integration-app ()
             (:modules ("" app-mod))))
    (assert-true (boundp (intern "INTEGRATION-APP" :cl-user))
                 "Application variable should be bound")
    (assert-true (functionp (symbol-value (intern "INTEGRATION-APP" :cl-user)))
                 "Application should be a function (Lack app)")))

(defun make-test-env (path &key (method :GET))
  "Create a minimal Lack environment for testing."
  (list :request-method method
        :request-uri path
        :path-info path
        :query-string ""
        :server-name "localhost"
        :server-port 5000
        :server-protocol :http/1.1
        :url-scheme "http"
        :remote-addr "127.0.0.1"
        :remote-port 12345
        :content-type nil
        :content-length nil
        :headers (make-hash-table :test 'equal)
        :input (make-string-input-stream "")))

(define-test module-dispatches-unprefixed-route ()
  (with-fresh-routes
    (eval '(shiso:define-module dispatch-test
             (:urls (:GET "/" (lambda () (shiso:http-response "hello")) "index"))))
    (let* ((mod (shiso:get-module :dispatch-test))
           (response (lack/component:call mod (make-test-env "/"))))
      (assert-true (listp response) "Response should be a list")
      (assert-eql 200 (first response) "Status should be 200"))))

(define-test module-returns-404-for-unmatched ()
  (with-fresh-routes
    (eval '(shiso:define-module notfound-test
             (:urls (:GET "/" (lambda () (shiso:http-response "hi")) "index"))))
    (let* ((mod (shiso:get-module :notfound-test))
           (response (lack/component:call mod (make-test-env "/nonexistent"))))
      (assert-true (listp response) "Response should be a list")
      (assert-eql 404 (first response) "Status should be 404"))))

(define-test mounted-app-dispatches-prefixed-route ()
  (with-fresh-routes
    (eval '(shiso:define-module mounted-test
             (:urls (:GET "/" (lambda () (shiso:http-response "mounted")) "index"))))
    (eval '(shiso:define-application mounted-app ()
             (:modules ("/mounted-test" mounted-test))))
    (let* ((app (symbol-value (intern "MOUNTED-APP" :cl-user)))
           ;; No trailing slash: app middleware 301-redirects "/path/" → "/path".
           (response (funcall app (make-test-env "/mounted-test"))))
      (assert-true (listp response) "Response should be a list")
      (assert-eql 200 (first response) "Status should be 200 for prefixed path"))))

(define-test mounted-app-returns-404-for-unknown-prefix ()
  (with-fresh-routes
    (eval '(shiso:define-module fallback-test
             (:urls (:GET "/" (lambda () (shiso:http-response "hi")) "index"))))
    (eval '(shiso:define-application fallback-app ()
             (:modules ("/fallback-test" fallback-test))))
    (let* ((app (symbol-value (intern "FALLBACK-APP" :cl-user)))
           (response (funcall app (make-test-env "/unknown"))))
      (assert-true (listp response) "Response should be a list")
      (assert-eql 404 (first response) "Status should be 404 for unknown prefix"))))

(define-test url-returns-prefixed-path-for-namespaced-route ()
  (with-fresh-routes
    (eval '(shiso:define-module articles
             (:urls (:GET "/" (lambda () (shiso:http-response "index")) "index"))))
    (setf (shiso:module-prefix (shiso:get-module :articles)) "/articles")
    ;; Index of a mount is the prefix without a trailing slash (canonical).
    (assert-string= "/articles" (shiso:url "articles:index")
                    "url should return prefixed path for namespaced route without trailing slash")))

(define-test url-returns-prefixed-path-with-params ()
  (with-fresh-routes
    (eval '(shiso:define-module articles
             (:urls (:GET "/users/:id" (lambda (id) (shiso:http-response id)) "show"))))
    (setf (shiso:module-prefix (shiso:get-module :articles)) "/articles")
    (assert-string= "/articles/users/42" (shiso:url "articles:show" :id "42")
                    "url should return prefixed path with params")))

(define-test url-returns-unprefixed-path-for-global-route ()
  (with-fresh-routes
    (shiso:define-route :GET "/about"
      :controller (lambda () (shiso:http-response "about"))
      :name "about")
    (assert-string= "/about" (shiso:url "about")
                    "url should return un-prefixed path for global route")))

(define-test root-mounted-module-has-no-prefix ()
  (with-fresh-routes
    (eval '(shiso:define-module pages
             (:urls (:GET "/about" (lambda () (shiso:http-response "about")) "about"))))
    (setf (shiso:module-prefix (shiso:get-module :pages)) "")
    (assert-string= "/about" (shiso:url "pages:about")
                    "Root-mounted module should generate URLs without a prefix")))

;;; ----------------------------------------------------------------------
;;; Trailing-slash canonicalization and mount script-name.

(define-test canonicalize-path-strips-trailing-slash ()
  (assert-string= "/" (shiso:canonicalize-path "/"))
  (assert-string= "/" (shiso:canonicalize-path "///"))
  (assert-string= "/staff" (shiso:canonicalize-path "/staff/"))
  (assert-string= "/staff" (shiso:canonicalize-path "/staff"))
  (assert-string= "/staff/crm" (shiso:canonicalize-path "/staff/crm/")))

(define-test canonicalize-redirect-url-preserves-query ()
  (assert-string= "/staff" (shiso:canonicalize-redirect-url "/staff/"))
  (assert-string= "/login?next=%2Fstaff"
                  (shiso:canonicalize-redirect-url "/login?next=%2Fstaff"))
  (assert-string= "/staff?x=1"
                  (shiso:canonicalize-redirect-url "/staff/?x=1"))
  (assert-string= "https://example.com/foo/"
                  (shiso:canonicalize-redirect-url "https://example.com/foo/")
                  "Absolute external URLs are left alone"))

(define-test redirect-response-strips-trailing-slash ()
  (let ((response (shiso:redirect-response "/staff/")))
    (assert-eql 302 (first response))
    (assert-string= "/staff" (getf (second response) :location)
                    "redirect-response must not re-add a trailing slash")))

(define-test trailing-slash-middleware-301s-to-canonical ()
  (let* ((inner (lambda (env)
                  (declare (ignore env))
                  '(200 () ("ok"))))
         (app (shiso/routing:strip-trailing-slash-middleware inner))
         (response (funcall app (make-test-env "/staff/"))))
    (assert-eql 301 (first response))
    (assert-string= "/staff" (getf (second response) :location))))

(define-test trailing-slash-middleware-preserves-query-string ()
  (let* ((inner (lambda (env)
                  (declare (ignore env))
                  '(200 () ("ok"))))
         (app (shiso/routing:strip-trailing-slash-middleware inner))
         (env (make-test-env "/staff/"))
         (_ (setf (getf env :query-string) "tab=1"))
         (response (funcall app env)))
    (declare (ignore _))
    (assert-eql 301 (first response))
    (assert-string= "/staff?tab=1" (getf (second response) :location))))

(define-test trailing-slash-middleware-passes-canonical-paths ()
  (let* ((seen nil)
         (inner (lambda (env)
                  (setf seen (getf env :path-info))
                  '(200 () ("ok"))))
         (app (shiso/routing:strip-trailing-slash-middleware inner))
         (response (funcall app (make-test-env "/staff"))))
    (assert-eql 200 (first response))
    (assert-string= "/staff" seen)))

(define-test mount-sets-script-name-for-full-path ()
  "After mount, path-info is stripped but script-name holds the prefix so
   full-path-from-env (and login next=) recover the original URL."
  (with-fresh-routes
    (eval '(shiso:define-module script-name-test
             (:urls (:GET "/" (lambda ()
                                (let ((env (lack/request:request-env shiso:*request*)))
                                  (shiso:http-response
                                   (format nil "~A|~A|~A"
                                           (getf env :script-name)
                                           (getf env :path-info)
                                           (shiso/routing:full-path-from-env env)))))
                      "index"))))
    (eval '(shiso:define-application script-name-app ()
             (:modules ("/staff" script-name-test))))
    (let* ((app (symbol-value (intern "SCRIPT-NAME-APP" :cl-user)))
           (response (funcall app (make-test-env "/staff")))
           (body (first (third response))))
      (assert-eql 200 (first response))
      (assert-string= "/staff|/|/staff" body
                      "script-name=/staff, path-info=/, full=/staff"))))

(define-test mount-full-path-for-nested-route ()
  (with-fresh-routes
    (eval '(shiso:define-module nested-full-path
             (:urls (:GET "/profile" (lambda ()
                                       (shiso:http-response
                                        (shiso/routing:full-path-from-env
                                         (lack/request:request-env shiso:*request*))))
                       "profile"))))
    (eval '(shiso:define-application nested-full-path-app ()
             (:modules ("/staff" nested-full-path))))
    (let* ((app (symbol-value (intern "NESTED-FULL-PATH-APP" :cl-user)))
           (response (funcall app (make-test-env "/staff/profile")))
           (body (first (third response))))
      (assert-eql 200 (first response))
      (assert-string= "/staff/profile" body))))

(define-test redirect-loop-cannot-form-via-redirect-response ()
  "App redirects to a slash form must be normalized; combined with the 301
   stripper this means at most one hop slash→canonical, never a loop."
  (with-fresh-routes
    (eval '(shiso:define-module loop-test
             (:urls (:GET "/" (lambda () (shiso:redirect-response "/staff/")) "index"))))
    (eval '(shiso:define-application loop-app ()
             (:modules ("/staff" loop-test))))
    (let* ((app (symbol-value (intern "LOOP-APP" :cl-user)))
           ;; Canonical request (no trailing slash) hits the controller.
           (response (funcall app (make-test-env "/staff")))
           (location (getf (second response) :location)))
      (assert-eql 302 (first response))
      (assert-string= "/staff" location
                      "Controller redirect to /staff/ must become /staff")
      ;; Slash form is a single 301, not a 302 back to slash.
      (let ((slash-response (funcall app (make-test-env "/staff/"))))
        (assert-eql 301 (first slash-response))
        (assert-string= "/staff" (getf (second slash-response) :location))))))
