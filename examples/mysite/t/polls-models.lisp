(defpackage #:mysite/t/polls-models
  (:use #:cl #:lisp-unit2))

(in-package #:mysite/t/polls-models)

(defmacro with-fresh-db (&body body)
  "Spin up an in-memory SQLite, ensure tables, run BODY, then tear down."
  `(let ((mito.connection:*connection* nil))
     (mito:connect-toplevel :sqlite3 :database-name ":memory:")
     (unwind-protect
          (progn
            (dolist (name (shiso/models:all-models))
              (mito:ensure-table-exists (shiso/models:model-class name)))
            ,@body)
       (mito:disconnect-toplevel))))

(define-test all-questions-orders-newest-first ()
  (with-fresh-db
    (let* ((cls (shiso/models:model-class 'polls/models::question)))
      (mito:create-dao cls :question-text "Older"
                       :pub-date (local-time:timestamp- (local-time:now) 1 :day))
      (mito:create-dao cls :question-text "Newer"
                       :pub-date (local-time:now))
      (let ((ranked (polls/models:all-questions)))
        (assert-eql 2 (length ranked))
        (assert-string= "Newer" (polls/models:question-text (first ranked)))))))

(define-test choices-for-question-filters-by-fk ()
  (with-fresh-db
    (let* ((q1 (mito:create-dao (shiso/models:model-class 'polls/models::question)
                                :question-text "A"))
           (q2 (mito:create-dao (shiso/models:model-class 'polls/models::question)
                                :question-text "B")))
      (polls/models:create-choice q1 "a1")
      (polls/models:create-choice q1 "a2")
      (polls/models:create-choice q2 "b1")
      (assert-eql 2 (length (polls/models:choices-for-question q1)))
      (assert-eql 1 (length (polls/models:choices-for-question q2))))))

(define-test question-published-recently-p-respects-24h-window ()
  (with-fresh-db
    (let* ((cls (shiso/models:model-class 'polls/models::question))
           (now (mito:create-dao cls :question-text "fresh"
                                 :pub-date (local-time:now)))
           (old (mito:create-dao cls :question-text "stale"
                                 :pub-date (local-time:timestamp- (local-time:now) 2 :day))))
      (assert-true (polls/models:question-published-recently-p now))
      (assert-false (polls/models:question-published-recently-p old)))))
