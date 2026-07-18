(defpackage #:todos/controllers
  (:use #:cl)
  (:local-nicknames (#:s #:shiso)
                    (#:ah #:almighty-html)
                    (#:models #:todos/models)
                    (#:forms #:todos/forms)
                    (#:hy #:todos/hypermedia))
  (:export #:index
           #:create
           #:edit
           #:update
           #:toggle
           #:destroy))

(in-package #:todos/controllers)

(defun render (title body)
  (s:http-response (hy:page title body)))

;;; --------------------------------------------------------------------
;;; Helpers — split out so the index controller stays straight-line and
;;; the if/cond branching stays out of `</>` (which can't introspect
;;; them).

(defun todo-row (todo)
  (let* ((id-str (princ-to-string (mito:object-id todo)))
         (donep (models:done todo))
         (todo-title (models:title todo))
         (li-class (if donep "done" ""))
         (edit-href (s:url "todos:edit" :id id-str)))
    (ah:</>
     (li :class li-class
       ;; Toggle form — not a form object; still needs CSRF.
       (form :method "POST" :action (s:url "todos:toggle" :id id-str)
         (hy:ac-csrf-input)
         (input :type "checkbox" :name "_" :|onChange| "this.form.submit()"
           :checked donep))
       (span :class "title" todo-title)
       (a :href edit-href "Edit")
       (form :class "delete-form" :method "POST"
             :action (s:url "todos:delete" :id id-str)
         (hy:ac-csrf-input)
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
            (hy:ac-csrf-input)
            (button :type "submit" "Sign out")))))
      (t
       (ah:</>
        (div :class "session"
          (a :href "/login" "Sign in")
          " or "
          (a :href "/signup" "create an account")
          " to keep tasks across visits."))))))

(defun add-form-markup (form)
  "Compact inline add form. Uses `field-context' so sticky values and
errors still flow through the form object without `render-form''s full
labeled field chrome."
  (let* ((ctx (s:field-context form 'models:title))
         (name-str (getf ctx :name-string))
         (value (or (getf ctx :value) ""))
         (errors (getf ctx :errors))
         (error-block (when errors
                        (ah:</> (ul :class "field-errors"
                                  (loop :for e :in errors
                                        :collect (ah:</> (li e))))))))
    (ah:</>
     (form :class "add" :method "POST" :action (s:url "todos:create")
       (hy:ac-csrf-input)
       (input :type "text" :name name-str :placeholder "Add a task..."
         :value value :required t :autofocus t)
       (button :type "submit" "Add")
       error-block))))

(defun index-page (add-form)
  (let* ((todos (models:all-todos))
         (list-content (cond ((null todos) (empty-state))
                             (t (todo-list todos))))
         (add-markup (add-form-markup add-form)))
    (render
     "Todos"
     (ah:</>
      (div
        (h1 "Todos")
        add-markup
        list-content
        (session-controls))))))

(defun edit-page (id-str form)
  "Stacked edit form: app-owned `ac-fields' + CSRF + submit."
  (let ((form-body
          (ah:</>
           (form :class "edit" :method "POST"
                 :action (s:url "todos:update" :id id-str)
             (hy:ac-csrf-input)
             (hy:ac-fields :form form)
             (button :type "submit" "Save")))))
    (render
     "Edit todo"
     (ah:</>
      (div
        (h1 "Edit todo")
        form-body
        (a :href (s:url "todos:index") "Back to list"))))))

;;; --------------------------------------------------------------------
;;; Controllers

(defun index ()
  (index-page (forms:make-add-form)))

(defun create ()
  (let ((form (forms:make-add-form :data (s:request-form-data))))
    (cond
      ((s:validate-form form)
       (s:save-form form)
       (s:redirect-response (s:url "todos:index")))
      (t
       (index-page form)))))

(defun edit (id-str)
  (let ((todo (models:find-todo (parse-integer id-str :junk-allowed t))))
    (cond
      ((null todo)
       (s:http-response "Todo not found." :code 404))
      (t
       (edit-page id-str (forms:make-edit-form todo))))))

(defun update (id-str)
  (let ((todo (models:find-todo (parse-integer id-str :junk-allowed t))))
    (cond
      ((null todo)
       (s:http-response "Todo not found." :code 404))
      (t
       (let ((form (forms:make-edit-form todo :data (s:request-form-data))))
         (cond
           ((s:validate-form form)
            (s:save-form form)
            (s:redirect-response (s:url "todos:index")))
           (t
            (edit-page id-str form))))))))

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
