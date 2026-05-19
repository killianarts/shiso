(defpackage #:polls/models
  (:use #:cl)
  (:export
   ;; Question accessors
   #:question-text
   #:pub-date
   ;; Choice accessors
   #:question-id
   #:choice-text
   #:votes
   ;; Helpers
   #:all-questions
   #:find-question
   #:choices-for-question
   #:question-published-recently-p
   #:create-choice))

(in-package #:polls/models)

(shiso:define-model question
    ((question-text :field-type :char
                    :max-length 200
                    :verbose-name "Question text"
                    :help-text "The text shown to voters."
                    :accessor question-text)
     (pub-date :field-type :datetime
               :verbose-name "Date published"
               :default (local-time:now)
               :accessor pub-date)))

(shiso:define-model choice
    ((question-id :field-type :integer
                  :verbose-name "Question id"
                  :help-text "Primary key of the question this choice belongs to."
                  :accessor question-id)
     (choice-text :field-type :char
                  :max-length 200
                  :verbose-name "Choice text"
                  :accessor choice-text)
     (votes :field-type :integer
            :default 0
            :editablep nil
            :accessor votes)))

(shiso/admin:define-admin question
  (:list-display question-text pub-date))

(shiso/admin:define-admin choice
  (:list-display choice-text votes question-id))

(defun all-questions (&key (limit 5))
  "Return the LIMIT most recently-published questions, newest first."
  (mito:select-dao (shiso/models:model-class 'question)
    (sxql:order-by (:desc :pub-date))
    (sxql:limit limit)))

(defun find-question (id)
  "Return the question with primary key ID, or NIL."
  (when id
    (mito:find-dao (shiso/models:model-class 'question) :id id)))

(defun choices-for-question (question)
  "Return all choices belonging to QUESTION, in id order."
  (mito:select-dao (shiso/models:model-class 'choice)
    (sxql:where (:= :question-id (mito:object-id question)))
    (sxql:order-by :id)))

(defun create-choice (question text)
  "Convenience: create and persist a choice for QUESTION with TEXT."
  (mito:create-dao (shiso/models:model-class 'choice)
                   :question-id (mito:object-id question)
                   :choice-text text))

(defun question-published-recently-p (question)
  "T iff QUESTION was published in the last 24 hours."
  (let* ((pub (pub-date question))
         (one-day-ago (local-time:timestamp- (local-time:now) 1 :day)))
    (local-time:timestamp> pub one-day-ago)))
