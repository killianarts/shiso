(defpackage #:todos/controllers
  (:use #:cl)
  (:local-nicknames (#:s #:shiso)
                    (#:ah #:almighty-html)
                    (#:models #:todos/models)
                    (#:hy #:todos/hypermedia))
  (:export #:index
           #:create
           #:toggle
           #:destroy))

(in-package #:todos/controllers)

(defun render (title body)
  (s:http-response (hy:page title body)))

(defun csrf-token-input ()
  (let* ((env (lack/request:request-env s:*request*))
         (session (getf env :lack.session))
         (token (and session (lack/middleware/csrf:csrf-token session))))
    (when token
      (ah:</> (input :type "hidden" :name "_csrf_token" :value token)))))

;;; --------------------------------------------------------------------
;;; Helpers — split out so the index controller stays straight-line and
;;; the if/cond branching stays out of `</>` (which can't introspect
;;; them).

(defun todo-row (todo)
  (let* ((id-str (princ-to-string (mito:object-id todo)))
         (donep (models:done todo))
         (todo-title (models:title todo))
         (li-class (if donep "done" "")))
    (ah:</>
     (li :class li-class
       ;; Toggle form
       (form :method "POST" :action (s:url "todos:toggle" :id id-str)
         (csrf-token-input)
         (input :type "checkbox" :name "_" :|onChange| "this.form.submit()"
           :checked donep))
       ;; Title
       (span :class "title" todo-title)
       ;; Delete form
       (form :class "delete-form" :method "POST"
             :action (s:url "todos:delete" :id id-str)
         (csrf-token-input)
         (button :type "submit" :class "delete" "Delete"))))))

(defun empty-state ()
  (ah:</> (p "Nothing to do. Add a task above to get started.")))

(defun todo-list (todos)
  (ah:</>
   (ul :class "todos"
     (loop for todo in todos
           collect (todo-row todo)))))

(defun session-controls ()
  (let ((u (shiso/auth:current-user)))
    (cond
      (u
       (ah:</>
        (div :class "session"
          (span (format nil "Signed in as ~A. " (shiso/auth:user-email u)))
          (form :method "POST" :action "/logout"
            (csrf-token-input)
            (button :type "submit" "Sign out")))))
      (t
       (ah:</>
        (div :class "session"
          (a :href "/login" "Sign in")
          " or "
          (a :href "/signup" "create an account")
          " to keep tasks across visits."))))))

;;; --------------------------------------------------------------------
;;; Controllers

(defun index ()
  (let* ((todos (models:all-todos))
         (list-content (cond ((null todos) (empty-state))
                             (t (todo-list todos)))))
    (render
     "Todos"
     (ah:</>
      (div
        (h1 "Todos")
        ;; Add-task form
        (form :class "add" :method "POST" :action (s:url "todos:create")
          (csrf-token-input)
          (input :type "text" :name "title" :placeholder "Add a task..."
            :required t :autofocus t)
          (button :type "submit" "Add"))
        list-content
        (session-controls))))))

(defun create ()
  (let* ((body (s:parse-body-params))
         (title (cdr (assoc :title body))))
    (when (and title (plusp (length (string-trim '(#\Space #\Tab) title))))
      (models:create-todo (string-trim '(#\Space #\Tab) title)))
    (s:redirect-response (s:url "todos:index"))))

(defun toggle (id-str)
  (let* ((id (parse-integer id-str :junk-allowed t))
         (todo (models:find-todo id)))
    (when todo (models:toggle-todo todo))
    (s:redirect-response (s:url "todos:index"))))

(defun destroy (id-str)
  (let* ((id (parse-integer id-str :junk-allowed t))
         (todo (models:find-todo id)))
    (when todo (models:delete-todo todo))
    (s:redirect-response (s:url "todos:index"))))
