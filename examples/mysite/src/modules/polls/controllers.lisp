(defpackage #:polls/controllers
  (:use #:cl)
  (:local-nicknames (#:s #:shiso)
                    (#:ah #:almighty-html)
                    (#:models #:polls/models)
                    (#:hy #:polls/hypermedia))
  (:export #:index
           #:detail
           #:results
           #:vote))

(in-package #:polls/controllers)

(defun render (title body)
  (s:http-response (hy:page title body)))

(defun csrf-token-input ()
  "Render a hidden CSRF token input for the current request's session."
  (let* ((env (lack/request:request-env s:*request*))
         (session (getf env :lack.session))
         (token (and session (lack/middleware/csrf:csrf-token session))))
    (when token
      (ah:</> (input :type "hidden" :name "_csrf_token" :value token)))))

;;; --------------------------------------------------------------------
;;; Index — list the latest five questions.

(defun question-list (questions)
  (ah:</>
   (ul :class "questions"
     (loop :for q :in questions
           :for id-str := (princ-to-string (mito:object-id q))
           :for href := (s:url "polls:detail" :id id-str)
           :collect (ah:</>
                     (li (a :href href (models:question-text q))))))))

(defun index ()
  (let* ((questions (models:all-questions :limit 5))
         (body-content (cond ((null questions)
                              (ah:</> (p "No polls are available.")))
                             (t (question-list questions)))))
    (render
     "Polls"
     (ah:</>
      (div
        (h1 "Latest polls")
        body-content
        (a :href "/admin" "Admin"))))))

;;; --------------------------------------------------------------------
;;; Detail — show a question and a form to vote.

(defun choice-radios (question)
  (ah:</>
   (<>
     (loop for choice in (models:choices-for-question question)
           for cid = (princ-to-string (mito:object-id choice))
           collect (ah:</>
                    (label
                      (input :type "radio"
                        :name "choice"
                        :value cid)
                      (models:choice-text choice)))))))

(defun detail (id-str)
  (let* ((id (parse-integer id-str :junk-allowed t))
         (question (models:find-question id))
         (error-msg (cdr (assoc "error"
                                (lack/request:request-query-parameters s:*request*)
                                :test #'string=))))
    (cond
      ((null question)
       (s:http-response "Question not found." :code 404))
      (t
       (let* ((error-block (when error-msg
                             (ah:</> (p :class "error" error-msg))))
              (q-text (models:question-text question)))
         (render
          q-text
          (ah:</>
           (div
             (h1 q-text)
             error-block
             (form :class "vote" :method "POST"
               :action (s:url "polls:vote" :id id-str)
               (csrf-token-input)
               (choice-radios question)
               (button :type "submit" "Vote"))))))))))

;;; --------------------------------------------------------------------
;;; Results — show the vote tally for a question.

(defun results-list (question)
  (ah:</>
   (ul :class "results"
     (loop for c in (models:choices-for-question question)
           collect (ah:</>
                    (li (format nil "~A — ~D vote~:P"
                                (models:choice-text c)
                                (models:votes c))))))))

(defun results (id-str)
  (let* ((id (parse-integer id-str :junk-allowed t))
         (question (models:find-question id)))
    (cond
      ((null question)
       (s:http-response "Question not found." :code 404))
      (t
       (let ((q-text (models:question-text question)))
         (render
          (format nil "Results for ~A" q-text)
          (ah:</>
           (div
             (h1 q-text)
             (results-list question)
             (a :href (s:url "polls:detail" :id id-str) "Vote again")))))))))

;;; --------------------------------------------------------------------
;;; Vote — POST handler that increments the chosen choice and redirects
;;; to the results page.

(defun vote (id-str)
  (let* ((id (parse-integer id-str :junk-allowed t))
         (question (models:find-question id)))
    (cond
      ((null question)
       (s:http-response "Question not found." :code 404))
      (t
       (let* ((body (s:parse-body-params))
              (choice-id-str (cdr (assoc :choice body)))
              (choice-id (and choice-id-str
                              (parse-integer choice-id-str :junk-allowed t)))
              (choice (and choice-id
                           (mito:find-dao (shiso/models:model-class 'choice)
                                          :id choice-id))))
         (cond
           ((null choice)
            (s:redirect-response
             (format nil "~A?error=~A"
                     (s:url "polls:detail" :id id-str)
                     (quri:url-encode "You didn't select a choice." :encoding :utf-8))))
           (t
            (incf (models:votes choice))
            (mito:save-dao choice)
            (s:redirect-response (s:url "polls:results" :id id-str)))))))))
