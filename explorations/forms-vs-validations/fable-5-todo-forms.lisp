;;;; fable-5-todo-forms.lisp
;;;;
;;;; The TODO tutorial app (docs/tutorial/05-todo-app.org) rewritten to use
;;;; the shiso Forms feature: `make-model-form' / `validate-form' /
;;;; `save-form' / `render-form'.
;;;;
;;;; Differences from the tutorial as published:
;;;;   - `create' validates and re-displays errors instead of silently
;;;;     dropping a blank title.
;;;;   - An edit view (`edit' / `update') is added, because instance-bound
;;;;     forms are where the Forms layer earns (or fails to earn) its keep.
;;;;   - The add form is rendered by `forms:render-form', so it carries the
;;;;     form layer's markup (div.form-group + label + input) instead of the
;;;;     tutorial's compact inline input. See the assessment for what that
;;;;     trade costs.
;;;;
;;;; Unchanged from the tutorial and therefore omitted here:
;;;;   src/package.lisp, src/routes.lisp, src/main.lisp,
;;;;   src/modules/todos/hypermedia/components.lisp (the `page' renderer).

;;; ---------------------------------------------------------------------
;;; src/modules/todos/models.lisp — identical to the tutorial, plus the
;;; slot metadata now does double duty: :max-length becomes both the DB
;;; column width and an auto-derived form validator.

