(defpackage #:mysite/t/polls-routes
  (:use #:cl #:lisp-unit2))

(in-package #:mysite/t/polls-routes)

(defun make-env (path &key (method :GET) (query ""))
  (list :request-method method
        :request-uri path
        :path-info path
        :query-string query
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

(defmacro with-fresh-db (&body body)
  `(let ((mito.connection:*connection* nil))
     (mito:connect-toplevel :sqlite3 :database-name ":memory:")
     (unwind-protect
          (progn
            (dolist (name (shiso/models:all-models))
              (mito:ensure-table-exists (shiso/models:model-class name)))
            ,@body)
       (mito:disconnect-toplevel))))

(define-test index-renders-200-when-empty ()
  (with-fresh-db
    (let* ((mod (shiso:get-module :polls))
           (response (lack/component:call mod (make-env "/"))))
      (assert-eql 200 (first response))
      (assert-true (search "No polls are available."
                           (first (third response)))))))

(define-test index-lists-questions ()
  (with-fresh-db
    (mito:create-dao (shiso/models:model-class 'polls/models::question)
                     :question-text "What is your name?")
    (let* ((mod (shiso:get-module :polls))
           (response (lack/component:call mod (make-env "/")))
           (body (first (third response))))
      (assert-eql 200 (first response))
      (assert-true (search "What is your name?" body)))))

(define-test detail-404s-for-missing-id ()
  (with-fresh-db
    (let* ((mod (shiso:get-module :polls))
           (response (lack/component:call mod (make-env "/9999"))))
      (assert-eql 404 (first response)))))
