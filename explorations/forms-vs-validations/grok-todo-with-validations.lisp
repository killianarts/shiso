;;;; grok-todo-with-validations.lisp
;;;;
;;;; Exploration: TODO create flow using a validation-first style, like
;;;; modern stacks (Laravel Form Requests, Rails strong params +
;;;; validations, Phoenix changesets' validate side, Go validator tags)
;;;; and Common Lisp's clavier library.
;;;;
;;;; Idea: request params are plain data. You declare validators, run
;;;; them, get (ok? cleaned errors), then branch. HTML is always hand-
;;;; written (or a separate component). There is no Form object that
;;;; owns both rendering and validation.
;;;;
;;;; Not loadable as a standalone system — design sketch.
;;;; Optional dependency illustrated: clavier (mmontone/clavier).
;;;; Fallback: the same shape with shiso/validators only.


;;; ----------------------------------------------------------------------
;;; validations.lisp — schema for the "create todo" input
;;; ----------------------------------------------------------------------

(defpackage #:todos/validations
  (:use #:cl)
  (:local-nicknames (#:v #:shiso/validators)
                    ;; When clavier is available:
                    ;; (#:clavier #:clavier)
                    )
  (:export #:validate-create-todo
           #:trim-string
           #:param))

(in-package #:todos/validations)

(defun param (params key)
  "Lookup KEY in a parse-body-params alist (keyword keys)."
  (cdr (assoc key params :test #'eq)))

(defun trim-string (s)
  (when s
    (string-trim '(#\Space #\Tab #\Newline #\Return) s)))

;;; --- Version A: clavier-shaped composition (illustrative) -------------
;;;
;;; Clavier builds composable validator objects:
;;;
;;;   (clavier:&& (clavier:not-blank)
;;;               (clavier:is-a-string)
;;;               (clavier:len :min 1 :max 200))
;;;
;;; (funcall validator value :error-p nil)
;;;   => T, nil          on success
;;;   => NIL, "message"  on failure
;;;
;;; Multi-field schemas are not first-class in clavier; you write a
;;; small function that runs field validators and assembles errors.

#+nil
(defparameter *title-validator*
  (clavier:&& (clavier:not-blank)
              (clavier:is-a-string)
              (clavier:len :min 1 :max 200)))

#+nil
(defun validate-create-todo/clavier (params)
  "Return (values cleaned-plist errors-alist).
CLEANED is (:title \"…\") on success.
ERRORS is ((:title . \"message\") …) on failure."
  (let* ((raw (param params :title))
         (title (trim-string raw))
         (errors nil))
    (multiple-value-bind (ok message)
        (funcall *title-validator* title :error-p nil)
      (unless ok
        (push (cons :title (or message "Invalid title.")) errors)))
    (if errors
        (values nil (nreverse errors))
        (values (list :title title) nil))))

;;; --- Version B: same contract with shiso/validators (no new dep) ------

(defparameter *title-validators*
  (list 'v:not-blank
        (list 'v:min-length 1)
        (list 'v:max-length 200)))

(defun validate-create-todo (params)
  "Validate create-todo request data.

PARAMS — alist from shiso:parse-body-params.
Returns two values:
  cleaned  — plist (:title string) when valid, else NIL
  errors   — alist ((:title . \"msg\") …) when invalid, else NIL

This is the only public entry point controllers need."
  (let* ((raw (param params :title))
         (title (trim-string raw))
         ;; not-blank treats "" as invalid; after trim, whitespace-only
         ;; titles become "" and fail the same way.
         (msgs (v:run-validators *title-validators* title)))
    (if msgs
        (values nil (list (cons :title (first msgs))))
        (values (list :title title) nil))))

;;; Cross-field / multi-field example (not needed for todo, but shows
;;; how the pattern scales without a Form class):
;;;
;;; (defun validate-signup (params)
;;;   (let ((errors nil)
;;;         (email (trim-string (param params :email)))
;;;         (p1 (param params :password))
;;;         (p2 (param params :password-confirm)))
;;;     (dolist (msg (v:run-validators (list 'v:not-blank 'v:valid-email) email))
;;;       (push (cons :email msg) errors))
;;;     (dolist (msg (v:run-validators (list (list 'v:min-length 8)) p1))
;;;       (push (cons :password msg) errors))
;;;     (when (and p1 p2 (not (string= p1 p2)))
;;;       (push (cons :__all__ "Passwords do not match.") errors))
;;;     (if errors
;;;         (values nil (nreverse errors))
;;;         (values (list :email email :password p1) nil))))


;;; ----------------------------------------------------------------------
;;; controllers.lisp — validate params; render HTML by hand
;;; ----------------------------------------------------------------------

(defpackage #:todos/controllers
  (:use #:cl)
  (:local-nicknames (#:s      #:shiso)
                    (#:ah     #:almighty-html)
                    (#:val    #:todos/validations)
                    (#:models #:todos/models)
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

;;; --- list helpers (same as tutorial) ----------------------------------

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

;;; --- add form is just HTML; errors/values are optional args -----------

(defun field-error (errors key)
  (cdr (assoc key errors)))

(defun add-form (&key (title-value "") errors)
  "Hand-written markup matching the tutorial's compact CSS.
Optional ERRORS alist and TITLE-VALUE for re-render after failed POST."
  (let ((err (field-error errors :title)))
    (ah:</>
     (form :class "add" :method "POST" :action (s:url "todos:create")
       (csrf-token-input)
       (input :type "text" :name "title" :placeholder "Add a task..."
         :required t :autofocus t :value title-value)
       (button :type "submit" "Add")
       (when err
         (ah:</> (p :class "field-error" err)))))))

(defun index-page (&key (title-value "") errors)
  (let* ((todos (models:all-todos))
         (list-content (if (null todos) (empty-state) (todo-list todos))))
    (render
     "Todos"
     (ah:</>
      (div
        (h1 "Todos")
        (add-form :title-value title-value :errors errors)
        list-content
        (session-controls))))))

(defun index ()
  (index-page))

(defun create ()
  "POST / — validate request data; no Form object involved."
  (let ((params (s:parse-body-params)))
    (multiple-value-bind (cleaned errors)
        (val:validate-create-todo params)
      (cond
        (cleaned
         (models:create-todo (getf cleaned :title))
         (s:redirect-response (s:url "todos:index")))
        (t
         (index-page :title-value (or (val:trim-string (val:param params :title)) "")
                     :errors errors))))))

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
;;; Notes on what validation-first bought us
;;; ----------------------------------------------------------------------
;;;
;;; 1. validate-create-todo is pure: params in, (cleaned | errors) out.
;;;    Easy to unit-test without HTTP, HTML, or form classes.
;;; 2. Markup stays under controller/component control — matches the
;;;    tutorial CSS exactly (form.add flex bar).
;;; 3. No field class hierarchy, no render-form generic methods, no
;;;    cleaned-data hash table keyed by symbols.
;;; 4. CSRF remains an orthogonal concern (hidden input + middleware).
;;;
;;; Cost:
;;; - Labels, widgets, and error presentation are manual per view.
;;; - Model metadata (max-length 200 on define-model) is *not*
;;;   automatically reused; you restate max-length on the validator list
;;;   unless you write a thin bridge from model metadata → validators.
;;; - Admin still wants something form-like (or its own path); the
;;;   public create flow and admin CRUD do not share a form object.
;;;
;;; Closer to: Laravel $request->validate([...]), Phoenix
;;; Changeset.validate_*, Go binding+validator, FastAPI Depends — and to
;;; what examples/todo/ already almost does (inline check), just extracted
;;; into a named validation function with structured errors.
)
