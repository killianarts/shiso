;;;; fable-5-todo-validations.lisp
;;;;
;;;; The TODO tutorial app (docs/tutorial/05-todo-app.org) rewritten in
;;;; the validation-first style: no form objects. You declare validations,
;;;; run them against request data, and render your own HTML. This is the
;;;; clavier-shaped approach — here built on `shiso/validators', which is
;;;; already clavier-like (designators → closures returning error strings),
;;;; so no new dependency is needed.
;;;;
;;;; The only new framework-level machinery is `validate-params' (~20
;;;; lines): coerce each param, run its validators, collect cleaned values
;;;; and per-field errors. That helper is what a validation-first shiso
;;;; feature would be, in its entirety.
;;;;
;;;; Same scope as the forms version: create with error re-display, plus
;;;; an edit view. Unchanged tutorial files omitted (src/package.lisp,
;;;; src/routes.lisp, src/main.lisp, hypermedia/components.lisp).

;;; ---------------------------------------------------------------------
;;; src/modules/todos/models.lisp — identical model definition. The
;;; metadata still serves the admin; this version just doesn't derive
;;; forms from it. The plain create/update helpers return.

(defpackage #:todos/models
  (:use #:cl)
  (:export #:title #:done
           #:all-todos #:find-todo #:create-todo #:update-todo))

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

(defun create-todo (title-string)
  (mito:create-dao (shiso/models:model-class 'todo)
                   :title title-string
                   :done nil))

(defun update-todo (todo &key title done)
  (setf (title todo) title
        (done todo) done)
  (mito:save-dao todo))

;;; ---------------------------------------------------------------------
;;; src/modules/todos/validations.lisp — replaces forms.lisp.

(defpackage #:todos/validations
  (:use #:cl)
  (:local-nicknames (#:val #:shiso/validators))
  (:export #:validate-params
           #:trimmed #:checkbox
           #:validate-new-todo #:validate-todo-update))

(in-package #:todos/validations)

;;; Coercers — raw request strings in, Lisp values out. These are the
;;; part the Forms layer normally hides; here they're explicit and
;;; shared by hand.

(defun trimmed (raw)
  "Coerce a raw text param: NIL → \"\", and trim edge whitespace."
  (string-trim '(#\Space #\Tab) (or raw "")))

(defun checkbox (raw)
  "HTML checkboxes send \"on\" when checked and nothing when not."
  (and raw (not (string= raw "")) t))

;;; The generic runner. This is the whole \"framework feature\" of the
;;; validation-first style.

(defun validate-params (params &rest field-specs)
  "Validate PARAMS (an alist as returned by `shiso:parse-body-params').
Each FIELD-SPEC is (KEY &key coerce validators), where COERCE maps the
raw string (or NIL) to a value and VALIDATORS is a list of
`shiso/validators' designators.

Returns (values CLEANED ERRORS). CLEANED is a plist of every coerced
value — including invalid ones, so pages can re-display what the user
typed. ERRORS is an alist of (KEY . error-strings), NIL when valid."
  (let (cleaned errors)
    (dolist (spec field-specs)
      (destructuring-bind (key &key (coerce #'identity) validators) spec
        (let* ((raw (cdr (assoc key params)))
               (value (funcall coerce raw))
               (msgs (val:run-validators validators value)))
          (setf cleaned (list* key value cleaned))
          (when msgs
            (push (cons key msgs) errors)))))
    (values cleaned (nreverse errors))))

;;; Per-view validations. Note the 200 repeats the model's :max-length —
;;; in this style nothing links them; see the assessment.

(defun validate-new-todo (params)
  (validate-params params
                   (list :title
                         :coerce #'trimmed
                         :validators (list 'val:not-blank
                                           '(val:max-length 200)))))

(defun validate-todo-update (params)
  (validate-params params
                   (list :title
                         :coerce #'trimmed
                         :validators (list 'val:not-blank
                                           '(val:max-length 200)))
                   (list :done
                         :coerce #'checkbox)))

;;; ---------------------------------------------------------------------
;;; src/modules/todos/controllers.lisp

(defpackage #:todos/controllers
  (:use #:cl)
  (:local-nicknames (#:s #:shiso)
                    (#:ah #:almighty-html)
                    (#:v #:todos/validations)
                    (#:models #:todos/models)
                    (#:hy #:todos/hypermedia))
  (:export #:index #:create #:edit #:update #:toggle #:destroy))

(in-package #:todos/controllers)

(defun render (title body)
  (s:http-response (hy:page title body)))

(defun csrf-token-input ()
  (let* ((env (lack/request:request-env s:*request*))
         (session (getf env :lack.session))
         (token (and session (lack/middleware/csrf:csrf-token session))))
    (when token
      (ah:</> (input :type "hidden" :name "_csrf_token" :value token)))))

;;; Error display — ours to write, and ours to style exactly as the
;;; tutorial page wants.

(defun field-errors-block (errors key)
  "Render the error list for KEY, or NIL when the field is clean."
  (let ((msgs (cdr (assoc key errors))))
    (when msgs
      (ah:</> (ul :class "field-errors"
                (loop for m in msgs
                      collect (ah:</> (li m))))))))

;;; Hand-rendered forms. The add form keeps the tutorial's compact
;;; inline layout — no wrapper divs, no label — which the Forms layer's
;;; renderer cannot produce. The cost: sticky values, error placement,
;;; and the CSRF input are all manual, in every form.

(defun add-form (&key values errors)
  (let ((title-value (or (getf values :title) ""))
        (title-errors (field-errors-block errors :title)))
    (ah:</>
     (div
       (form :class "add" :method "POST" :action (s:url "todos:create")
         (csrf-token-input)
         (input :type "text" :name "title" :placeholder "Add a task..."
           :value title-value :required t :autofocus t)
         (button :type "submit" "Add"))
       title-errors))))

(defun edit-form (id-str &key values errors)
  (let ((title-value (or (getf values :title) ""))
        (donep (getf values :done))
        (title-errors (field-errors-block errors :title)))
    (ah:</>
     (form :method "POST" :action (s:url "todos:update" :id id-str)
       (csrf-token-input)
       (div :class "form-group"
         (label :for "title" "Title")
         (input :type "text" :name "title" :id "title" :value title-value))
       title-errors
       (div :class "form-group"
         (label
           (input :type "checkbox" :name "done" :id "done" :checked donep)
           " Done?"))
       (button :type "submit" "Save")))))

;;; List rendering — unchanged from the tutorial except the Edit link.

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

(defun index-page (&key add-values add-errors)
  (let* ((todos (models:all-todos))
         (list-content (cond ((null todos) (empty-state))
                             (t (todo-list todos))))
         (form-html (add-form :values add-values :errors add-errors)))
    (render
     "Todos"
     (ah:</>
      (div
        (h1 "Todos")
        form-html
        list-content
        (session-controls))))))

(defun edit-page (id-str &key values errors)
  (let ((form-html (edit-form id-str :values values :errors errors)))
    (render
     "Edit todo"
     (ah:</>
      (div
        (h1 "Edit todo")
        form-html
        (a :href (s:url "todos:index") "Back to list"))))))

;;; Controllers. The data flow is fully visible: params → validate →
;;; plist → model helper. Nothing is keyed by symbols behind the scenes.

(defun index ()
  (index-page))

(defun create ()
  (multiple-value-bind (cleaned errors)
      (v:validate-new-todo (s:parse-body-params))
    (cond
      (errors
       (index-page :add-values cleaned :add-errors errors))
      (t
       (models:create-todo (getf cleaned :title))
       (s:redirect-response (s:url "todos:index"))))))

(defun edit (id-str)
  (let ((todo (models:find-todo (parse-integer id-str :junk-allowed t))))
    (if todo
        ;; Initial values are wired from the instance by hand — the step
        ;; the Forms layer's :instance argument does for free.
        (edit-page id-str
                   :values (list :title (models:title todo)
                                 :done (models:done todo)))
        (s:redirect-response (s:url "todos:index")))))

(defun update (id-str)
  (let ((todo (models:find-todo (parse-integer id-str :junk-allowed t))))
    (cond
      ((null todo)
       (s:redirect-response (s:url "todos:index")))
      (t
       (multiple-value-bind (cleaned errors)
           (v:validate-todo-update (s:parse-body-params))
         (cond
           (errors
            (edit-page id-str :values cleaned :errors errors))
           (t
            (models:update-todo todo
                                :title (getf cleaned :title)
                                :done (getf cleaned :done))
            (s:redirect-response (s:url "todos:index")))))))))

(defun toggle (id-str)
  (let* ((id (parse-integer id-str :junk-allowed t))
         (todo (models:find-todo id)))
    (when todo
      (models:update-todo todo
                          :title (models:title todo)
                          :done (not (models:done todo))))
    (s:redirect-response (s:url "todos:index"))))

(defun destroy (id-str)
  (let* ((id (parse-integer id-str :junk-allowed t))
         (todo (models:find-todo id)))
    (when todo (mito:delete-dao todo))
    (s:redirect-response (s:url "todos:index"))))

;;; ---------------------------------------------------------------------
;;; src/modules/todos/routes.lisp — identical to the forms version.

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
