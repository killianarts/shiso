;;;; grok-todo-with-forms.lisp
;;;;
;;;; Exploration: TODO create flow rewritten to use Shiso Forms.
;;;;
;;;; Scope: only the pieces that change vs the tutorial's ad-hoc create
;;;; path (examples/todo/). Model, routes, toggle, delete, and the list
;;;; markup are unchanged in spirit.
;;;;
;;;; Not loadable as a standalone system — read as a design sketch.
;;;; Depends on: shiso, shiso/forms, mito, almighty-html.

;;; ----------------------------------------------------------------------
;;; forms.lisp — define the form once, reuse for GET (empty) and POST
;;; (bound data + errors).
;;; ----------------------------------------------------------------------

(defpackage #:todos/forms
  (:use #:cl)
  (:local-nicknames (#:fields #:shiso/forms/fields)
                    (#:form   #:shiso/forms/form)
                    (#:val    #:shiso/validators))
  (:export #:make-todo-form
           #:todo-form))

(in-package #:todos/forms)

(defclass todo-form (form:form) ())

(defun make-todo-form (&key data instance)
  "Build a form for creating (or editing) a Todo.

DATA is an alist of submitted params (keyword or string keys — forms
look up by string-equal on the field name). INSTANCE is a todo DAO for
edit flows; nil for create."
  (make-instance 'todo-form
                 :instance instance
                 :data data
                 :fields (list
                          (make-instance 'fields:char-field
                                         :name 'title
                                         :label "Title"
                                         :help-text "What needs doing."
                                         :max-length 200
                                         :requiredp t
                                         :validators (list (list 'val:max-length 200)
                                                           (list 'val:min-length 1))))))

;;; Alternative: derive fields from the model metadata entirely.
;;;
;;;   (shiso/forms:make-model-form 'todo :data data :instance instance)
;;;
;;; That pulls :max-length / :verbose-name / :help-text / blankp from
;;; define-model. For the tutorial's one-field create form the explicit
;;; make-todo-form above is clearer; model-form wins when admin and
;;; public UI share the same field set.


;;; ----------------------------------------------------------------------
;;; controllers.lisp — create re-renders on error; index embeds render-form
;;; ----------------------------------------------------------------------

(defpackage #:todos/controllers
  (:use #:cl)
  (:local-nicknames (#:s      #:shiso)
                    (#:ah     #:almighty-html)
                    (#:forms  #:shiso/forms)
                    (#:fields #:shiso/forms/fields)
                    (#:models #:todos/models)
                    (#:tf     #:todos/forms)
                    (#:hy     #:todos/hypermedia))
  (:export #:index #:create #:toggle #:destroy))

(in-package #:todos/controllers)

(defun render (title body)
  (s:http-response (hy:page title body)))

(defun csrf-token-input ()
  (let* ((env (lack/request:request-env s:*request*))
         (session (getf env :lack.session))
         (token (and session (lack/middleware/csrf:csrf-token session))))
    (when token
      (ah:</> (input :type "hidden" :name "_csrf_token" :value token)))))

;;; --- list helpers (unchanged from tutorial) ---------------------------

(defun todo-row (todo)
  (let* ((id-str (princ-to-string (mito:object-id todo)))
         (donep (models:done todo))
         (todo-title (models:title todo))
         (li-class (if donep "done" "")))
    (ah:</>
     (li :class li-class
       (form :method "POST" :action (s:url "todos:toggle" :id id-str)
         (csrf-token-input)
         (input :type "checkbox" :name "_"
                :|onChange| "this.form.submit()" :checked donep))
       (span :class "title" todo-title)
       (form :class "delete-form" :method "POST"
             :action (s:url "todos:delete" :id id-str)
         (csrf-token-input)
         (button :type "submit" :class "delete" "Delete"))))))

(defun empty-state ()
  (ah:</> (p "Nothing to do. Add a task above to get started.")))

(defun todo-list (todos)
  (ah:</>
   (ul :class "todos"
     (loop for todo in todos collect (todo-row todo)))))

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

;;; --- form-aware page shell --------------------------------------------

(defun add-form-element (form)
  "Render the add-todo form via shiso/forms:render-form.
CSRF is injected by render-form for non-GET methods."
  (forms:render-form form
                     :action (s:url "todos:create")
                     :method "POST"
                     :submit-label "Add"))

(defun index-page (&optional form)
  "GET index (empty form) or failed POST re-render (form with errors)."
  (let* ((form (or form (tf:make-todo-form)))
         (todos (models:all-todos))
         (list-content (if (null todos) (empty-state) (todo-list todos))))
    (render
     "Todos"
     (ah:</>
      (div
        (h1 "Todos")
        ;; Forms path: one call produces labels, inputs, help text,
        ;; field errors, submit button, and CSRF.
        (add-form-element form)
        list-content
        (session-controls))))))

(defun index ()
  (index-page))

(defun create ()
  "POST / — validate via the form object; save only when valid."
  (let* ((data (s:parse-body-params))
         ;; parse-body-params returns keyword keys; form lookup is
         ;; string-equal on field names, so keywords work in practice.
         (form (tf:make-todo-form :data data)))
    (cond
      ((forms:validate-form form)
       (let ((title (gethash 'title (forms:form-cleaned-data form))))
         (models:create-todo (string-trim '(#\Space #\Tab) title)))
       (s:redirect-response (s:url "todos:index")))
      (t
       ;; Stay on the page with errors and the submitted value preserved.
       ;; (Tutorial version always redirected and silently dropped bad input.)
       (index-page form)))))

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


;;; ----------------------------------------------------------------------
;;; Notes on what Forms bought us for this page
;;; ----------------------------------------------------------------------
;;;
;;; 1. Field definition lives once (make-todo-form): name, label, max
;;;    length, required, validators.
;;; 2. render-form owns HTML shape + CSRF for the add form.
;;; 3. validate-form runs auto + explicit validators, fills cleaned-data
;;;    or per-field errors.
;;; 4. Failed submit re-renders with errors; value is not lost.
;;;
;;; Cost:
;;; - New package + form class + wiring between index and create.
;;; - render-form's default markup (form-group, full label, generic submit)
;;;   does not match the tutorial's compact "flex add bar" CSS without
;;;   either customizing the renderer or abandoning render-form for the
;;;   add UI while still using the form object for validation only.
;;; - Toggle / delete forms stay hand-written (no field data to validate).
;;; - Key/type friction: parse-body-params keywords vs field symbols.
;;;
;;; Reality check: examples/todo/ today does *not* use this path. The
;;; tutorial's create is ~5 lines of ad-hoc trim+length check. This file
;;; is the "if we leaned into Forms" rewrite of that one feature.
)