(defpackage #:todos/models
  (:use #:cl)
  (:export #:title #:done
           #:all-todos #:find-todo))

(in-package #:todos/models)

(shiso:define-model todo
    ((title :field-type :char
            :max-length 200
            :verbose-name "Title"
            :help-text "What needs doing."
            :accessor title)
     (done :field-type :boolean
           :default nil
           :verbose-name "Done?"
           :accessor done)))

(shiso/admin:define-admin todo
  (:list-display title done))

(defun all-todos ()
  "All todos, newest first."
  (mito:select-dao (shiso/models:model-class 'todo)
    (sxql:order-by (:desc :id))))

(defun find-todo (id)
  (when id
    (mito:find-dao (shiso/models:model-class 'todo) :id id)))

;; Note: no create-todo / update-todo / toggle-todo helpers in this
;; version. Creation and update go through `forms:save-form', which
;; writes cleaned form data onto the DAO itself. Only `toggle' still
;; touches the DAO directly (checkbox auto-submit is not a form in the
;; Forms sense).

;;; ---------------------------------------------------------------------
;;; src/modules/todos/controllers.lisp

(defpackage #:todos/controllers
  (:use #:cl)
  (:local-nicknames (#:s #:shiso)
                    (#:ah #:almighty-html)
                    (#:forms #:shiso/forms)
                    (#:models #:todos/models)
                    (#:hy #:todos/hypermedia))
  (:export #:index #:create #:edit #:update #:toggle #:destroy))

(in-package #:todos/controllers)

(defun render (title body)
  (s:http-response (hy:page title body)))

;; Still needed for the toggle/delete/logout micro-forms, which are not
;; form objects. `forms:render-form' injects its own CSRF input, but only
;; for the forms it renders.
(defun csrf-token-input ()
  (let* ((env (lack/request:request-env s:*request*))
         (session (getf env :lack.session))
         (token (and session (lack/middleware/csrf:csrf-token session))))
    (when token
      (ah:</> (input :type "hidden" :name "_csrf_token" :value token)))))

;;; Form constructors — one place that says which fields each view uses.

(defun make-add-form (&key data)
  "The add form exposes only TITLE; DONE stays at its model default."
  (forms:make-model-form "todo"
                         :fields (list 'models:title)
                         :data data))

(defun make-edit-form (todo &key data)
  "The edit form exposes every editable field (TITLE and DONE).
Initial values come from the instance; DONE renders as a checkbox
because the model metadata says :field-type :boolean."
  (forms:make-model-form "todo" :instance todo :data data))

;;; List rendering — unchanged from the tutorial except for the Edit link.

(defun todo-row (todo)
  (let* ((id-str (princ-to-string (mito:object-id todo)))
         (donep (models:done todo))
         (todo-title (models:title todo))
         (li-class (if donep "done" ""))
         (edit-href (s:url "todos:edit" :id id-str)))
    (ah:</>
     (li :class li-class
       (form :method "POST" :action (s:url "todos:toggle" :id id-str)
         (csrf-token-input)
         (input :type "checkbox" :name "_"
                :|onChange| "this.form.submit()" :checked donep))
       (span :class "title" todo-title)
       (a :href edit-href "Edit")
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

;;; Pages.

(defun index-page (add-form)
  "Render the index. ADD-FORM may be a fresh form (GET) or a failed one
(POST re-render) — `render-form' handles both: it re-displays the
submitted value from form-data and shows per-field errors, and it
prepends its own CSRF input."
  (let* ((todos (models:all-todos))
         (list-content (cond ((null todos) (empty-state))
                             (t (todo-list todos))))
         (add-form-html (forms:render-form add-form
                                           :action (s:url "todos:create")
                                           :submit-label "Add")))
    (render
     "Todos"
     (ah:</>
      (div
        (h1 "Todos")
        add-form-html
        list-content
        (session-controls))))))

(defun edit-page (id-str form)
  (let ((form-html (forms:render-form form
                                      :action (s:url "todos:update" :id id-str)
                                      :submit-label "Save")))
    (render
     "Edit todo"
     (ah:</>
      (div
        (h1 "Edit todo")
        form-html
        (a :href (s:url "todos:index") "Back to list"))))))

;;; Controllers. Each is a straight validate → save → redirect | re-render.

(defun index ()
  (index-page (make-add-form)))

(defun create ()
  (let ((form (make-add-form :data (s:parse-body-params))))
    (cond
      ((forms:validate-form form)
       (forms:save-form form)
       (s:redirect-response (s:url "todos:index")))
      (t
       (index-page form)))))

(defun edit (id-str)
  (let ((todo (models:find-todo (parse-integer id-str :junk-allowed t))))
    (if todo
        (edit-page id-str (make-edit-form todo))
        (s:redirect-response (s:url "todos:index")))))

(defun update (id-str)
  (let ((todo (models:find-todo (parse-integer id-str :junk-allowed t))))
    (cond
      ((null todo)
       (s:redirect-response (s:url "todos:index")))
      (t
       ;; The unchecked-checkbox case is handled inside the form layer:
       ;; boolean-field parses an absent param to NIL and is not required,
       ;; so unchecking "Done?" round-trips correctly with no code here.
       (let ((form (make-edit-form todo :data (s:parse-body-params))))
         (cond
           ((forms:validate-form form)
            (forms:save-form form)
            (s:redirect-response (s:url "todos:index")))
           (t
            (edit-page id-str form))))))))

(defun toggle (id-str)
  (let* ((id (parse-integer id-str :junk-allowed t))
         (todo (models:find-todo id)))
    (when todo
      (setf (models:done todo) (not (models:done todo)))
      (mito:save-dao todo))
    (s:redirect-response (s:url "todos:index"))))

(defun destroy (id-str)
  (let* ((id (parse-integer id-str :junk-allowed t))
         (todo (models:find-todo id)))
    (when todo (mito:delete-dao todo))
    (s:redirect-response (s:url "todos:index"))))

;;; ---------------------------------------------------------------------
;;; src/modules/todos/routes.lisp

(defpackage #:todos/routes
  (:use #:cl)
  (:local-nicknames (#:s #:shiso)
                    (#:controllers #:todos/controllers)))

(in-package #:todos/routes)

(s:define-module todos
  (:urls (:GET  "/"            'controllers:index   "index")
         (:POST "/"            'controllers:create  "create")
         (:GET  "/:id/edit"    'controllers:edit    "edit")
         (:POST "/:id"         'controllers:update  "update")
         (:POST "/:id/toggle"  'controllers:toggle  "toggle")
         (:POST "/:id/delete"  'controllers:destroy "delete")))
